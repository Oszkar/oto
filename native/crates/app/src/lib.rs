#![deny(unsafe_code)]

//! `oto-app` — owns runtime state (the active `Wire`) and routes the
//! discover command and the playback/volume/state commands.
//! See `docs/ARCHITECTURE.md` for the command flow and the `Wire` seam.
//!
//! # Concurrency model
//!
//! Two process-global locks, with distinct scopes:
//!
//! - **`SLOT` (`Mutex<Option<HeldWire>>`)** is held for the **entire
//!   duration of each command**, including the blocking SOAP round-trip
//!   that happens inside the `Wire` implementation. This is a deliberate
//!   trade-off:
//!
//!   - **LAN politeness.** Home networks and Sonos devices are not built
//!     for concurrent SOAP traffic from the same controller. Serialising
//!     all outbound commands keeps the request rate proportional to the
//!     user's actions.
//!   - **Command frequency.** Every entry point here is user-initiated
//!     (play, pause, volume knob, …). Humans cannot issue commands fast
//!     enough for the serialisation to matter.
//!   - **Simplicity.** No fine-grained per-device locking, no queue, no
//!     deadlock surface.
//!
//!   Revisit if v0.4 event-pump threads contend on the same lock; at that
//!   point a command channel or per-device granularity may be warranted.
//!
//! - **`StateManager` `RwLock`s (per-speaker / per-group / topology)** —
//!   added in v0.4 (Slices 1–4). Independent of `SLOT`. The FRB-worker
//!   consumer loop in `api.rs::subscribe_change_events` takes one of
//!   these write locks per `ChangeEvent` applied (short hold — one
//!   variant dispatch + one HashMap insert); the cache-backed
//!   `speaker_state` takes read locks. Production runs through v0.4
//!   dogfooding (spec § 8.7–§ 8.9) showed no observable contention
//!   between event-apply writes and command-time `SLOT` holds. The
//!   reasoning: event throughput is bounded by Sonos's GENA cadence
//!   (~120 events/min for a 4-speaker household at the spike's
//!   baseline), and `SLOT` writes happen only on user commands —
//!   different time scales, different access patterns. Lock-granularity
//!   audit per spec § 5.4 lands here: no narrowing needed for v0.4. The
//!   v0.5 topology-events stream lands on the same channel and the
//!   same apply_event path; revisit only if event volume + command
//!   volume produce visible latency.
//!
//! - **`DISCOVER_LOCK` (`Mutex<()>`)** is held for the duration of one
//!   `discover_with` call — across `make()`, `wire.discover()`, and the
//!   slot replacement. It serialises *discoveries against each other*
//!   without touching the slot lock, so playback commands and discovery
//!   live on independent serialisation surfaces.
//!
//!   Why a second lock: `wire.discover()` is the longest blocking call
//!   in the system (3 s SSDP + a SOAP `GetZoneGroupState` per responder),
//!   and the old design released the slot lock before that call started
//!   and re-took it after. Two overlapping `discover_with` calls (the
//!   `discoveryProvider` is autoDispose-d, so a remount-during-discovery
//!   re-fires it) could finish in any order, and last-writer-wins on the
//!   slot let an *older* snapshot overwrite a *newer* wire. Serialising
//!   the whole discover_with call gives deterministic ordering — the
//!   `discover_with` that acquires the lock last is the one whose wire
//!   ends up in the slot.

mod events;
mod health;
mod state_manager;

use std::sync::{Mutex, OnceLock};

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, SpeakerId, SpeakerState, Volume, Wire, WireError,
};
use oto_wire::SonosWire;

use crate::health::HealthTracker;
use crate::state_manager::StateManager;

// Re-export the FRB consumer's drain hook for the app-originated event bus
// (v0.5 S2). `api.rs::subscribe_change_events` interleaves this with the
// wire channel. See `events.rs` for the dual-channel rationale.
pub use crate::events::try_recv_app_event;

// `Send` lets the wire cross threads into the static; `Sync` is not
// needed — all access is serialised by the `Mutex`. Don't add `+ Sync`.
type BoxedWire = Box<dyn Wire + Send>;

/// The installed wire paired with the `StateManager` generation it was
/// installed under. Pairing them in the slot lets the FRB consumer take
/// its receiver and its generation **atomically** (one slot-lock
/// acquisition) — see [`take_event_stream_with_generation`]. Without the
/// pairing the consumer could take an OLD wire's receiver and then read a
/// NEWER generation (a concurrent rediscover bumped it between the two
/// reads), applying the old wire's buffered events into the new wire's
/// freshly-seeded cache.
struct HeldWire {
    wire: BoxedWire,
    generation: u64,
}

fn slot() -> &'static Mutex<Option<HeldWire>> {
    static SLOT: OnceLock<Mutex<Option<HeldWire>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(None))
}

/// Process-global serialisation for `discover_with`. Held across the
/// whole call (make + wire.discover + slot replacement) so two
/// overlapping discoveries cannot finish out of acquisition order and
/// overwrite each other's wire in the slot. See the module doc-comment.
fn discover_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

/// Process-global event-fed cache. Mutated by the FRB-worker consumer
/// loop in `api.rs::subscribe_change_events` via `apply_event`, cleared
/// by `discover_with` on every wire replacement.
fn state_manager() -> &'static StateManager {
    static SM: OnceLock<StateManager> = OnceLock::new();
    SM.get_or_init(StateManager::new)
}

/// Process-global per-speaker subscription-health tracker (v0.5 S2).
/// Observed by command dispatch; reset by `discover_with` on wire
/// replacement. Emits `SubscriptionError`/`Recovered` onto the app event
/// bus (`events::push`) on health transitions.
fn health_tracker() -> &'static HealthTracker {
    static HT: OnceLock<HealthTracker> = OnceLock::new();
    HT.get_or_init(HealthTracker::new)
}

/// Observe a per-speaker command's result and emit a health-transition
/// event onto the app bus if the speaker's `Healthy ↔ Errored` state flips.
/// The event is stamped with the current wire generation so the FRB consumer
/// can drop it if a rediscover has since replaced the wire (events.rs #3).
fn observe_speaker_health<R>(speaker: &SpeakerId, result: &Result<R, WireError>) {
    if let Some(event) = health_tracker().observe(speaker, result) {
        events::push(state_manager().current_generation(), event);
    }
}

