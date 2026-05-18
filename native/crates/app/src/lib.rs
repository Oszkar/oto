#![deny(unsafe_code)]

//! `oto-app` — owns runtime state (the active `Wire`) and routes the
//! discover command and v0.2 playback/volume/state commands.
//! See docs/plans/2026-05-15-frb-discover-command-design.md.
//!
//! # Concurrency model
//!
//! The `Mutex<Option<HeldWire>>` in `SLOT` is held for the **entire
//! duration of each command**, including the blocking SOAP round-trip that
//! happens inside the `Wire` implementation.  This is a deliberate
//! trade-off:
//!
//! - **LAN politeness.** Home networks and Sonos devices are not built for
//!   concurrent SOAP traffic from the same controller.  Serialising all
//!   outbound commands keeps the request rate proportional to the user's
//!   actions.
//! - **Command frequency.** Every entry point here is user-initiated
//!   (play, pause, volume knob, …).  Humans cannot issue commands fast
//!   enough for the serialisation to matter.
//! - **Simplicity.** No fine-grained per-device locking, no queue, no
//!   deadlock surface.
//!
//! Revisit if v0.3 event-pump threads contend on the same lock; at that
//! point a command channel or per-device granularity may be warranted.

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
pub fn discover_with(make: impl FnOnce() -> HeldWire) -> Result<DiscoverySnapshot, WireError> {
    let wire = make();
    let snapshot = wire.discover()?;
    *slot().lock().expect("wire slot poisoned") = Some(wire);
    Ok(snapshot)
}

/// Production entry point: discovery backed by `SonosWire`.
pub fn discover() -> Result<DiscoverySnapshot, WireError> {
    discover_with(|| Box::new(SonosWire::new()))
}

pub fn play(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.play(group))
}

pub fn pause(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.pause(group))
}

pub fn next(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.next(group))
}

pub fn previous(group: &GroupId) -> Result<(), WireError> {
    with_wire(|w| w.previous(group))
}

pub fn set_volume(speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
    with_wire(|w| w.set_volume(speaker, volume))
}

pub fn set_mute(speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
    with_wire(|w| w.set_mute(speaker, muted))
}

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

    /// Serialise all slot-touching tests so that the process-global
    /// `OnceLock<Mutex<Option<HeldWire>>>` does not cause cross-test
    /// interference when `cargo nextest` runs tests in parallel threads.
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
}
