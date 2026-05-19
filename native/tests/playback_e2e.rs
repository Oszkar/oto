//! v0.2 PR B acceptance: command→state round-trips proven end-to-end without a LAN.
//!
//! Drives `oto_app`'s routing fns against the stateful `oto_mock::MockWire` —
//! the exact command pathway `api::play/pause/set_volume/…` will use in
//! production.  Zero network; deterministic fixture; proves the domain layer
//! (oto-app + oto-core + oto-mock) before the FRB DTO map is wired in.
//!
//! The DTO-crossing e2e (snapshot + `oto_native::map`) is Task 7 / PR C.
//! A real Sonos LAN run is the user-run hardware smoke in
//! `native/crates/wire/tests/live_playback.rs`.

use oto_app::{discover_with, next, pause, play, previous, set_mute, set_volume, speaker_state};
use oto_core::{GroupId, PlaybackState, SpeakerId, Volume, WireError};
use oto_mock::MockWire;
use oto_native::api::PlaybackStateDto;
use oto_native::map::to_speaker_state_dto;

/// Comprehensive command→state round-trip — the PR B acceptance bar.
///
/// A single `#[test]` function that performs all assertions in sequence.
/// This is intentional: `oto_app` stores its wire in a process-global
/// `OnceLock`; splitting into multiple `#[test]` fns would cause them to
/// fight over the slot under `cargo test` (parallel threads, one process).
/// Under `cargo nextest` each test binary is a separate process, but a
/// single comprehensive test is cheaper and equally clear.
#[test]
fn playback_command_state_round_trips() {
    // ── Fixture IDs ───────────────────────────────────────────────────────────
    let kitchen = SpeakerId::new("RINCON_KITCHEN");
    let office = SpeakerId::new("RINCON_OFFICE");
    let ghost = SpeakerId::new("RINCON_GHOST");

    // MockWire fixture: RINCON_KITCHEN:1 (kitchen + dining), RINCON_OFFICE:0
    let kitchen_group = GroupId::new("RINCON_KITCHEN:1");
    let office_group = GroupId::new("RINCON_OFFICE:0");

    // ── Seed the slot ─────────────────────────────────────────────────────────
    let snap =
        discover_with(|| Box::new(MockWire::default())).expect("mock discovery must succeed");
    assert_eq!(snap.speakers.len(), 3, "fixture must have 3 speakers");
    assert_eq!(snap.groups.len(), 2, "fixture must have 2 groups");

    // ── (a) set_volume round-trip ─────────────────────────────────────────────
    set_volume(&kitchen, Volume::new(63).expect("63 in range")).expect("set_volume must succeed");
    let state_a = speaker_state(&kitchen).expect("speaker_state must succeed after set_volume");
    assert_eq!(
        state_a.volume,
        Some(Volume::new(63).unwrap()),
        "(a) volume must reflect the written value"
    );

    // ── (b) set_mute round-trip ───────────────────────────────────────────────
    set_mute(&office, true).expect("set_mute must succeed");
    let state_b = speaker_state(&office).expect("speaker_state must succeed after set_mute");
    assert_eq!(
        state_b.muted,
        Some(true),
        "(b) muted must reflect the written value"
    );

    // ── (c) play → Playing ────────────────────────────────────────────────────
    play(&kitchen_group).expect("play must succeed");
    let state_c = speaker_state(&kitchen).expect("speaker_state must succeed after play");
    assert_eq!(
        state_c
            .transport
            .expect("transport present after play")
            .state,
        PlaybackState::Playing,
        "(c) transport must be Playing after play"
    );

    // ── (d) pause → Paused ───────────────────────────────────────────────────
    pause(&kitchen_group).expect("pause must succeed");
    let state_d = speaker_state(&kitchen).expect("speaker_state must succeed after pause");
    assert_eq!(
        state_d
            .transport
            .expect("transport present after pause")
            .state,
        PlaybackState::Paused,
        "(d) transport must be Paused after pause"
    );

    // ── (e) next / previous return Ok for known group ─────────────────────────
    next(&office_group).expect("(e) next must return Ok for a known group");
    previous(&office_group).expect("(e) previous must return Ok for a known group");

    // ── (f) unknown id → WireError::NotFound ─────────────────────────────────
    let err_f = speaker_state(&ghost).expect_err("(f) unknown id must return Err");
    assert!(
        matches!(err_f, WireError::NotFound(_)),
        "(f) error must be WireError::NotFound, got: {err_f:?}"
    );
}

/// D2 end-to-end: a grouped non-coordinator's `speaker_state` returns the
/// coordinator's transport, proven across the FRB DTO boundary.
///
/// Harness mirrors `playback_command_state_round_trips`: `discover_with`
/// seeds the slot with `MockWire::default()`, then commands and
/// `speaker_state` are routed through `oto_app`.  The raw `SpeakerState`
/// is then passed through `to_speaker_state_dto` (the same map
/// `api::speaker_state()` applies) and the resulting `PlaybackStateDto` is
/// asserted — proving the full domain→DTO path LAN-free.
///
/// Under `cargo nextest` this runs in its own process so the slot starts
/// fresh; under `cargo test` the earlier test already seeded it, but
/// `discover_with` replaces the wire, so state is still deterministic.
#[test]
fn grouped_non_coordinator_state_is_group_transport() {
    let dining = SpeakerId::new("RINCON_DINING");
    let kitchen_group = GroupId::new("RINCON_KITCHEN:1");

    // Seed the slot — mirrors the pattern in playback_command_state_round_trips.
    discover_with(|| Box::new(MockWire::default())).expect("mock discovery must succeed");

    // Play on the group whose coordinator is Kitchen (Dining is a non-coordinator member).
    play(&kitchen_group).expect("play must succeed on mock");

    // Read Dining's state (non-coordinator) and cross the DTO map.
    let raw = speaker_state(&dining).expect("speaker_state must succeed for Dining");
    let dto = to_speaker_state_dto(raw);

    assert!(
        matches!(
            dto.transport
                .expect("transport must be Some — coordinator was played")
                .state,
            PlaybackStateDto::Playing
        ),
        "D2: non-coordinator Dining must report the coordinator's Playing transport across the map"
    );
}
