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

mod state_manager;

use std::sync::{Mutex, OnceLock};

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, SpeakerId, SpeakerState, Volume, Wire, WireError,
};
use oto_wire::SonosWire;

use crate::state_manager::StateManager;

// `Send` lets the wire cross threads into the static; `Sync` is not
// needed — all access is serialised by the `Mutex`. Don't add `+ Sync`.
type HeldWire = Box<dyn Wire + Send>;

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
    match guard.as_deref() {
        None => Err(WireError::NotFound("no wire — discover first".into())),
        Some(wire) => f(wire),
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
pub fn discover_with(make: impl FnOnce() -> HeldWire) -> Result<DiscoverySnapshot, WireError> {
    let _discover_guard = discover_lock()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let wire = make();
    let snapshot = wire.discover()?;
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
    //   1. bump_and_clear  →  makes any future apply_*_at_generation
    //      from the OLD consumer no-op (gen mismatch), and clears the
    //      stale cache before the NEW seeds repopulate it.
    //   2. slot replacement → drops the old wire (Sender side of the
    //      old channel), which unblocks the OLD consumer's `recv()`
    //      with Err and lets the consumer exit.
    //
    // The NEW consumer hasn't been spawned yet (the Dart provider
    // depends on `discoveryProvider`; it rebuilds + calls
    // `subscribe_change_events` once this fn returns); it will
    // capture the post-bump generation on entry.
    state_manager().bump_and_clear();
    // Slice 4: install fresh topology so the cache-backed
    // `speaker_state` can resolve speaker → group → transport against
    // the wire we're about to install. Order matters: AFTER
    // bump_and_clear (which also wipes topology) and BEFORE the slot
    // swap (so a `speaker_state` racing past the swap sees consistent
    // topology with empty caches, not stale topology with empty
    // caches).
    state_manager().install_topology(&snapshot);
    *slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(wire);
    Ok(snapshot)
}

/// Production entry point: discovery backed by `SonosWire`.
pub fn discover() -> Result<DiscoverySnapshot, WireError> {
    discover_with(|| Box::new(SonosWire::new()))
}

/// Start playback on `group` (routed to its coordinator).
pub fn play(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.play(group))
}

/// Pause playback on `group` (routed to its coordinator).
pub fn pause(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.pause(group))
}

/// Skip to the next track on `group`.
pub fn next(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.next(group))
}

/// Skip to the previous track on `group`.
pub fn previous(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.previous(group))
}

/// Set `speaker`'s volume (per-speaker, not per-group).
pub fn set_volume(speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
    with_wire(|w| w.set_volume(speaker, volume))
}

/// Set `speaker`'s mute state (per-speaker, not per-group).
pub fn set_mute(speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
    with_wire(|w| w.set_mute(speaker, muted))
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
        .and_then(|w| w.take_event_stream())
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

    use crate::{apply_event_at_generation, current_generation, take_event_stream};

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
        // `gen` is re-read whenever we refresh the receiver (see the
        // `Disconnected` arm). For OLD-wire events buffered before a
        // gen bump, the captured OLD gen is correct — the apply will
        // succeed if gen still matches, or no-op if `bump_and_clear`
        // already ran (matching production semantics). For NEW-wire
        // events arriving after a refresh, the refreshed gen ensures
        // they reach the cache.
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
                *slot_guard = take_event_stream();
                if slot_guard.is_none() {
                    // No wire installed.
                    return count;
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
                    // Wire was replaced — drop this rx, leave the
                    // slot empty so the next iteration re-takes from
                    // the new wire. Re-read the generation so the
                    // NEW receiver's events apply at the NEW gen
                    // (matching what the production NEW consumer in
                    // `api.rs::subscribe_change_events` captures when
                    // it's spawned against the replacement wire).
                    drop(rx);
                    // (slot is already None because we `.take()`d above.)
                    gen = current_generation();
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
}
