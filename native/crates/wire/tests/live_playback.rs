//! LAN-only. Feature-gated AND `#[ignore]`d so CI cannot accidentally
//! run it (needs real Sonos hardware). Run:
//!   cargo nextest run -p oto-wire --features live-tests --test live_playback --run-ignored ignored-only --nocapture
//!
//! Non-destructive: writes volume back to its read value; only toggles
//! transport if already Playing (Pause-when-Stopped → device 500; see
//! docs/plans/2026-05-18-playback-spike-findings.md). Does NOT call
//! next/previous (queue-mutating).

#![cfg(feature = "live-tests")]

use oto_core::Wire;
use oto_wire::SonosWire;

#[test]
#[ignore = "requires a real Sonos LAN"]
fn live_playback_round_trip() {
    let w = SonosWire::new();
    let snap = w.discover().expect("discovery");
    println!(
        "speakers={} groups={}",
        snap.speakers.len(),
        snap.groups.len()
    );

    assert!(!snap.speakers.is_empty(), "expected ≥1 speaker on the LAN");

    // Pick the first speaker and its group.
    // SonosWire::to_snapshot produces group-of-one IDs as "{speaker_id}:0".
    // We iterate snap.groups to find the group whose coordinator matches,
    // so this works for both single-speaker and real multi-device topologies.
    let chosen_speaker = &snap.speakers[0];
    let sid = &chosen_speaker.id;
    let group = snap
        .groups
        .iter()
        .find(|g| g.coordinator == *sid)
        .unwrap_or_else(|| {
            panic!("no group found whose coordinator is {sid}");
        });
    let gid = &group.id;

    println!(
        "chosen speaker: {} [{}] {:?} {}",
        chosen_speaker.room_name, sid, chosen_speaker.model, chosen_speaker.ip
    );
    println!("chosen group: {gid}");

    // ── Volume round-trip (net-zero write) ────────────────────────────────────
    let state_before = w
        .speaker_state(sid)
        .expect("speaker_state before volume round-trip");
    let original_volume = state_before
        .volume
        .expect("speaker must report a volume level");
    println!("volume before: {original_volume}");

    w.set_volume(sid, original_volume)
        .expect("set_volume (same value) must succeed");

    let state_after = w
        .speaker_state(sid)
        .expect("speaker_state after volume round-trip");
    let restored_volume = state_after
        .volume
        .expect("speaker must report a volume level after set");
    println!("volume after:  {restored_volume}");

    assert_eq!(
        original_volume, restored_volume,
        "volume round-trip: write-same-value must leave volume unchanged"
    );

    // ── Transport round-trip (only if already Playing) ────────────────────────
    // Pause-when-Stopped → Sonos device returns HTTP 500 (documented spike
    // finding). We skip transport mutation for any non-Playing initial state.
    let transport = state_before.transport.as_ref();
    match transport.map(|t| &t.state) {
        Some(oto_core::PlaybackState::Playing) => {
            println!("transport: Playing — running pause→play round-trip");

            w.pause(gid).expect("pause must succeed when Playing");
            // Capture post-pause state WITHOUT unwrapping, then restore
            // immediately. `play` must run whenever `pause` succeeded —
            // before any assertion or read failure can abort the test and
            // leave the user's speaker paused. Non-destructiveness depends
            // on this ordering (see the module header).
            let after_pause = w.speaker_state(sid);
            let restore = w.play(gid);

            let paused = after_pause
                .expect("speaker_state after pause")
                .transport
                .expect("transport present after pause");
            println!("transport after pause: {:?}", paused.state);
            assert_eq!(
                paused.state,
                oto_core::PlaybackState::Paused,
                "transport must be Paused after pause"
            );

            restore.expect("play (restore) must succeed");
            let restored = w
                .speaker_state(sid)
                .expect("speaker_state after play restore")
                .transport
                .expect("transport present after play restore");
            println!("transport after play (restore): {:?}", restored.state);
            assert_eq!(
                restored.state,
                oto_core::PlaybackState::Playing,
                "transport must return to Playing after restore"
            );
        }
        Some(state) => {
            println!("transport: {state:?} — skipping transport mutation (only safe when Playing)");
        }
        None => {
            println!("transport: None — speaker reported no transport state; skipping mutation");
        }
    }
}