/// Observe a group-addressed command's result against the group's
/// coordinator (the speaker the command was routed to). No-op if the
/// coordinator can't be resolved (unknown/stale group) — the command's own
/// `NotFound` already conveys that, and health is reachability-only.
fn observe_group_health<R>(group: &GroupId, result: &Result<R, WireError>) {
    if let Some(coordinator) = state_manager().coordinator_of(group) {
        observe_speaker_health(&coordinator, result);
    }
}

/// Lock the slot and call `f` with the held wire, returning
/// `Err(WireError::NotFound)` if no discovery has been run yet.
///
/// The lock is held across the entire call to `f`, which means it spans
/// the blocking SOAP call inside the `Wire` implementation.  See the
/// module-level doc comment for the rationale.
fn with_wire<R>(f: impl FnOnce(&dyn Wire) -> Result<R, WireError>) -> Result<R, WireError> {
    let guard = slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    match guard.as_ref() {
        None => Err(WireError::NotFound("no wire — discover first".into())),
        Some(held) => f(&*held.wire),
    }
}

/// Construct a wire, run discovery, and on success replace the held
/// wire (so v0.2 playback can act on it). On failure the previously
/// held wire — if any — is left intact.
///
/// `DISCOVER_LOCK` is held for the full call so two overlapping
/// discoveries serialise; the slot lock is only taken at the very end
/// for the replacement, so playback commands are *not* blocked for the
/// 3 s SSDP + SOAP window. See the module doc-comment.
pub fn discover_with(make: impl FnOnce() -> BoxedWire) -> Result<DiscoverySnapshot, WireError> {
    let _discover_guard = discover_lock()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let wire = make();
    let snapshot = wire.discover()?;
    // v0.5 (S1): register topology-event interest BEFORE subscribe_speakers.
    // subscribe_speakers builds the event pump and (for SonosWire) the SDK
    // manager moves into the pump thread, so the GroupMembership watch must
    // be requested first — subscribe_speakers reads the flag when it spawns
    // the pump. Idempotent on the wire; a logic-bug error here (discover()
    // just succeeded) propagates as a discovery failure.
    wire.subscribe_topology()?;
    // v0.4: activate the subscription before installing the wire so
    // `take_event_stream` is callable as soon as the slot is replaced.
    // A NoSpeakersDiscovered here would be a logic bug (discover()
    // just succeeded), but treat any error as a discovery failure.
    wire.subscribe_speakers()?;
    // ── Race window between OLD and NEW wire ─────────────────────────
    //
    // At this point the NEW wire's pump is live (subscribe_speakers
    // succeeded) and queueing events into its tx channel; the old
    // wire is still in the slot, and its consumer loop in
    // `api.rs::subscribe_change_events` may still be calling
    // `apply_event_at_generation(old_gen, ...)` against `state_manager`.
    //
    // Order (intentional):
    //   1. bump_clear_and_install → bumps the generation (so any future
    //      apply_*_at_generation from the OLD consumer no-ops on the gen
    //      mismatch), clears the stale property caches, and installs the
    //      NEW topology — in one step. Folding the topology install into
    //      the bump means there is never a window where a wire is present
    //      but the topology map is empty (which would make a concurrent
    //      `speaker_state` spuriously return NotFound for a speaker that
    //      exists in both topologies — L5). It returns the generation it
    //      bumped to, which we pin to the wire in the slot swap below.
    //   2. slot replacement → installs the NEW wire PAIRED with that
    //      generation, and drops the old wire (Sender side of the old
    //      channel), which unblocks the OLD consumer's `recv()` with Err
    //      and lets the consumer exit.
    //
    // The NEW consumer hasn't been spawned yet (the Dart provider
    // depends on `discoveryProvider`; it rebuilds + calls
    // `subscribe_change_events` once this fn returns); it takes its
    // (generation, receiver) pair atomically from the slot on entry
    // (`take_event_stream_with_generation`).
    let generation = state_manager().bump_clear_and_install(&snapshot);
    // v0.5 S2: a fresh wire starts with a clean health slate — drop any
    // Errored marks from the old wire so the first command on the new wire
    // is judged from Healthy (and a recovery on the new wire isn't masked).
    health_tracker().reset_all();
    // …and drop any app-bus event still queued against the OLD wire, so a
    // stale SubscriptionError/Recovered can't surface on the NEW stream
    // after rediscover (review #65). Health just reset, so it'd be wrong.
    events::clear();
    *slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(HeldWire { wire, generation });
    Ok(snapshot)
}

/// Production entry point: discovery backed by `SonosWire`.
pub fn discover() -> Result<DiscoverySnapshot, WireError> {
    discover_with(|| Box::new(SonosWire::new()))
}

/// v0.5.1 (Option D): the topology fast-path — a "discover() minus SSDP".
///
/// Re-pull authoritative topology from the CURRENT wire (no SSDP) to get the
/// reachable speaker IPs, then install a FRESH wire seeded from them through
/// the proven wire-replacement lifecycle. Going through `discover_with` (not a
/// same-wire pump respawn) is load-bearing: it bumps the generation AND, on the
/// Dart side, drives a `discoveryProvider` transition, so `wireGeneration`
/// recomputes and the event stream re-subscribes against the new wire's fresh
/// pump (clean `TopologyFilter`). A same-wire respawn would bump the Rust
/// generation but NOT trigger the Dart `discoveryProvider` transition, so Dart
/// would never re-take the new receiver and events would silently stop after
/// the first regroup.
pub fn refresh_topology() -> Result<DiscoverySnapshot, WireError> {
    // `with_wire` releases SLOT before returning; `refresh_topology_with` →
    // `discover_with` then acquires DISCOVER_LOCK → SLOT independently — no lock
    // inversion. Two GetZoneGroupState SOAP calls happen (one here for the IPs,
    // one in the seeded `discover()`), each ~tens of ms — still far under the
    // ~3-5 s SSDP sweep this replaces.
    let snapshot = with_wire(|w| w.refresh_topology())?;
    let ips: Vec<std::net::IpAddr> = snapshot.speakers.iter().map(|s| s.ip).collect();
    refresh_topology_with(move || Box::new(SonosWire::new_seeded(ips)))
}

