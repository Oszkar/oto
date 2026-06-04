//! Hardware-gated acceptance for v0.5.1 group form/break
//! (`join_group` / `leave_group`). Feature-gated AND `#[ignore]`d so CI
//! cannot accidentally run it (needs a real Sonos LAN with >= 2 controllable
//! zones).
//!
//! User-run procedure:
//!   1. Ensure the household has at least two independent (un-grouped) zones.
//!   2. cargo nextest run -p oto-wire --features live-tests --test live_grouping --run-ignored ignored-only --nocapture
//!      (or: cargo test -p oto-wire --features live-tests --test live_grouping -- --ignored --nocapture)
//!   3. Observe: the joiner folds into the coordinator's group, then leaving
//!      restores it to a standalone group.
//!
//! Settle semantics (load-bearing): a regroup is reflected by the household
//! ASYNCHRONOUSLY, and the settle latency is VARIABLE — the 2026-06-04 spike
//! found a single fixed delay is racy, and a first hardware run of this test
//! caught a not-yet-settled `leave` at 3 s that passed on the retry. So this
//! test POLLS `refresh_topology()` until the household reaches the expected
//! settled state (or a generous timeout), rather than asserting on one
//! fixed-delay snapshot. Production does not rely on a fixed delay either: it
//! refreshes off the post-settle `GroupMembership` event (debounced).

#![cfg(feature = "live-tests")]

use std::{
    sync::mpsc::RecvTimeoutError,
    thread::sleep,
    time::{Duration, Instant},
};

use oto_core::{ChangeEvent, DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, Volume, Wire};
use oto_wire::SonosWire;

/// How often to re-pull topology while waiting for the household to settle.
const POLL: Duration = Duration::from_millis(500);
/// Upper bound on the settle wait. Far above the observed (~<=3 s) settle, so a
/// slow propagation doesn't flake the test; a genuine failure still fails
/// (the expected state never arrives) within the bound.
const SETTLE_TIMEOUT: Duration = Duration::from_secs(20);

/// Find the group containing `speaker` in a snapshot, if any.
fn group_of<'a>(snap: &'a DiscoverySnapshot, speaker: &SpeakerId) -> Option<&'a GroupIdentity> {
    snap.groups.iter().find(|g| g.members.contains(speaker))
}

/// Re-pull `refresh_topology()` every `POLL` until `pred` returns `Some` or
/// `SETTLE_TIMEOUT` elapses; returns the satisfied value. Tolerates a transient
/// `refresh_topology` error within the window (retries). Panics with `label`
/// context on timeout. This is the settle-robust replacement for a single fixed
/// delay (see the module doc) — Sonos reflects a regroup asynchronously with
/// variable latency, so we wait for the expected state rather than a fixed time.
fn poll_until_settled<T>(
    wire: &SonosWire,
    label: &str,
    mut pred: impl FnMut(&DiscoverySnapshot) -> Option<T>,
) -> T {
    let start = Instant::now();
    loop {
        // Wait BEFORE the first poll so it can't race the mutating SOAP write
        // completing on the device.
        sleep(POLL);
        match wire.refresh_topology() {
            Ok(snap) => {
                if let Some(v) = pred(&snap) {
                    return v;
                }
            }
            // stdout (not stderr) so it survives `nextest --nocapture`.
            Err(e) => println!("  {label}: refresh_topology error (retrying within window): {e}"),
        }
        assert!(
            start.elapsed() < SETTLE_TIMEOUT,
            "{label}: household did not reach the expected settled topology within {SETTLE_TIMEOUT:?}",
        );
    }
}

#[test]
#[ignore = "requires a real Sonos LAN with >= 2 independent zones; v0.5.1 acceptance"]
fn live_join_then_leave_round_trip() {
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discover() against the real LAN");
    println!(
        "discover(): {} group(s), {} speaker(s)",
        snap.groups.len(),
        snap.speakers.len()
    );

    // Need two distinct groups so we can fold one into the other. Pick a joiner
    // from a 1-member group and a coordinator from a DIFFERENT group.
    let coordinator_group = snap.groups.first().expect("expected >= 1 group on the LAN");
    let coordinator = coordinator_group.coordinator.clone();

    let joiner_group = snap
        .groups
        .iter()
        .find(|g| g.members.len() == 1 && g.coordinator != coordinator)
        .or_else(|| snap.groups.iter().find(|g| g.coordinator != coordinator));

    let Some(joiner_group) = joiner_group else {
        println!(
            "SKIP: need >= 2 independent zones to exercise join/leave (found {} group(s)). \
             Un-group a room in the Sonos app, then re-run.",
            snap.groups.len()
        );
        return;
    };
    let joiner = joiner_group.coordinator.clone();

    println!(
        "join: {} → coordinator {}",
        joiner.as_str(),
        coordinator.as_str()
    );

    // ── JOIN ──────────────────────────────────────────────────────────────
    wire.join_group(&joiner, &coordinator)
        .expect("join_group must succeed");

    // Poll the SETTLED topology until the joiner is a member of the
    // coordinator's group (variable settle latency — see module doc).
    let joined_into = poll_until_settled(&wire, "join", |snap| {
        group_of(snap, &joiner)
            .filter(|g| g.coordinator == coordinator && g.members.contains(&coordinator))
            .cloned()
    });
    println!(
        "  settled: joiner {} now in group {} (coord {})",
        joiner.as_str(),
        joined_into.id.as_str(),
        joined_into.coordinator.as_str()
    );

    // ── LEAVE (restore) ─────────────────────────────────────────────────────
    wire.leave_group(&joiner).expect("leave_group must succeed");

    // Poll the SETTLED topology until the leaver coordinates its own
    // standalone group containing only itself.
    let standalone = poll_until_settled(&wire, "leave", |snap| {
        group_of(snap, &joiner)
            .filter(|g| g.coordinator == joiner && g.members == vec![joiner.clone()])
            .cloned()
    });
    println!(
        "  settled: joiner {} back to standalone group {}",
        joiner.as_str(),
        standalone.id.as_str()
    );
}

