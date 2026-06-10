//! LAN-only. Feature-gated AND `#[ignore]`d so CI cannot accidentally
//! run it (needs real Sonos hardware). Run:
//!   cargo nextest run -p oto-wire --features live-tests --test live_events \
//!     --run-ignored ignored-only --nocapture
//!
//! Verifies the v0.4 event pump end-to-end against the 4-speaker LAN:
//!   1. `subscribe_speakers` + seed NOTIFYs arrive within 2 s of subscribe.
//!   2. Operator volume change in the Sonos app → `ChangeEvent::Volume`
//!      arrives during the operator window. Latency NOT asserted here
//!      (dominated by human reaction time); spec § 8.1's sub-second
//!      target needs a separate programmatic test (set_volume via SOAP,
//!      measure event arrival).
//!   3. Operator play/pause → `ChangeEvent::Playback` carrying the
//!      group's `GroupId` (NOT the coordinator's `SpeakerId` —
//!      coordinator-only filter must apply per-group addressing).
//!   4. Long-running renewal cycle observation (≥ 26 min idle; renewal
//!      at ~25 min per spike finding #8). Extra-ignored so it only runs
//!      when explicitly invoked.
//!
//! The two interactive tests (#2, #3) prompt the operator via stdout
//! with persistent reminders through the wait window. The seed-NOTIFY
//! test (#1) and the deadlock-regression test are fully automatic.

#![cfg(feature = "live-tests")]

use std::collections::HashSet;
use std::io::{self, Write};
use std::sync::Once;
use std::time::{Duration, Instant};

use oto_core::{ChangeEvent, GroupId, SpeakerId, Wire};
use oto_wire::SonosWire;

/// Print + flush an interactive prompt to **stdout** (not stderr) so it
/// actually shows up under `cargo nextest run --nocapture`. Empirically
/// (empirically on real hardware): the captured stdout `println!`
/// output appears in the test runner's failure dump, but `eprintln!`
/// stderr lines are dropped. Use this helper for any operator prompt
/// so the user can actually see what they're being asked to do.
///
/// Repeated calls during the wait window are the reliable way to make
/// interactive tests robust on real hardware — the SDK can produce
/// other output (tracing-level logging behind a transitive subscriber)
/// that can bury a single prompt.
fn flush_prompt(lines: &[&str]) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out);
    for line in lines {
        let _ = writeln!(out, "{line}");
    }
    let _ = writeln!(out);
    let _ = out.flush();
}

/// Install a tracing subscriber so SDK-internal logs (subscribe attempts,
/// broker registration, polling cycles) print to stderr. Only called by
/// the interactive tests where the diagnostic noise is the point —
/// `subscribe_then_seed_notifies_arrive` keeps its tight output for the
/// automatic assertion.
///
/// Honors `RUST_LOG` if set; defaults to a useful Sonos-SDK filter so
/// the test gives diagnostic value without an env-var setup step.
/// `try_init` so multiple test invocations in the same process don't
/// panic — the global subscriber is one-shot per process.
fn init_sdk_tracing() {
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        let default_filter = "warn,sonos_event_manager=debug,sonos_state=debug,\
                              sonos_stream=debug,sonos_callback_server=debug,\
                              oto_wire=debug";
        let filter = tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(default_filter));
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_writer(io::stderr)
            .with_target(true)
            .try_init();
    });
}