/// Test seam (mirrors `discover`/`discover_with`): install a fresh wire via the
/// proven `discover_with` path. Production passes the seeded-`SonosWire`
/// factory (see [`refresh_topology`]); tests pass a `MockWire` factory.
pub fn refresh_topology_with(
    make: impl FnOnce() -> BoxedWire,
) -> Result<DiscoverySnapshot, WireError> {
    discover_with(make)
}

/// Start playback on `group` (routed to its coordinator).
pub fn play(group: &GroupId) -> Result<(), WireError> {
    let result = with_wire(|w| w.play(group));
    observe_group_health(group, &result);
    result
}

/// Pause playback on `group` (routed to its coordinator).
pub fn pause(group: &GroupId) -> Result<(), WireError> {
    let result = with_wire(|w| w.pause(group));
    observe_group_health(group, &result);
    result
}

/// Skip to the next track on `group`.
pub fn next(group: &GroupId) -> Result<(), WireError> {
    let result = with_wire(|w| w.next(group));
    observe_group_health(group, &result);
    result
}

/// Skip to the previous track on `group`.
pub fn previous(group: &GroupId) -> Result<(), WireError> {
    let result = with_wire(|w| w.previous(group));
    observe_group_health(group, &result);
    result
}

/// Set `speaker`'s volume (per-speaker, not per-group).
pub fn set_volume(speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
    let result = with_wire(|w| w.set_volume(speaker, volume));
    observe_speaker_health(speaker, &result);
    result
}

/// Set `speaker`'s mute state (per-speaker, not per-group).
pub fn set_mute(speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
    let result = with_wire(|w| w.set_mute(speaker, muted));
    observe_speaker_health(speaker, &result);
    result
}

/// v0.5.1: set `group`'s master volume (routed to its coordinator). Health is
/// attributed to the coordinator the command was routed to.
pub fn set_group_volume(group: &GroupId, volume: Volume) -> Result<(), WireError> {
    let result = with_wire(|w| w.set_group_volume(group, volume));
    observe_group_health(group, &result);
    result
}

/// v0.5.1: set `group`'s master mute state (routed to its coordinator). Health
/// is attributed to the coordinator the command was routed to.
pub fn set_group_mute(group: &GroupId, muted: bool) -> Result<(), WireError> {
    let result = with_wire(|w| w.set_group_mute(group, muted));
    observe_group_health(group, &result);
    result
}

/// v0.5.1: fold `speaker` into `coordinator`'s group. Additive; the settled
/// topology surfaces via the debounced `GroupMembership` topology-event path
/// (no self-trigger here). Health is attributed to the joiner — the speaker
/// the join SOAP is sent to.
pub fn join_group(speaker: &SpeakerId, coordinator: &SpeakerId) -> Result<(), WireError> {
    let result = with_wire(|w| w.join_group(speaker, coordinator));
    observe_speaker_health(speaker, &result);
    result
}

/// v0.5.1: detach `speaker` into its own standalone group. Additive; the
/// settled topology surfaces via the debounced `GroupMembership`
/// topology-event path (no self-trigger here).
pub fn leave_group(speaker: &SpeakerId) -> Result<(), WireError> {
    let result = with_wire(|w| w.leave_group(speaker));
    observe_speaker_health(speaker, &result);
    result
}

/// One-shot read of `speaker`'s current volume/mute/transport snapshot.
///
/// **Slice 4:** reads from the `StateManager` cache instead of
/// dispatching through `Wire::speaker_state`. The trait method is kept
/// (the production `SonosWire` still implements it via SOAP — used by
/// the hardware-gated live tests for baseline reads; `MockWire` still
/// implements it for its own unit tests). But `oto_app::speaker_state`
/// — and therefore every FRB caller — is now event-fed: a speaker's
/// volume/mute reflect the most recent ChangeEvent applied to the
/// `StateManager`, and transport resolves via speaker → group →
/// group-cache using the topology installed by `discover_with`.
///
/// **Error contract preserved from v0.3:**
///   - No wire installed → `NotFound("no wire — discover first")`.
///   - Wire installed but `speaker` not in the topology → `NotFound(id)`.
///   - Wire installed AND speaker in topology → `Ok(SpeakerState)` with
///     honest-partial fields (`None` for any property whose event
///     hasn't landed in the cache yet).
///
/// The topology check matters: without it, a typo'd `speaker_id` from
/// the Dart layer would silently return `SpeakerState { None, None,
/// None }` instead of surfacing as an error. Topology is the source
/// of truth for "is this id real?"; the per-speaker cache only
/// promises freshness of values for ids that exist.
pub fn speaker_state(speaker: &SpeakerId) -> Result<SpeakerState, WireError> {
    let guard = slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.is_none() {
        return Err(WireError::NotFound("no wire — discover first".into()));
    }
    drop(guard);
    if !state_manager().is_known_speaker(speaker) {
        return Err(WireError::NotFound(speaker.to_string()));
    }
    Ok(state_manager().speaker_state(speaker))
}

/// Hand the v0.4 event-stream receiver to the FRB consumer loop.
/// Called by `api.rs::subscribe_change_events`. Returns `None` if no
/// wire is installed yet, or if the receiver has already been taken
/// (one consumer per wire — per spec § 4 + FRB pre-check § 5).
pub fn take_event_stream() -> Option<std::sync::mpsc::Receiver<ChangeEvent>> {
    slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .as_ref()
        .and_then(|held| held.wire.take_event_stream())
}

/// Hand the FRB consumer its event-stream receiver **paired with the
/// generation the wire was installed under**, both read under one slot
/// lock so a concurrent `discover_with` cannot slip a generation bump
/// between "take receiver" and "read generation". The consumer applies
/// events at this generation; once a later `discover_with` bumps the
/// `StateManager` past it, those applies no-op — so a lingering OLD-wire
/// consumer cannot pollute the NEW wire's freshly-seeded cache. Returns
/// `None` if no wire is installed or the receiver was already taken (one
/// consumer per wire).
pub fn take_event_stream_with_generation() -> Option<(u64, std::sync::mpsc::Receiver<ChangeEvent>)>
{
    let guard = slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let held = guard.as_ref()?;
    let generation = held.generation;
    held.wire.take_event_stream().map(|rx| (generation, rx))
}