#[test]
#[ignore = "requires a real Sonos LAN with >= 2 independent zones; v0.5.1 acceptance"]
fn live_group_volume_command_and_event_round_trip() {
    // Forms a group, then issues `set_group_volume` on the coordinator and
    // drains the event stream asserting a `GroupVolume` event carrying the
    // group's `GroupId`. Mirrors the per-speaker volume command+event path.
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discover() against the real LAN");
    println!(
        "discover(): {} group(s), {} speaker(s)",
        snap.groups.len(),
        snap.speakers.len()
    );

    // Pick a coordinator + a joiner from a DIFFERENT group, like the
    // join/leave test, so we exercise a real (multi-member) group.
    let coordinator_group = snap.groups.first().expect("expected >= 1 group on the LAN");
    let coordinator = coordinator_group.coordinator.clone();
    let joiner_group = snap
        .groups
        .iter()
        .find(|g| g.members.len() == 1 && g.coordinator != coordinator)
        .or_else(|| snap.groups.iter().find(|g| g.coordinator != coordinator));
    let Some(joiner_group) = joiner_group else {
        println!(
            "SKIP: need >= 2 independent zones to form a group (found {} group(s)).",
            snap.groups.len()
        );
        return;
    };
    let joiner = joiner_group.coordinator.clone();

    // Form the group FIRST, then build the subscription against the SETTLED,
    // grouped topology — mirroring production, where a regroup triggers a
    // re-discover that rebuilds the pump with a clean TopologyFilter. Subscribing
    // BEFORE joining (an earlier version did) makes the pump observe the regroup,
    // mark its TopologyFilter dirty, and drop group-addressed events (incl.
    // GroupVolume) until rebuilt — so the wait below would time out even though
    // the command succeeded (codex review of PR #73, finding 2).
    wire.join_group(&joiner, &coordinator)
        .expect("join_group must succeed");
    let joined_into = poll_until_settled(&wire, "join", |snap| {
        group_of(snap, &joiner)
            .filter(|g| g.coordinator == coordinator && g.members.contains(&coordinator))
            .cloned()
    });
    let group_id: GroupId = joined_into.id.clone();
    println!(
        "  settled: group {} (coord {})",
        group_id.as_str(),
        coordinator.as_str()
    );

    // Re-pull the settled grouped topology into the wire's caches, then spawn a
    // FRESH pump (clean TopologyFilter) that watches the coordinator's
    // GroupRenderingControl — exactly what a production re-discover does.
    wire.discover()
        .expect("re-discover the settled grouped topology");
    wire.subscribe_topology()
        .expect("subscribe_topology before the pump");
    wire.subscribe_speakers()
        .expect("subscribe_speakers spawns the pump");
    let rx = wire
        .take_event_stream()
        .expect("event stream available after subscribe_speakers");

    // Drain any seed / settle events already queued so the assertion below
    // observes the event caused by OUR command, not a leftover seed.
    drain_until_quiet(&rx, Duration::from_millis(500));

    // ── SET GROUP VOLUME → expect a GroupVolume event for this group ────────
    let target = Volume::new(35).expect("35 in range");
    println!("set_group_volume({}) on group {}", 35, group_id.as_str());
    wire.set_group_volume(&group_id, target)
        .expect("set_group_volume must succeed");

    // A single group-volume change fires one or more group_volume NOTIFYs;
    // wait for the first GroupVolume event addressed to our group.
    let saw_group_volume = wait_for_group_volume(&rx, &group_id, Duration::from_secs(10));
    assert!(
        saw_group_volume,
        "expected a GroupVolume event for group {} after set_group_volume",
        group_id.as_str()
    );

    // ── RESTORE: leave the group so the LAN is left as we found it ──────────
    wire.leave_group(&joiner).expect("leave_group must succeed");
    let _ = poll_until_settled(&wire, "leave", |snap| {
        group_of(snap, &joiner)
            .filter(|g| g.coordinator == joiner && g.members == vec![joiner.clone()])
            .cloned()
    });
}

/// Drain events for up to `budget`, ignoring them — used to flush seeds/settle
/// noise before asserting on a command-caused event.
fn drain_until_quiet(rx: &std::sync::mpsc::Receiver<ChangeEvent>, budget: Duration) {
    let deadline = Instant::now() + budget;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return;
        }
        match rx.recv_timeout(remaining.min(Duration::from_millis(100))) {
            Ok(_) => continue,
            Err(RecvTimeoutError::Timeout) => return,
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

/// Block until a `GroupVolume` event addressed to `group` arrives, or `budget`
/// elapses. Returns whether one was seen.
fn wait_for_group_volume(
    rx: &std::sync::mpsc::Receiver<ChangeEvent>,
    group: &GroupId,
    budget: Duration,
) -> bool {
    let deadline = Instant::now() + budget;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return false;
        }
        match rx.recv_timeout(remaining.min(Duration::from_millis(250))) {
            Ok(ChangeEvent::GroupVolume { group: g, volume }) if g == *group => {
                println!(
                    "  got GroupVolume {{ group: {}, volume: {} }}",
                    g.as_str(),
                    volume.get()
                );
                return true;
            }
            Ok(_) => continue,
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => return false,
        }
    }
}