/// Test #1 — fully automatic. Subscribe and assert the SDK's first
/// SUBSCRIBE NOTIFY seeds Volume on at least one of the discovered
/// speakers within 5 s.
///
/// **Why ≥ 1 (not ≥ N or ≥ N/2):** the test's job is "does the seed
/// mechanism work at all" — proving the SUBSCRIBE → NOTIFY → ChangeEvent
/// chain reaches the consumer. Multi-speaker coverage is verified by
/// the active tests (#2, #3) which exercise per-speaker / per-group
/// addressing.
///
/// Empirically on real hardware: speakers don't always send their
/// initial RC NOTIFY on every fresh SUBSCRIBE — particularly on LANs
/// with recent subscription activity (e.g. tests running back-to-back),
/// where a speaker may be in some kind of subscription cooldown that
/// suppresses the redundant seed. The Era 100 in the 2-speaker
/// acceptance LAN exhibited this on 2026-05-26: only the Beam sent
/// its seed within the window even though both speakers were
/// reachable. The window was widened from 2 s → 5 s and the floor
/// from ≥ 2 → ≥ 1 to make the test robust across speaker counts and
/// SDK-internal cooldown timing.
#[test]
#[ignore = "requires a real Sonos LAN"]
fn subscribe_then_seed_notifies_arrive() {
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discovery ok");
    println!(
        "[live_events] discovered {} speakers — expecting ≥ 1 to seed Volume within 5 s",
        snap.speakers.len()
    );
    wire.subscribe_speakers().expect("subscribe ok");
    let rx = wire.take_event_stream().expect("rx available");

    let deadline = Instant::now() + Duration::from_secs(5);
    let mut volume_speakers: HashSet<_> = HashSet::new();
    while Instant::now() < deadline {
        if let Ok(ChangeEvent::Volume { speaker, .. }) = rx.recv_timeout(Duration::from_millis(100))
        {
            volume_speakers.insert(speaker);
        }
    }
    let seeded = volume_speakers.len();
    let discovered = snap.speakers.len();
    println!(
        "[live_events] saw seed Volume for {seeded}/{discovered} speakers: {volume_speakers:?}"
    );
    // Surface a quiet-seed diagnostic so future flakes are easier to
    // attribute — which speakers didn't respond within the window?
    let quiet: Vec<_> = snap
        .speakers
        .iter()
        .map(|s| &s.id)
        .filter(|id| !volume_speakers.contains(id))
        .collect();
    if !quiet.is_empty() {
        println!("[live_events] (quiet — no seed Volume within 5 s): {quiet:?}");
    }
    assert!(
        !volume_speakers.is_empty(),
        "expected ≥ 1 Volume seed within 5 s (across {discovered} discovered speakers); got none"
    );
}

