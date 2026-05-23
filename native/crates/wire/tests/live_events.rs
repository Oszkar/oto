//! LAN-only. Feature-gated AND `#[ignore]`d so CI cannot accidentally
//! run it (needs real Sonos hardware). Run:
//!   cargo nextest run -p oto-wire --features live-tests --test live_events \
//!     --run-ignored ignored-only --nocapture
//!
//! Verifies the v0.4 Path A pump end-to-end against the 4-speaker LAN:
//!   1. `subscribe_speakers` + seed NOTIFYs arrive within 2 s of subscribe.
//!   2. Operator volume change in the Sonos app → `ChangeEvent::Volume`
//!      within sub-second latency (spec § 8.1, design target 500 ms).
//!   3. Operator play/pause → `ChangeEvent::Playback` carrying the
//!      group's `GroupId` (NOT the coordinator's `SpeakerId` —
//!      coordinator-only filter must apply per-group addressing).
//!   4. Long-running renewal cycle observation (≥ 26 min idle; renewal
//!      at ~25 min per spike finding #8). Extra-ignored so it only runs
//!      when explicitly invoked.
//!
//! The two interactive tests (#2, #3) require the operator to act
//! within a 5 s window — they print a prompt to stderr and wait. The
//! seed-NOTIFY test (#1) is fully automatic.

#![cfg(feature = "live-tests")]

use std::collections::HashSet;
use std::time::{Duration, Instant};

use oto_core::{ChangeEvent, GroupId, SpeakerId, Wire};
use oto_wire::SonosWire;

/// Test #1 — fully automatic. Subscribe and assert the SDK's first
/// SUBSCRIBE NOTIFY seeds Volume on ≥ 2 of the 4 speakers within 2 s.
/// (≥ 2 not 4 because speakers in standby can take >2 s to respond;
/// the spike consistently saw 4/4 but we use 2 as the floor to avoid
/// flake.)
#[test]
#[ignore = "requires a real Sonos LAN"]
fn subscribe_then_seed_notifies_arrive() {
    let wire = SonosWire::new();
    wire.discover().expect("discovery ok");
    wire.subscribe_speakers().expect("subscribe ok");
    let rx = wire.take_event_stream().expect("rx available");

    let deadline = Instant::now() + Duration::from_secs(2);
    let mut volume_speakers: HashSet<_> = HashSet::new();
    while Instant::now() < deadline {
        if let Ok(ChangeEvent::Volume { speaker, .. }) = rx.recv_timeout(Duration::from_millis(100))
        {
            volume_speakers.insert(speaker);
        }
    }
    println!(
        "[live_events] saw seed Volume for {} speakers: {:?}",
        volume_speakers.len(),
        volume_speakers
    );
    assert!(
        volume_speakers.len() >= 2,
        "expected ≥ 2 Volume seeds within 2 s; got {volume_speakers:?}"
    );
}

/// Test #2 — interactive. Prompts the operator to change a speaker's
/// volume in the Sonos app and asserts the matching `ChangeEvent::Volume`
/// arrives within sub-second latency.
///
/// **False-positive guard (Copilot review on PR #45):** pre-fetches a
/// per-speaker volume baseline via the v0.3 SOAP path before subscribing
/// and only accepts `Volume` events whose value DIFFERS from baseline.
/// This filters late-arriving seed NOTIFYs that report a speaker's
/// existing volume — without the baseline check, a slow-to-seed speaker
/// could deliver its seed AFTER the 2 s drain and falsely trip the test.
#[test]
#[ignore = "live-only — manual: change a speaker volume in the Sonos app within 5 s"]
fn operator_volume_change_within_500ms() {
    use std::collections::HashMap;

    let wire = SonosWire::new();
    let snap = wire.discover().expect("discovery ok");

    // Pre-fetch baseline volumes via the v0.3 SOAP path. This gives a
    // deterministic per-speaker reference; events whose value matches
    // are seeds (or no-ops), not the operator's action.
    let mut baseline: HashMap<SpeakerId, u8> = HashMap::new();
    for s in &snap.speakers {
        if let Ok(state) = wire.speaker_state(&s.id) {
            if let Some(v) = state.volume {
                baseline.insert(s.id.clone(), v.get());
            }
        }
    }
    println!(
        "[live_events] captured {} baseline volumes via SOAP",
        baseline.len()
    );

    wire.subscribe_speakers().expect("subscribe ok");
    let rx = wire.take_event_stream().expect("rx available");

    // Drain seed events for 2 s — these arrive from the initial
    // SUBSCRIBE NOTIFYs and shouldn't count as the operator action.
    // The baseline check below also catches any late seeds that
    // straggle past this window.
    let drain_until = Instant::now() + Duration::from_secs(2);
    while Instant::now() < drain_until {
        let _ = rx.recv_timeout(Duration::from_millis(100));
    }

    eprintln!();
    eprintln!(">>> CHANGE A SPEAKER VOLUME IN THE SONOS APP NOW (5 s window) <<<");
    eprintln!();
    let start = Instant::now();
    let deadline = start + Duration::from_secs(5);
    while Instant::now() < deadline {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(ChangeEvent::Volume { speaker, volume }) => {
                let new = volume.get();
                match baseline.get(&speaker) {
                    Some(&old) if old == new => {
                        // Late seed or no-op write. Update baseline so
                        // subsequent events for this speaker compare
                        // against the most-recent observed value.
                        println!("[live_events] (filtered no-change Volume for {speaker}: {old})");
                        baseline.insert(speaker, new);
                    }
                    _ => {
                        // Either a real change (different from baseline)
                        // OR a Volume event for a speaker whose baseline
                        // SOAP read failed — treat as the operator action.
                        let elapsed = start.elapsed();
                        println!(
                            "[live_events] Volume {} → {} (baseline {:?}) after {:?}",
                            speaker,
                            new,
                            baseline.get(&speaker),
                            elapsed
                        );
                        assert!(
                            elapsed < Duration::from_millis(500),
                            "event arrived in {elapsed:?}, design target ≤ 500 ms"
                        );
                        return;
                    }
                }
            }
            Ok(other) => {
                // Other event variants are fine (Mute, Track, …) — only
                // a Volume change counts for this assertion.
                println!("[live_events] (ignoring non-Volume event: {other:?})");
            }
            Err(_) => { /* timeout — keep polling until deadline */ }
        }
    }
    panic!("no Volume event within 5 s of the operator prompt");
}

