#![deny(unsafe_code)]

//! `oto-app` — owns runtime state (the active `Wire`) and routes the
//! discover command and v0.2 playback/volume/state commands.
//! See docs/plans/2026-05-15-frb-discover-command-design.md.
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

use std::sync::{Mutex, OnceLock};

use oto_core::{DiscoverySnapshot, GroupId, SpeakerId, SpeakerState, Volume, Wire, WireError};
use oto_wire::SonosWire;

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
pub fn speaker_state(speaker: &SpeakerId) -> Result<SpeakerState, WireError> {
    with_wire(|w| w.speaker_state(speaker))
}

// ── Test-only helpers ─────────────────────────────────────────────────────────

#[cfg(test)]
fn clear_slot() {
    *slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
}

#[cfg(test)]
mod tests {
    use super::*;
    use oto_core::{PlaybackState, Volume};
    use oto_mock::MockWire;
    use std::sync::Mutex;

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

        // ── 3. set_volume + speaker_state round-trip through held wire ────
        set_volume(&kitchen, Volume::new(55).unwrap()).unwrap();
        assert_eq!(
            speaker_state(&kitchen).unwrap().volume,
            Some(Volume::new(55).unwrap())
        );

        // ── 4. Transport commands ─────────────────────────────────────────
        let kitchen_group = GroupId::new("RINCON_KITCHEN:1");
        let office_group = GroupId::new("RINCON_OFFICE:0");

        play(&kitchen_group).unwrap();
        assert_eq!(
            speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Playing
        );

        pause(&kitchen_group).unwrap();
        assert_eq!(
            speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Paused
        );

        // MockWire next/previous are coordinator-lookup stubs (no queue
        // model); meaningful state assertion is deferred to Task 6 /
        // the SonosWire hardware smoke.
        next(&office_group).unwrap();
        previous(&office_group).unwrap();

        // mute round-trip
        let office = SpeakerId::new("RINCON_OFFICE");
        set_mute(&office, true).unwrap();
        assert_eq!(speaker_state(&office).unwrap().muted, Some(true));

        // ── 5. Failing discover leaves prior wire intact ──────────────────
        let err = discover_with(|| Box::new(MockWire::failing(WireError::NoDevicesFound)));
        assert_eq!(err, Err(WireError::NoDevicesFound));
        // Prior wire still there: state from step 3 survives
        assert_eq!(
            speaker_state(&kitchen).unwrap().volume,
            Some(Volume::new(55).unwrap())
        );

        // ── 6. Second successful discover replaces the wire ───────────────
        // The new MockWire::default() seeds kitchen volume at SEED_VOLUME (30),
        // not the 55 we wrote in step 3 — proving replacement, not retention.
        discover_with(|| Box::new(MockWire::default())).unwrap();
        let vol_after_replace = speaker_state(&kitchen).unwrap().volume.unwrap();
        assert_ne!(
            vol_after_replace,
            Volume::new(55).unwrap(),
            "second discover must replace the wire, not keep the old one"
        );
        // SEED_VOLUME is 30; confirm we got the fresh seed, not the old value.
        assert_eq!(vol_after_replace, Volume::new(30).unwrap());
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