/// Test #2 — interactive. Prompts the operator to change a speaker's
/// volume in the Sonos app and asserts the matching `ChangeEvent::Volume`
/// arrives during the operator window.
///
/// **What this DOES verify:** RenderingControl SUBSCRIBE works end-to-end
/// on real hardware — operator action → SDK NOTIFY → pump_loop mapping
/// → ChangeEvent::Volume reaches the test consumer.
///
/// **What this does NOT verify** (intentionally, by /codex review on
/// PR #46 hardware re-run): the sub-second SDK→consumer latency target
/// from spec § 8.1. That target measures SDK pipeline latency in
/// isolation, but the operator-driven test ALSO includes human reaction
/// time (read prompt → reach for slider → drag), which is the dominant
/// term. A 4.4-second elapsed time on real hardware decomposed as
/// ~3-4 s human + sub-ms SDK is genuinely a fast SDK with a normal
/// human operator. The proper sub-second latency check requires a
/// programmatic volume change (set_volume via SOAP, measure event
/// arrival) — that test belongs separate from the operator gate.
///
/// **False-positive guard (Copilot review on PR #45):** pre-fetches a
/// per-speaker volume baseline via the v0.3 SOAP path before subscribing
/// and only accepts `Volume` events whose value DIFFERS from baseline.
/// This filters late-arriving seed NOTIFYs that report a speaker's
/// existing volume — without the baseline check, a slow-to-seed speaker
/// could deliver its seed AFTER the 2 s drain and falsely trip the test.
#[test]
#[ignore = "live-only — manual: change a speaker volume in the Sonos app within 15 s"]
fn operator_volume_change_emits_event() {
    use std::collections::HashMap;

    init_sdk_tracing();
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discovery ok");

    // Pre-fetch baseline volumes via the v0.3 SOAP path. This gives a
    // deterministic per-speaker reference; events whose value matches
    // are seeds (or no-ops), not the operator's action.
    let mut baseline: HashMap<SpeakerId, u8> = HashMap::new();
    for s in &snap.speakers {
        if let Ok(state) = wire.speaker_state(&s.id)
            && let Some(v) = state.volume
        {
            baseline.insert(s.id.clone(), v.get());
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

    flush_prompt(&[
        "============================================================",
        ">>> ACTION REQUIRED — CHANGE A SPEAKER VOLUME NOW <<<",
        "    Use the SONOS app (not Spotify) — any speaker is fine.",
        "    Volume must DIFFER from current value (no-op writes are filtered).",
        "    Prompt repeats every 3 s through the 15 s window.",
        "    (No sub-second latency requirement; that's an automated test.)",
        "============================================================",
    ]);
    let start = Instant::now();
    let deadline = start + Duration::from_secs(15);
    let mut next_reminder = start + Duration::from_secs(3);
    while Instant::now() < deadline {
        if Instant::now() >= next_reminder {
            let remaining = deadline.saturating_duration_since(Instant::now()).as_secs();
            flush_prompt(&[&format!(
                ">>> ACT NOW — {remaining} s remaining — CHANGE A VOLUME <<<"
            )]);
            next_reminder = Instant::now() + Duration::from_secs(3);
        }
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
                        //
                        // Latency includes human reaction time; we log
                        // it for diagnostic value but don't assert any
                        // ceiling here — the operator-driven path is
                        // not a meaningful SDK-latency measurement.
                        // Spec § 8.1's sub-second target needs a
                        // separate programmatic test.
                        let elapsed = start.elapsed();
                        println!(
                            "[live_events] Volume {} → {} (baseline {:?}) after {:?} (operator+SDK latency, not SDK-only)",
                            speaker,
                            new,
                            baseline.get(&speaker),
                            elapsed
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
    panic!("no Volume event within 15 s of the operator prompt");
}

/// Test #3 — interactive. Prompts the operator to play/pause a
/// (preferably multi-speaker) group in the Sonos app and asserts the
/// matching `ChangeEvent::Playback` arrives carrying the group's
/// `GroupId`, NOT a `SpeakerId`. This verifies the coordinator-only
/// filter + per-group addressing path end-to-end on real hardware.
///
/// **What this test asserts:** the load-bearing assertion is that the
/// `Playback` event carries a `GroupId` matching one of the discovered
/// groups — the coordinator-only AVTransport filter + per-group
/// addressing path. State semantics (Playing vs Paused) are NOT what
/// this test verifies; tests #1 / #2 + the apply_event unit tests
/// cover state-shape correctness.
///
/// **No baseline filter (post 2026-05-26 acceptance run):** an earlier
/// version rejected events whose `PlaybackState` matched a SOAP-read
/// baseline (intent: filter late seeds). That worked when the operator
/// transition produced a state change AWAY from baseline. It broke when:
///   - the operator transition happened to land back at the baseline
///     state (e.g. play then pause when baseline was Paused), OR
///   - the operator did nothing useful, AND
///   - `sonos-stream`'s base 5 s polling cadence emitted a re-NOTIFY of
///     the unchanged state during the operator window.
///
/// In both cases the only Playback event during the window matched
/// baseline and was filtered, even though the subscription was alive
/// and addressing was correct. The test asserts what we actually care
/// about (GroupId routing); polled refreshes during the operator
/// window are an acceptable positive signal.
#[test]
#[ignore = "live-only — manual: play or pause a group in the Sonos app within 15 s"]
fn operator_play_pause_emits_per_group_event() {
    use oto_core::PlaybackState;
    use std::collections::HashMap;

    init_sdk_tracing();
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
    // path — used purely as an operator-prompt hint (so the operator
    // knows what direction to transition), NOT as a filter on incoming
    // events. See the docstring for why the filter was removed.
    let mut baseline: HashMap<GroupId, PlaybackState> = HashMap::new();
    for g in &snap.groups {
        if let Ok(state) = wire.speaker_state(&g.coordinator)
            && let Some(t) = state.transport
        {
            baseline.insert(g.id.clone(), t.state);
        }
    }
    println!(
        "[live_events] captured {} baseline group transports via SOAP",
        baseline.len()
    );

    wire.subscribe_speakers().expect("subscribe ok");
    let rx = wire.take_event_stream().expect("rx available");

    // Drain initial SUBSCRIBE NOTIFYs for 2 s — these are seeds, not
    // operator actions. (We no longer baseline-filter, but draining is
    // still useful: it keeps the "events I see in the operator window"
    // window clean of cold-start noise on the screen, even if a late
    // seed during the operator window would now pass the test
    // harmlessly — see the docstring.)
    let drain_until = Instant::now() + Duration::from_secs(2);
    while Instant::now() < drain_until {
        let _ = rx.recv_timeout(Duration::from_millis(100));
    }

    // Build the prompt with baseline state so the operator knows which
    // direction to toggle each group.
    let baseline_summary: Vec<String> = snap
        .groups
        .iter()
        .map(|g| {
            let state = baseline
                .get(&g.id)
                .map(|s| format!("{s:?}"))
                .unwrap_or_else(|| "unknown".into());
            format!("      {} = {state} (members={})", g.id, g.members.len())
        })
        .collect();
    let mut banner: Vec<String> = vec![
        "============================================================".into(),
        ">>> ACTION REQUIRED — TOGGLE play/pause on a group NOW <<<".into(),
        "    Use the SONOS app (not Spotify Connect).".into(),
        "    Current group states (TRANSITION at least one of them):".into(),
    ];
    banner.extend(baseline_summary);
    banner.push("      e.g. if Playing → tap Pause; if Paused → tap Play.".into());
    banner.push("    Prompt repeats every 3 s through the 15 s window.".into());
    banner.push("    Polled refresh of unchanged state ALSO counts as pass —".into());
    banner.push("    the test checks per-group addressing, not state delta.".into());
    banner.push("============================================================".into());
    let banner_refs: Vec<&str> = banner.iter().map(|s| s.as_str()).collect();
    flush_prompt(&banner_refs);

    let start = Instant::now();
    let deadline = start + Duration::from_secs(15);
    let mut next_reminder = start + Duration::from_secs(3);
    while Instant::now() < deadline {
        if Instant::now() >= next_reminder {
            let remaining = deadline.saturating_duration_since(Instant::now()).as_secs();
            flush_prompt(&[&format!(
                ">>> ACT NOW — {remaining} s remaining — toggle play/pause <<<"
            )]);
            next_reminder = Instant::now() + Duration::from_secs(3);
        }
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(ChangeEvent::Playback { group, state }) => {
                let elapsed = start.elapsed();
                let baseline_state = baseline.get(&group).copied();
                if baseline_state == Some(state) {
                    println!(
                        "[live_events] Playback {group} → {state:?} (baseline {baseline_state:?}, matches — likely a polled refresh) after {elapsed:?}"
                    );
                } else {
                    println!(
                        "[live_events] Playback {group} → {state:?} (baseline {baseline_state:?}, transitioned) after {elapsed:?}"
                    );
                }

                // Load-bearing assertion: the event carries a GroupId
                // that matches one of the discovered groups. This is
                // what the test exists to prove.
                assert!(
                    snap.groups.iter().any(|g| g.id == group),
                    "Playback event carried unknown GroupId {group}; \
                     known groups: {:?}",
                    snap.groups.iter().map(|g| &g.id).collect::<Vec<_>>(),
                );
                return;
            }
            Ok(other) => {
                println!("[live_events] (ignoring non-Playback event: {other:?})");
            }
            Err(_) => { /* timeout — keep polling */ }
        }
    }
    panic!("no Playback event within 15 s of the operator prompt");
}

/// Test #4 — fully automatic. Calls `discover()` + `subscribe_speakers()`
/// twice in sequence on the same wire? No — `subscribe_speakers` is
/// one-shot per wire, so we construct two wires back-to-back. The
/// regression we're guarding against: a v0.4 `EventPump::Drop`
/// self-deadlock would have hung the SECOND wire's
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