/// Test #3 — interactive. Prompts the operator to play/pause a
/// (preferably multi-speaker) group in the Sonos app and asserts the
/// matching `ChangeEvent::Playback` arrives carrying the group's
/// `GroupId`, NOT a `SpeakerId`. This verifies the coordinator-only
/// filter + per-group addressing path end-to-end on real hardware.
///
/// **False-positive guard (Copilot review on PR #45):** pre-fetches a
/// per-group transport-state baseline via the v0.3 SOAP path (reading
/// the coordinator's state) and only accepts `Playback` events whose
/// `PlaybackState` DIFFERS from baseline. This filters late-arriving
/// seed NOTIFYs that report a group's existing state — without the
/// baseline check, a slow-to-seed group could deliver its seed AFTER
/// the 2 s drain and falsely trip the test.
#[test]
#[ignore = "live-only — manual: play or pause a group in the Sonos app within 10 s"]
fn operator_play_pause_emits_per_group_event() {
    use oto_core::PlaybackState;
    use std::collections::HashMap;

    let wire = SonosWire::new();
    let snap = wire.discover().expect("discovery ok");
    println!(
        "[live_events] discovered {} speakers in {} groups",
        snap.speakers.len(),
        snap.groups.len()
    );
    for g in &snap.groups {
        println!(
            "[live_events]   group {} coord={} members={}",
            g.id,
            g.coordinator,
            g.members.len()
        );
    }

    // Pre-fetch baseline transport state per group via the v0.3 SOAP
    // path (reading the coordinator's transport). Events whose
    // PlaybackState matches the baseline are seeds; only a real change
    // counts as the operator's action.
    let mut baseline: HashMap<GroupId, PlaybackState> = HashMap::new();
    for g in &snap.groups {
        if let Ok(state) = wire.speaker_state(&g.coordinator) {
            if let Some(t) = state.transport {
                baseline.insert(g.id.clone(), t.state);
            }
        }
    }
    println!(
        "[live_events] captured {} baseline group transports via SOAP",
        baseline.len()
    );

    wire.subscribe_speakers().expect("subscribe ok");
    let rx = wire.take_event_stream().expect("rx available");

    // Drain seeds (any straggler is also caught by the baseline check).
    let drain_until = Instant::now() + Duration::from_secs(2);
    while Instant::now() < drain_until {
        let _ = rx.recv_timeout(Duration::from_millis(100));
    }

    eprintln!();
    eprintln!(">>> PLAY or PAUSE a group in the Sonos app NOW (10 s window) <<<");
    eprintln!("    (prefer a multi-speaker group if available; we verify the");
    eprintln!("     event carries GroupId, not the coordinator's SpeakerId)");
    eprintln!();

    let start = Instant::now();
    let deadline = start + Duration::from_secs(10);
    while Instant::now() < deadline {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(ChangeEvent::Playback { group, state }) => {
                match baseline.get(&group) {
                    Some(&old) if old == state => {
                        // Late seed or no-op. Update baseline so a
                        // subsequent real change for this group can
                        // still be detected.
                        println!(
                            "[live_events] (filtered no-change Playback for {group}: {old:?})"
                        );
                        baseline.insert(group, state);
                    }
                    _ => {
                        // Real state change (or no baseline available
                        // because the coordinator's SOAP read failed
                        // — treat as the operator's action either way).
                        let elapsed = start.elapsed();
                        println!(
                            "[live_events] Playback {} → {:?} (baseline {:?}) after {:?}",
                            group,
                            state,
                            baseline.get(&group),
                            elapsed
                        );

                        // Verify the GroupId matches one of the discovered groups.
                        // (The pump must address per-group, not per-speaker.)
                        assert!(
                            snap.groups.iter().any(|g| g.id == group),
                            "Playback event carried unknown GroupId {group}; \
                             known groups: {:?}",
                            snap.groups.iter().map(|g| &g.id).collect::<Vec<_>>(),
                        );
                        return;
                    }
                }
            }
            Ok(other) => {
                println!("[live_events] (ignoring non-Playback event: {other:?})");
            }
            Err(_) => { /* timeout — keep polling */ }
        }
    }
    panic!("no Playback event within 10 s of the operator prompt");
}