/// Generation-aware apply — no-op if `gen` doesn't match the current
/// `state_manager` generation. The FRB consumer loop captures the
/// generation once at start, then passes it on every event so a
/// `discover_with` that bumps mid-stream causes any in-flight writes
/// from the OLD wire's consumer to be dropped before they corrupt the
/// NEW wire's freshly-seeded cache.
pub fn apply_event_at_generation(gen: u64, event: &ChangeEvent) {
    state_manager().apply_event_at_generation(gen, event);
}

/// Snapshot the current `state_manager` generation. Captured by the
/// FRB consumer loop on entry; see `apply_event_at_generation`.
pub fn current_generation() -> u64 {
    state_manager().current_generation()
}

/// Read a speaker's cached volume — used by Slice 4's
/// cache-backed `speaker_state`. v0.4 read surface; the full cache
/// API lands in Task 2 / Slice 4 of this plan.
pub fn cached_volume(speaker: &SpeakerId) -> Option<Volume> {
    state_manager().volume_of(speaker)
}

/// Read a speaker's cached mute state. Slice 4 read surface.
pub fn cached_muted(speaker: &SpeakerId) -> Option<bool> {
    state_manager().muted_of(speaker)
}

/// Read a group's cached transport. Slice 4 read surface.
pub fn cached_transport(group: &GroupId) -> Option<oto_core::TransportState> {
    state_manager().transport_of(group)
}

/// Read a group's cached current track. Slice 4 read surface.
pub fn cached_track(group: &GroupId) -> Option<oto_core::Track> {
    state_manager().track_of(group)
}

/// Read a group's cached GroupRenderingControl volume (v0.5.1). Event-fed;
/// `None` until the first GroupVolume event lands for that group.
pub fn cached_group_volume(group: &GroupId) -> Option<Volume> {
    state_manager().group_volume_of(group)
}

/// Read a group's cached GroupRenderingControl mute state (v0.5.1). Event-fed;
/// `None` until the first GroupMute event lands for that group.
pub fn cached_group_muted(group: &GroupId) -> Option<bool> {
    state_manager().group_muted_of(group)
}

// ── Test helpers ──────────────────────────────────────────────────────────────
//
// Slice 4 swapped `speaker_state` to a cache-backed read, which means
// command-then-read round-trips in tests need the consumer loop to run
// between the mutation and the read. The FRB consumer
// (`api::subscribe_change_events`) is the production path; the helpers
// below offer a synchronous equivalent so unit tests AND cross-crate
// integration tests (in `native/tests/`) can drive the same pipeline.
//
// Exposed via `#[doc(hidden)] pub` rather than `#[cfg(test)]` so the
// integration tests, which live in a separate compilation unit, can
// reach them. Don't call from production paths.

/// Test-only helpers — see module-level "Test helpers" section above
/// for context. Marked `#[doc(hidden)]` to keep them out of public
/// docs while still cross-crate-visible.
#[doc(hidden)]
pub mod test_helpers {
    use std::sync::mpsc::Receiver;
    use std::sync::{Mutex, OnceLock};

    use oto_core::ChangeEvent;

    use crate::{apply_event_at_generation, current_generation, take_event_stream_with_generation};

    /// Process-static holder for the held wire's event receiver during
    /// tests. The receiver is one-shot per wire, but a test may drain
    /// it many times (after each mutation); this slot keeps it across
    /// calls within one test process.
    ///
    /// Refreshed automatically when the held wire is replaced: a
    /// `Disconnected` error on `recv_timeout` means the OLD wire's
    /// `Sender` dropped, so the helper drops the stale rx and re-takes
    /// the NEW wire's stream on the next iteration.
    fn test_event_rx() -> &'static Mutex<Option<Receiver<ChangeEvent>>> {
        static RX: OnceLock<Mutex<Option<Receiver<ChangeEvent>>>> = OnceLock::new();
        RX.get_or_init(|| Mutex::new(None))
    }

    /// Drain events from the held wire's channel and apply each to
    /// `StateManager` (mirrors the FRB consumer loop in
    /// `api.rs::subscribe_change_events`). Designed for the "mutate →
    /// drain → read cache" pattern.
    ///
    /// Returns the number of events applied. Caps drain to `timeout`
    /// so a hung sender can't lock up a test; under MockWire
    /// (synchronous auto-emit on every command) a 50 ms budget is
    /// plenty.
    ///
    /// Auto-refreshes the receiver when the held wire is replaced. The
    /// captured generation is re-read after a `Disconnected` (i.e.
    /// whenever a fresh receiver is taken) so that NEW-wire events
    /// land at the NEW generation — without this, a wire replacement
    /// mid-drain would silently no-op every subsequent apply against
    /// the stale (pre-bump) generation.
    pub fn process_pending_events(timeout: std::time::Duration) -> usize {
        let deadline = std::time::Instant::now() + timeout;
        // `gen` is paired with the receiver whenever we (re)take the
        // stream via `take_event_stream_with_generation` (the refill
        // below + the `Disconnected` arm). For OLD-wire events buffered
        // before a gen bump, the captured OLD gen is correct — the apply
        // succeeds if gen still matches, or no-ops if a rediscover already
        // bumped (matching production semantics). For NEW-wire events
        // arriving after a refresh, the re-paired gen ensures they reach
        // the cache.
        let mut gen = current_generation();
        let mut count = 0;
        loop {
            if std::time::Instant::now() >= deadline {
                break;
            }
            // Acquire-then-release pattern: only hold the test-rx slot
            // lock long enough to refresh or read the receiver, never
            // across the `recv_timeout` blocking call.
            let mut slot_guard = test_event_rx()
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if slot_guard.is_none() {
                // Take the receiver and its wire's generation together so
                // NEW-wire events apply at the NEW generation (mirrors the
                // production consumer's atomic pairing).
                match take_event_stream_with_generation() {
                    Some((g, rx)) => {
                        gen = g;
                        *slot_guard = Some(rx);
                    }
                    // No wire installed.
                    None => return count,
                }
            }
            // Drop the guard before the (potentially blocking) recv —
            // holding the Mutex across recv would needlessly serialise
            // any concurrent helper. (`process_pending_events` is
            // called serially in practice; this is purely defensive.)
            let rx = slot_guard.take().expect("just installed above");
            drop(slot_guard);

            let remaining = deadline.saturating_duration_since(std::time::Instant::now());
            let step = remaining.min(std::time::Duration::from_millis(10));
            match rx.recv_timeout(step) {
                Ok(ev) => {
                    apply_event_at_generation(gen, &ev);
                    count += 1;
                    // Put the receiver back so the next iteration can
                    // continue draining.
                    *test_event_rx().lock().unwrap_or_else(|p| p.into_inner()) = Some(rx);
                }
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                    // No more events for now — put the receiver back
                    // and exit. (Don't busy-loop within the timeout.)
                    *test_event_rx().lock().unwrap_or_else(|p| p.into_inner()) = Some(rx);
                    break;
                }
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                    // Wire was replaced — drop this rx, leave the slot
                    // empty so the next iteration re-takes (rx, gen)
                    // together via `take_event_stream_with_generation`,
                    // which re-pairs `gen` with the NEW wire (mirroring
                    // the production NEW consumer in
                    // `api.rs::subscribe_change_events`).
                    drop(rx);
                    // (slot is already None because we `.take()`d above.)
                }
            }
        }
        count
    }

    /// Drop any stored test receiver so the next test process / test
    /// fn starts clean. Called from oto-app's own `clear_slot` between
    /// tests; integration-test crates don't need to call it directly
    /// (each nextest test runs in a fresh process).
    pub fn reset_rx() {
        *test_event_rx().lock().unwrap_or_else(|p| p.into_inner()) = None;
    }
}

