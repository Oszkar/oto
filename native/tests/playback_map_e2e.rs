//! v0.2 acceptance: playback commands + speaker_state proven end-to-end
//! without a LAN.
//!
//! Drives `oto_app`'s command routing against the stateful `MockWire`, then
//! crosses the **FRB DTO boundary** via `oto_native::map` - the exact
//! representational map `api::speaker_state()` and `api::{play,pause,…}`
//! apply (`WireError` → `CommandError`, `SpeakerState` → `SpeakerStateDto`).
//! This realises plan deviation D2 for the v0.2 command surface: the e2e
//! asserts the domain state *and* the `oto_native` DTO mapping with zero LAN.
//!
//! # Process-global slot note
//!
//! `oto_app` holds the active wire in a process-global `OnceLock<Mutex<…>>`.
//! Under `cargo nextest` each test runs in a separate process so there are no
//! shared-slot races. Under `cargo test` (threads), multiple tests touching
//! the slot could interleave. We therefore use a **single comprehensive `#[test]`**
//! (the `slot_lifecycle_and_routing` pattern from `oto-app`'s own tests) to
//! avoid any intra-process ordering dependency.

use oto_app::discover_with;
use oto_app::test_helpers::process_pending_events;
use oto_core::WireError;
use oto_mock::MockWire;
use oto_native::api::{CommandError, PlaybackStateDto};
use oto_native::map::{to_command_error, to_speaker_state_dto};
use std::time::Duration;

/// Cache-backed `speaker_state` needs the consumer loop driven between
/// mutations and reads. 50 ms is well above any realistic MockWire
/// emit-to-drain delay.
const DRAIN_WINDOW: Duration = Duration::from_millis(50);

#[test]
fn playback_commands_and_state_cross_the_dto_map() {
    // ── 1. Discover against MockWire ─────────────────────────────────────────
    let snap = discover_with(|| Box::new(MockWire::default())).expect("mock discovery succeeds");
    assert_eq!(snap.speakers.len(), 3, "fixture has 3 speakers");
    // Drain seeds so the post-discover cache reads see anything.
    process_pending_events(DRAIN_WINDOW);

    // ── 2. set_volume → speaker_state → to_speaker_state_dto ─────────────────
    let kitchen = oto_core::SpeakerId::new("RINCON_KITCHEN");
    oto_app::set_volume(&kitchen, oto_core::Volume::new(72).unwrap())
        .expect("set_volume succeeds on mock");
    process_pending_events(DRAIN_WINDOW);

    let raw_state = oto_app::speaker_state(&kitchen).expect("speaker_state succeeds on mock");
    assert_eq!(raw_state.volume, Some(oto_core::Volume::new(72).unwrap()));

    let dto = to_speaker_state_dto(raw_state);
    assert_eq!(
        dto.volume,
        Some(72u32),
        "Volume newtype unwraps to u32 across the map"
    );
    assert_eq!(dto.muted, Some(false), "seed muted=false passes through");

    let transport = dto.transport.expect("transport is Some after seeding");
    assert!(
        matches!(transport.state, PlaybackStateDto::Stopped),
        "initial transport is Stopped"
    );

    // ── 3. pause → transport DTO state ───────────────────────────────────────
    let kitchen_group = oto_core::GroupId::new("RINCON_KITCHEN:1");
    oto_app::pause(&kitchen_group).expect("pause succeeds on mock");
    process_pending_events(DRAIN_WINDOW);

    let paused_state =
        oto_app::speaker_state(&kitchen).expect("speaker_state after pause succeeds");
    let paused_dto = to_speaker_state_dto(paused_state);
    let paused_transport = paused_dto.transport.expect("transport Some after pause");
    assert!(
        matches!(paused_transport.state, PlaybackStateDto::Paused),
        "pause command maps transport state to Paused across the DTO"
    );

    // ── 4. WireError::NotFound crosses to_command_error ──────────────────────
    // A fresh `MockWire::failing` has an empty model; any command returns
    // WireError::NotFound. We drive to_command_error directly (the function
    // api::play() et al. call) to prove the error map LAN-free.
    let not_found_err = WireError::NotFound("RINCON_GHOST".into());
    assert!(
        matches!(
            to_command_error(not_found_err),
            CommandError::NotFound(m) if m == "RINCON_GHOST"
        ),
        "NotFound passes through to_command_error unchanged"
    );

    // Backend → Sonos is the non-obvious rename; verify it crosses correctly.
    let backend_err = WireError::Backend("soap fault".into());
    assert!(
        matches!(
            to_command_error(backend_err),
            CommandError::Sonos(m) if m == "soap fault"
        ),
        "Backend maps to CommandError::Sonos across the DTO boundary"
    );

    // NoDevicesFound (exhaustive arm) → NotFound("no devices discovered").
    assert!(
        matches!(
            to_command_error(WireError::NoDevicesFound),
            CommandError::NotFound(m) if m == "no devices discovered"
        ),
        "NoDevicesFound exhaustive arm maps to NotFound"
    );
}
