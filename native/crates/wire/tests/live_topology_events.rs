//! LAN-only. Feature-gated AND `#[ignore]`d so CI cannot accidentally
//! run it (needs real Sonos hardware). Run:
//!   cargo nextest run -p oto-wire --features live-tests \
//!     --test live_topology_events --run-ignored ignored-only --nocapture
//!
//! Verifies the v0.5 topology-event path end-to-end against a real LAN:
//!   1. `subscribe_topology` + `subscribe_speakers` activates the SDK
//!      `GroupMembership` watch without error (automatic smoke test).
//!   2. Operator regroups in the Sonos app → `ChangeEvent::TopologyChanged`
//!      arrives during the operator window (interactive).
//!   3. `refresh_topology` re-pulls authoritative topology via SOAP and
//!      reflects the operator's new grouping (interactive, chained with #2).
//!
//! Mechanism (docs/sonos-notes.md § "Topology change events"):
//! ZoneGroupTopology has no watchable *property*; topology changes surface
//! via the speaker-scoped `GroupMembership` property. A single regroup fires
//! one `group_membership` NOTIFY per affected speaker, each mapped to a
//! payload-less `TopologyChanged`.

#![cfg(feature = "live-tests")]

use std::io::{self, Write};
use std::time::{Duration, Instant};

use oto_core::{ChangeEvent, Wire};
use oto_wire::SonosWire;

/// Print + flush an interactive prompt to **stdout** so it shows up under
/// `cargo nextest run --nocapture` (stderr lines are dropped by the runner;
/// see live_events.rs for the empirical note).
fn flush_prompt(lines: &[&str]) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out);
    for line in lines {
        let _ = writeln!(out, "{line}");
    }
    let _ = writeln!(out);
    let _ = out.flush();
}

/// Test #1 — fully automatic. Subscribing to topology then speakers must
/// activate the SDK `GroupMembership` watch and yield a live event stream
/// without error. Does NOT require a regroup — just proves the wiring is
/// sound (the watch registers, the pump spawns, the stream is takeable).
///
/// Hardware probing established that `GroupMembership` also seeds on subscribe
/// (one event per speaker before any user action). We don't assert on the
/// seed here — speaker-scoped seed timing is non-uniform and can exceed a
/// few seconds (sonos-notes § "Per-speaker seed NOTIFY behavior is
/// non-uniform"); the regroup-driven path is test #2's job.
#[test]
#[ignore = "requires a real Sonos LAN"]
fn subscribe_topology_then_speakers_activates_stream() {
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discovery ok");
    println!(
        "[live_topology] discovered {} speakers in {} groups",
        snap.speakers.len(),
        snap.groups.len()
    );

    // Ordering matters: subscribe_topology MUST precede subscribe_speakers
    // so the flag is set before the pump is built (mirrors discover_with).
    wire.subscribe_topology().expect("subscribe_topology ok");
    wire.subscribe_speakers().expect("subscribe_speakers ok");
    let _rx = wire
        .take_event_stream()
        .expect("event stream available after subscribe");
    println!("[live_topology] topology watch active; stream takeable");
}

/// Test #2 — interactive. Prompts the operator to regroup in the Sonos app
/// (form a group, then break it) and asserts at least one
/// `ChangeEvent::TopologyChanged` arrives during the operator window. Then
/// calls `refresh_topology` and prints the re-pulled grouping so the
/// operator can eyeball that it reflects reality.
///
/// **What this verifies:** the full topology event chain on real hardware —
/// `GroupMembership` SUBSCRIBE → NOTIFY on regroup → pump maps to
/// `TopologyChanged` → reaches the consumer; and `refresh_topology` SOAP
/// returns a fresh snapshot (no SSDP).
///
/// **Latency:** not asserted (dominated by human reaction time). The ~5 s
/// acceptance figure in the plan is the NOTIFY→event delivery, which the
/// hardware probing measured sub-second; here the wall-clock is mostly
/// the operator reaching for the app.
#[test]
#[ignore = "live-only — manual: regroup speakers in the Sonos app within 30 s"]
fn operator_regroup_emits_topology_changed() {
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discovery ok");
    println!(
        "[live_topology] discovered {} speakers in {} groups (before regroup):",
        snap.speakers.len(),
        snap.groups.len()
    );
    for g in &snap.groups {
        println!(
            "[live_topology]   group {} coord={} members={}",
            g.id,
            g.coordinator,
            g.members.len()
        );
    }
    assert!(
        snap.speakers.len() >= 2,
        "regroup test needs ≥ 2 speakers on the LAN; found {}",
        snap.speakers.len()
    );

    wire.subscribe_topology().expect("subscribe_topology ok");
    wire.subscribe_speakers().expect("subscribe_speakers ok");
    let rx = wire.take_event_stream().expect("rx available");

    // Drain the seed NOTIFYs (~3 s) so we only count regroup-driven events.
    // GroupMembership seeds per speaker on subscribe (see sonos-notes); the
    // probe observed seed latency that can exceed 3 s, so a straggler seed
    // could slip past — acceptable here: a seed TopologyChanged is
    // indistinguishable from a regroup one at this layer, and the operator
    // prompt window is the dominant signal.
    let drain_until = Instant::now() + Duration::from_secs(3);
    while Instant::now() < drain_until {
        let _ = rx.recv_timeout(Duration::from_millis(100));
    }

    flush_prompt(&[
        "============================================================",
        ">>> ACTION REQUIRED — REGROUP SPEAKERS NOW <<<",
        "    In the SONOS app: add a room to another room's group,",
        "    then (optionally) break the group again.",
        "    Prompt repeats every 5 s through the 30 s window.",
        "============================================================",
    ]);

    let start = Instant::now();
    let deadline = start + Duration::from_secs(30);
    let mut next_reminder = start + Duration::from_secs(5);
    let mut topology_events = 0usize;
    while Instant::now() < deadline {
        if Instant::now() >= next_reminder {
            let remaining = deadline.saturating_duration_since(Instant::now()).as_secs();
            flush_prompt(&[&format!(
                ">>> ACT NOW — {remaining} s remaining — REGROUP in the Sonos app <<<"
            )]);
            next_reminder = Instant::now() + Duration::from_secs(5);
        }
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(ChangeEvent::TopologyChanged) => {
                topology_events += 1;
                let elapsed = start.elapsed();
                println!("[live_topology] TopologyChanged #{topology_events} after {elapsed:?}");
                // One is enough to prove the path; keep draining briefly to
                // show the per-speaker fan-out, but don't require a count.
                break;
            }
            Ok(other) => {
                println!("[live_topology] (ignoring non-topology event: {other:?})");
            }
            Err(_) => { /* timeout — keep polling */ }
        }
    }

    assert!(
        topology_events >= 1,
        "no TopologyChanged within 30 s of the regroup prompt"
    );

    // Now prove refresh_topology re-pulls authoritative state via SOAP.
    let refreshed = wire.refresh_topology().expect("refresh_topology ok");
    println!(
        "[live_topology] refresh_topology → {} speakers in {} groups (after regroup):",
        refreshed.speakers.len(),
        refreshed.groups.len()
    );
    for g in &refreshed.groups {
        println!(
            "[live_topology]   group {} coord={} members={}",
            g.id,
            g.coordinator,
            g.members.len()
        );
    }
    assert!(
        !refreshed.speakers.is_empty(),
        "refresh_topology returned an empty snapshot"
    );
}