/// Test #4 — fully automatic. Calls `discover()` + `subscribe_speakers()`
/// twice in sequence on the same wire? No — `subscribe_speakers` is
/// one-shot per wire, so we construct two wires back-to-back. The
/// regression we're guarding against: the v0.4 Slice 3 review-finding-C1
/// `EventPump::Drop` self-deadlock would have hung the SECOND wire's
/// constructor (because dropping the first wire also drops its
/// `EventPump`, which under the old design joined a pump thread that
/// was blocked on its own sender clone).
///
/// On real hardware: each wire performs SSDP + ZGT + SUBSCRIBE; both
/// must complete within a generous budget. If the second wire hangs,
/// this test will time out at the nextest test-level timeout (5 min).
#[test]
#[ignore = "requires a real Sonos LAN"]
fn double_discover_does_not_hang() {
    let start = Instant::now();

    // Wire #1
    {
        let wire = SonosWire::new();
        wire.discover().expect("wire 1 discover ok");
        wire.subscribe_speakers().expect("wire 1 subscribe ok");
        let _ = wire.take_event_stream().expect("wire 1 rx available");
        // Brief observation window so the pump is actually running on
        // a real LAN before we drop the wire.
        std::thread::sleep(Duration::from_millis(500));
    }
    let after_first_drop = start.elapsed();
    println!("[live_events] double_discover: first wire dropped at {after_first_drop:?}");

    // Wire #2 — this is where the OLD design would hang in spawn ->
    // subscribe_speakers (waiting for the first wire's pump to join,
    // which never would).
    {
        let wire2 = SonosWire::new();
        wire2.discover().expect("wire 2 discover ok");
        wire2.subscribe_speakers().expect("wire 2 subscribe ok");
        let _ = wire2.take_event_stream().expect("wire 2 rx available");
        std::thread::sleep(Duration::from_millis(500));
    }
    let total = start.elapsed();
    println!("[live_events] double_discover: both wires constructed + dropped in {total:?}");

    // A generous budget: SSDP timeout (3 s) × 2 + setup + cleanup.
    // Under the old broken design the second cycle would never finish;
    // under the fix this should complete in well under 10 s on a LAN.
    assert!(
        total < Duration::from_secs(15),
        "double-discover took {total:?}; expected well under 15 s"
    );
}

/// Test #5 — extra-ignored long-running. Subscribes and idles for ≥ 26
/// minutes, then asserts the channel is still alive (renewals fired at
/// ~25 min per spike finding #8). Run only when explicitly invoked.
///
/// Belt-and-braces: even if `--features live-tests` is set,
/// `--run-ignored ignored-only` runs every `#[ignore]` test in the
/// file. To skip THIS test specifically, pass
/// `--no-tests=live_events::renewal_cycle_observation` or rely on the
/// explicit "30 min" tag in the ignore message as a manual gate.
#[test]
#[ignore = "live-only — 30+ min run; observes the ~25 min renewal cycle"]
fn renewal_cycle_observation() {
    let wire = SonosWire::new();
    wire.discover().expect("discovery ok");
    wire.subscribe_speakers().expect("subscribe ok");
    let rx = wire.take_event_stream().expect("rx available");

    let start = Instant::now();
    let target = Duration::from_secs(28 * 60); // 28 min — past the ~25 min renewal threshold
    let mut events_seen = 0usize;
    let mut last_log = Instant::now();
    while start.elapsed() < target {
        match rx.recv_timeout(Duration::from_secs(60)) {
            Ok(_) => {
                events_seen += 1;
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                // Expected for long idle periods.
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                panic!(
                    "channel disconnected after {:?} — pump thread exited unexpectedly \
                     (events seen before disconnect: {events_seen})",
                    start.elapsed()
                );
            }
        }
        if last_log.elapsed() > Duration::from_secs(120) {
            println!(
                "[live_events] renewal_cycle: elapsed={:?}, events_seen={events_seen}",
                start.elapsed()
            );
            last_log = Instant::now();
        }
    }
    println!(
        "[live_events] renewal_cycle: PASS after {:?}, events_seen={events_seen}",
        start.elapsed()
    );
}