#[cfg(test)]
fn clear_slot() {
    *slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    // Cache survives across tests in the same process otherwise; clear it
    // so the next test starts from a known-empty state.
    state_manager().clear();
    // S2: clear per-speaker health so a prior test's Errored mark doesn't
    // leak into the next test (same process under `cargo test`).
    health_tracker().reset_all();
    // S2: drain any app-bus events a prior test pushed so they don't leak
    // (gen-agnostic — clear() empties the channel regardless of stamp).
    events::clear();
    // Drop any stranded test receiver so the next test starts clean.
    test_helpers::reset_rx();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_helpers::process_pending_events;
    use oto_core::{PlaybackState, Volume};
    use oto_mock::MockWire;
    use std::sync::Mutex;
    use std::time::Duration;

    /// How long unit tests are willing to wait when draining MockWire
    /// events into the StateManager cache. MockWire emits synchronously
    /// from its own command thread, so 50 ms is comfortably more than
    /// any realistic drain — but enough that a CI host under load
    /// shouldn't flake.
    const DRAIN_WINDOW: Duration = Duration::from_millis(50);

    /// Serialises all slot-touching tests under `cargo test`, which runs
    /// tests in parallel threads within one process; redundant but
    /// harmless under `cargo nextest` (a separate process per test).
    static TEST_SERIAL: Mutex<()> = Mutex::new(());

    /// Test-only `Wire` that wraps `Arc<MockWire>` so a test can keep a
    /// reference to the mock after `discover_with` boxes it into the slot,
    /// then introspect it (e.g. `topology_subscribed()`). Mirrors the
    /// `MockWireArc` pattern in `native/src/api.rs`'s dev seam.
    struct ArcWire(std::sync::Arc<MockWire>);

    impl Wire for ArcWire {
        fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
            self.0.discover()
        }
        fn play(&self, g: &GroupId) -> Result<(), WireError> {
            self.0.play(g)
        }
        fn pause(&self, g: &GroupId) -> Result<(), WireError> {
            self.0.pause(g)
        }
        fn next(&self, g: &GroupId) -> Result<(), WireError> {
            self.0.next(g)
        }
        fn previous(&self, g: &GroupId) -> Result<(), WireError> {
            self.0.previous(g)
        }
        fn set_volume(&self, s: &SpeakerId, v: Volume) -> Result<(), WireError> {
            self.0.set_volume(s, v)
        }
        fn set_mute(&self, s: &SpeakerId, m: bool) -> Result<(), WireError> {
            self.0.set_mute(s, m)
        }
        fn set_group_volume(&self, g: &GroupId, v: Volume) -> Result<(), WireError> {
            self.0.set_group_volume(g, v)
        }
        fn set_group_mute(&self, g: &GroupId, m: bool) -> Result<(), WireError> {
            self.0.set_group_mute(g, m)
        }
        fn join_group(&self, s: &SpeakerId, c: &SpeakerId) -> Result<(), WireError> {
            self.0.join_group(s, c)
        }
        fn leave_group(&self, s: &SpeakerId) -> Result<(), WireError> {
            self.0.leave_group(s)
        }
        fn speaker_state(&self, s: &SpeakerId) -> Result<SpeakerState, WireError> {
            self.0.speaker_state(s)
        }
        fn subscribe_speakers(&self) -> Result<(), WireError> {
            self.0.subscribe_speakers()
        }
        fn subscribe_topology(&self) -> Result<(), WireError> {
            self.0.subscribe_topology()
        }
        fn refresh_topology(&self) -> Result<DiscoverySnapshot, WireError> {
            self.0.refresh_topology()
        }
        fn take_event_stream(&self) -> Option<std::sync::mpsc::Receiver<ChangeEvent>> {
            self.0.take_event_stream()
        }
    }

    /// Comprehensive slot test:
    ///
    /// 1. Pre-discover routing → NotFound.
    /// 2. Successful discover stores a wire; snapshot has 3 speakers.
    /// 3. Routing commands are forwarded to the held wire (set_volume / speaker_state).
    /// 4. Transport commands work (play / pause / next / previous).
    /// 5. A failing discover leaves the prior wire intact.
    /// 6. A second successful discover replaces the wire (old mutations gone).
    #[test]
    fn slot_lifecycle_and_routing() {
        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        // ── 0. Clean slate ────────────────────────────────────────────────
        clear_slot();

        // ── 1. Pre-discover routing returns NotFound ──────────────────────
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        assert!(matches!(
            speaker_state(&kitchen),
            Err(WireError::NotFound(_))
        ));
        assert!(matches!(
            set_volume(&kitchen, Volume::new(55).unwrap()),
            Err(WireError::NotFound(_))
        ));

        // ── 2. Successful discover: snapshot + slot populated ─────────────
        let snap = discover_with(|| Box::new(MockWire::default())).unwrap();
        assert_eq!(snap.speakers.len(), 3);
        // Slice 4: drain the subscribe_speakers seed events into the
        // StateManager cache so the post-discover reads below see
        // anything at all. (Before Slice 4 these reads dispatched
        // through MockWire which reported state directly; now they
        // read the event-fed cache, so the consumer loop must run.)
        process_pending_events(DRAIN_WINDOW);

        // ── 3. set_volume + speaker_state round-trip via cache ────────────
        // MockWire::set_volume auto-emits a Volume event (mirroring real
        // Sonos NOTIFY); draining applies it to the cache; speaker_state
        // reads back from the cache.
        set_volume(&kitchen, Volume::new(55).unwrap()).unwrap();
        process_pending_events(DRAIN_WINDOW);
        assert_eq!(
            speaker_state(&kitchen).unwrap().volume,
            Some(Volume::new(55).unwrap())
        );

        // ── 4. Transport commands ─────────────────────────────────────────
        let kitchen_group = GroupId::new("RINCON_KITCHEN:1");
        let office_group = GroupId::new("RINCON_OFFICE:0");

        play(&kitchen_group).unwrap();
        process_pending_events(DRAIN_WINDOW);
        assert_eq!(
            speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Playing
        );

        pause(&kitchen_group).unwrap();
        process_pending_events(DRAIN_WINDOW);
        assert_eq!(
            speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Paused
        );

        // MockWire next/previous are coordinator-lookup stubs (no queue
        // model, no event emit); meaningful state assertion is deferred
        // to the SonosWire hardware smoke.
        next(&office_group).unwrap();
        previous(&office_group).unwrap();

        // mute round-trip
        let office = SpeakerId::new("RINCON_OFFICE");
        set_mute(&office, true).unwrap();
        process_pending_events(DRAIN_WINDOW);
        assert_eq!(speaker_state(&office).unwrap().muted, Some(true));

        // ── 5. Failing discover leaves prior wire intact ──────────────────
        let err = discover_with(|| Box::new(MockWire::failing(WireError::NoDevicesFound)));
        assert_eq!(err, Err(WireError::NoDevicesFound));
        // Prior wire still there: state from step 3 survives in the
        // cache (failed discover doesn't bump_and_clear).
        assert_eq!(
            speaker_state(&kitchen).unwrap().volume,
            Some(Volume::new(55).unwrap())
        );

        // ── 6. Second successful discover replaces the wire ───────────────
        // The new MockWire::default() seeds kitchen volume at SEED_VOLUME (30),
        // not the 55 we wrote in step 3 — proving replacement, not retention.
        // bump_and_clear wiped the cache; install_topology refreshed the
        // speaker→group map; then subscribe_speakers seeded the NEW wire's
        // events. Draining brings the seeds into the cache.
        discover_with(|| Box::new(MockWire::default())).unwrap();
        process_pending_events(DRAIN_WINDOW);
        let vol_after_replace = speaker_state(&kitchen).unwrap().volume.unwrap();
        assert_ne!(
            vol_after_replace,
            Volume::new(55).unwrap(),
            "second discover must replace the wire, not keep the old one"
        );
        // SEED_VOLUME is 30; confirm we got the fresh seed, not the old value.
        assert_eq!(vol_after_replace, Volume::new(30).unwrap());
    }

    /// Discover-with auto-invokes `subscribe_speakers` on the wire it
    /// installs, so a Dart consumer that calls `subscribe_change_events`
    /// (which is what `take_event_stream` underpins) sees seed events
    /// without the caller having to drive subscription itself.
    ///
    /// PR #43 only exercised this transitively through the Dart
    /// integration test (`v0_4_events_test.dart`). Pin the Rust-level
    /// contract directly so the wire-installation path stays honest
    /// even when the Dart layer is being reshaped.
    #[test]
    fn discover_with_auto_invokes_subscribe_speakers() {
        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        clear_slot();

        // `discover_with` is expected to call `subscribe_speakers`
        // internally; absent that call, `take_event_stream` would
        // return None even though the wire is installed.
        let snap = discover_with(|| Box::new(MockWire::default())).expect("discover ok");
        assert_eq!(snap.speakers.len(), 3, "fixture sanity");

        let rx = take_event_stream().expect(
            "discover_with must auto-invoke subscribe_speakers — without it the \
             MockWire's tx channel is None and the receiver is unreachable",
        );

        // Drain seed events until the channel goes quiet. Slice 2
        // expanded the mock's seed set (Volume + Mute + Playback —
        // see `MockWire::subscribe_speakers`); rather than hardcode
        // the exact count, count the Volume seeds specifically and
        // assert ≥3 (one per fixture speaker). A regression that
        // dropped the subscribe call would surface as zero events
        // arriving in the recv_timeout window.
        let mut volume_seeds = 0usize;
        let mut total_seeds = 0usize;
        loop {
            match rx.recv_timeout(std::time::Duration::from_millis(50)) {
                Ok(ChangeEvent::Volume { .. }) => {
                    volume_seeds += 1;
                    total_seeds += 1;
                }
                Ok(_) => total_seeds += 1,
                Err(_) => break,
            }
            if total_seeds > 32 {
                panic!("seed phase produced > 32 events; runaway");
            }
        }
        assert!(
            volume_seeds >= 3,
            "subscribe_speakers must emit ≥3 Volume seeds for the 3-speaker fixture; got {volume_seeds} (total seeds: {total_seeds})"
        );
    }

    /// v0.5 (S1): `discover_with` must auto-invoke `subscribe_topology` so
    /// the topology-event watch is active without the caller driving it.
    /// The `MockWire::topology_subscribed()` introspection confirms the
    /// call happened. (Ordering — topology before speakers — is enforced
    /// at the wire layer; here we only assert it was invoked.)
    #[test]
    fn discover_with_auto_invokes_subscribe_topology() {
        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        clear_slot();

        // Hold an Arc to the mock so we can introspect it after install.
        let mock = std::sync::Arc::new(MockWire::default());
        let mock_probe = std::sync::Arc::clone(&mock);
        discover_with(move || Box::new(ArcWire(mock))).expect("discover ok");
        assert!(
            mock_probe.topology_subscribed(),
            "discover_with must call subscribe_topology on the installed wire"
        );
    }

    /// v0.5.1 (Option D): `refresh_topology_with` installs a fresh wire via the
    /// proven `discover_with` path — so it returns a snapshot AND bumps the
    /// generation, exactly like a re-discover. (Production's `refresh_topology`
    /// first re-pulls IPs from the current wire, then calls this with a
    /// seeded-`SonosWire` factory; here we drive the seam directly with a
    /// `MockWire`, which is what the FRB layer relies on for the gen bump that
    /// makes Dart re-subscribe.)
    #[test]
    fn refresh_topology_with_installs_fresh_wire_and_bumps_generation() {
        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        clear_slot();

        // Seed an initial wire so there's a generation to bump from.
        discover_with(|| Box::new(MockWire::default())).expect("initial discover ok");
        let gen_before = current_generation();

        // The fast-path seam: a fresh wire goes in via discover_with, so the
        // snapshot comes back and the generation advances by one.
        let snap = refresh_topology_with(|| Box::new(MockWire::default()))
            .expect("refresh_topology_with ok");
        assert_eq!(snap.speakers.len(), 3, "fixture snapshot returned");
        assert_eq!(
            current_generation(),
            gen_before + 1,
            "refresh installs a fresh wire → generation bumps (Dart re-subscribes)"
        );
    }

    /// Production `refresh_topology` re-pulls the topology from the CURRENT wire
    /// (via `with_wire(refresh_topology)`) before seeding the new wire — so it
    /// requires a wire to be installed first. Pin that precondition: with no
    /// wire installed it returns `NotFound`, same as any other `with_wire`
    /// command.
    #[test]
    fn refresh_topology_without_wire_is_not_found() {
        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        clear_slot();
        assert!(matches!(refresh_topology(), Err(WireError::NotFound(_))));
    }

    // ── S2: SubscriptionError reactive emission ───────────────────────────

    /// Drain every app-bus event currently queued at the current generation
    /// (the S2 sibling channel). Mirrors the FRB consumer, which drains with
    /// the wire generation it captured at start.
    fn drain_app_events() -> Vec<ChangeEvent> {
        let gen = current_generation();
        let mut out = Vec::new();
        while let Some(e) = try_recv_app_event(gen) {
            out.push(e);
        }
        out
    }

    /// Build a discovered wire from an `Arc<MockWire>` the test still holds,
    /// so the test can arrange command errors before/after `discover_with`.
    fn discover_with_held_mock() -> std::sync::Arc<MockWire> {
        let mock = std::sync::Arc::new(MockWire::default());
        let for_app = std::sync::Arc::clone(&mock);
        discover_with(move || Box::new(ArcWire(for_app))).expect("discover ok");
        mock
    }

    #[test]
    fn subscription_error_emitted_on_first_network_failure() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        let mock = discover_with_held_mock();
        let _ = drain_app_events(); // ignore anything from setup
        mock.set_command_error(&kitchen, WireError::Network("unreachable".into()));

        let res = set_volume(&kitchen, Volume::new(50).unwrap());
        assert!(matches!(res, Err(WireError::Network(_))));

        let events = drain_app_events();
        assert_eq!(events.len(), 1, "exactly one SubscriptionError");
        assert!(matches!(
            &events[0],
            ChangeEvent::SubscriptionError { speaker, .. } if *speaker == kitchen
        ));
    }

    #[test]
    fn subscription_error_not_repeated_on_repeated_failures() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        let mock = discover_with_held_mock();
        let _ = drain_app_events();
        mock.set_command_error(&kitchen, WireError::Network("unreachable".into()));

        let _ = set_volume(&kitchen, Volume::new(50).unwrap());
        let _ = set_volume(&kitchen, Volume::new(51).unwrap());
        let _ = set_mute(&kitchen, true);

        let events = drain_app_events();
        assert_eq!(
            events.len(),
            1,
            "edge-triggered: only the first failure emits"
        );
    }

    #[test]
    fn subscription_recovered_after_error_then_success() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        let mock = discover_with_held_mock();
        let _ = drain_app_events();
        mock.set_command_error(&kitchen, WireError::Network("unreachable".into()));
        let _ = set_volume(&kitchen, Volume::new(50).unwrap()); // → Errored
        let _ = drain_app_events(); // consume the SubscriptionError

        mock.clear_command_error(&kitchen); // device back
        let res = set_volume(&kitchen, Volume::new(60).unwrap());
        assert!(res.is_ok());

        let events = drain_app_events();
        assert_eq!(events.len(), 1);
        assert!(matches!(
            &events[0],
            ChangeEvent::SubscriptionRecovered { speaker } if *speaker == kitchen
        ));
    }

    #[test]
    fn backend_error_does_not_emit_health_event() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        let mock = discover_with_held_mock();
        let _ = drain_app_events();
        mock.set_command_error(&kitchen, WireError::Backend("soap fault".into()));

        let _ = set_volume(&kitchen, Volume::new(50).unwrap());

        assert!(
            drain_app_events().is_empty(),
            "Backend error is not a reachability signal — no health event"
        );
    }

    #[test]
    fn group_command_failure_attributes_to_coordinator() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        // Kitchen group's coordinator is RINCON_KITCHEN (fixture).
        let coord = SpeakerId::new("RINCON_KITCHEN");
        let group = GroupId::new("RINCON_KITCHEN:1");

        let mock = discover_with_held_mock();
        let _ = drain_app_events();
        mock.set_command_error(&coord, WireError::Network("unreachable".into()));

        let res = play(&group);
        assert!(matches!(res, Err(WireError::Network(_))));

        let events = drain_app_events();
        assert_eq!(events.len(), 1, "group failure → one SubscriptionError");
        assert!(
            matches!(&events[0], ChangeEvent::SubscriptionError { speaker, .. } if *speaker == coord),
            "attributed to the group's coordinator"
        );
    }

    #[test]
    fn health_state_resets_on_wire_replacement() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        // Wire 1: drive kitchen to Errored.
        let mock1 = discover_with_held_mock();
        let _ = drain_app_events();
        mock1.set_command_error(&kitchen, WireError::Network("unreachable".into()));
        let _ = set_volume(&kitchen, Volume::new(50).unwrap());
        assert_eq!(drain_app_events().len(), 1, "errored on wire 1");

        // Rediscover (wire 2) → health reset. A successful command must NOT
        // emit Recovered (the speaker is Healthy again, not Errored).
        let _mock2 = discover_with_held_mock();
        let _ = drain_app_events();
        let res = set_volume(&kitchen, Volume::new(60).unwrap());
        assert!(res.is_ok());
        assert!(
            drain_app_events().is_empty(),
            "health reset on rediscover — no stale Recovered event"
        );
    }

    #[test]
    fn speaker_state_read_does_not_trigger_health_check() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        let _mock = discover_with_held_mock();
        let _ = drain_app_events();

        // speaker_state is a cache read (no SOAP, no command dispatch).
        let _ = speaker_state(&kitchen);

        assert!(
            drain_app_events().is_empty(),
            "cache-read speaker_state must not observe health"
        );
    }

    #[test]
    fn discover_with_clears_stale_app_events() {
        let _guard = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        clear_slot();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        // Queue a SubscriptionError on wire 1 and deliberately DON'T drain
        // it (simulates an event still in the bus when rediscover starts).
        let mock = discover_with_held_mock();
        let _ = drain_app_events();
        mock.set_command_error(&kitchen, WireError::Network("unreachable".into()));
        let _ = set_volume(&kitchen, Volume::new(50).unwrap());

        // Rediscover: health resets, so the queued event is stale and must
        // be dropped — it must not surface on the new stream (review #65).
        let _ = discover_with_held_mock();
        assert!(
            drain_app_events().is_empty(),
            "rediscover must clear stale app-bus events"
        );
    }

    /// Regression for the concurrent-`discover()` race: the old design
    /// ran `wire.discover()` *outside* any lock and only locked the slot
    /// for the final write, so two overlapping discoveries could finish
    /// in any order and the slower one would last-writer-wins overwrite
    /// the faster one's wire — losing whatever fresh topology the user
    /// just observed.
    ///
    /// `DISCOVER_LOCK` now serialises the full call (make + discover +
    /// slot replacement), so two discoveries are strictly sequential.
    /// This test asserts mutual exclusion by counting concurrent
    /// occupants of the critical section: a shared atomic counter is
    /// incremented at the top of `make()` and decremented at the end;
    /// with the lock in place the observed maximum is exactly 1. The
    /// `make()` body sleeps long enough that, absent the lock, the
    /// second thread would observe the first still inside.
    #[test]
    fn discover_with_serialises_concurrent_calls() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;
        use std::thread;
        use std::time::Duration;

        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());

        clear_slot();

        let in_make = Arc::new(AtomicUsize::new(0));
        let max_concurrent = Arc::new(AtomicUsize::new(0));

        let spawn_one = |in_make: Arc<AtomicUsize>, max_concurrent: Arc<AtomicUsize>| {
            thread::spawn(move || {
                discover_with(move || {
                    let cur = in_make.fetch_add(1, Ordering::SeqCst) + 1;
                    // `fetch_max` records the high-water mark of concurrent
                    // make() occupants observed across both threads.
                    max_concurrent.fetch_max(cur, Ordering::SeqCst);
                    // Sleep long enough that, without the lock, the second
                    // thread is guaranteed to enter make() while the first
                    // is still inside (50 ms is well above any realistic
                    // thread-spawn latency).
                    thread::sleep(Duration::from_millis(50));
                    // Build the wire into a local so the closure's tail
                    // expression is `Box::new(local)`, not
                    // `Box::new(T::default())` — the latter trips
                    // clippy::box_default, which would otherwise suggest
                    // `Box::default()`. That suggestion doesn't compile
                    // here because the closure's inferred return type
                    // is `Box<dyn Wire + Send>` (no Default impl); the
                    // box-then-coerce path keeps the unsize coercion at
                    // the return site.
                    let wire = MockWire::default();
                    in_make.fetch_sub(1, Ordering::SeqCst);
                    Box::new(wire)
                })
                .expect("discover ok")
            })
        };

        let t1 = spawn_one(Arc::clone(&in_make), Arc::clone(&max_concurrent));
        let t2 = spawn_one(Arc::clone(&in_make), Arc::clone(&max_concurrent));
        t1.join().expect("t1");
        t2.join().expect("t2");

        assert_eq!(
            max_concurrent.load(Ordering::SeqCst),
            1,
            "DISCOVER_LOCK must serialise overlapping discover_with calls; \
             a regression to the pre-fix design would observe 2 here"
        );
        assert_eq!(
            in_make.load(Ordering::SeqCst),
            0,
            "both make() bodies must have run to completion"
        );
    }

    /// M1: the FRB consumer must take its event-stream receiver and the
    /// generation it applies at as ONE atomic pair, so a rediscover can't
    /// slip a generation bump between "take receiver" and "read
    /// generation" (which would let an OLD wire's buffered events apply
    /// into the NEW wire's freshly-seeded cache).
    /// `take_event_stream_with_generation` returns the generation the
    /// installed wire was paired with; a second discover bumps it, and the
    /// new wire's receiver pairs with the bumped value.
    #[test]
    fn event_stream_receiver_is_paired_with_its_wire_generation() {
        let _guard = TEST_SERIAL
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        clear_slot();

        // Wire 1: receiver pairs with the generation it was installed under.
        discover_with(|| Box::new(MockWire::default())).unwrap();
        let gen_1 = current_generation();
        let (paired_1, _rx1) = take_event_stream_with_generation().expect("wire 1 installed");
        assert_eq!(
            paired_1, gen_1,
            "receiver handed out paired with its wire's install generation"
        );

        // Rediscover: new wire, bumped generation, atomically re-paired.
        discover_with(|| Box::new(MockWire::default())).unwrap();
        let gen_2 = current_generation();
        assert_eq!(gen_2, gen_1 + 1, "rediscover bumps the generation");
        let (paired_2, _rx2) = take_event_stream_with_generation().expect("wire 2 installed");
        assert_eq!(
            paired_2, gen_2,
            "wire 2's receiver pairs with the bumped gen"
        );
        assert_ne!(
            paired_1, paired_2,
            "the two wires' receivers carry distinct generations — an OLD-wire \
             event applied at paired_1 no-ops once paired_2 is current"
        );
    }
}
