//! Hardware-gated acceptance for v0.5.1 group form/break
//! (`join_group` / `leave_group`). Feature-gated AND `#[ignore]`d so CI
//! cannot accidentally run it (needs a real Sonos LAN with >= 2 controllable
//! zones).
//!
//! User-run procedure:
//!   1. Ensure the household has at least two independent (un-grouped) zones.
//!   2. cargo nextest run -p oto-wire --features live-tests --test live_grouping --run-ignored ignored-only --nocapture
//!   3. Observe: the joiner folds into the coordinator's group, then leaving
//!      restores it to a standalone group.
//!
//! Settle semantics (load-bearing): a regroup is reflected by the household
//! ASYNCHRONOUSLY via `GroupMembership` NOTIFYs that fire only AFTER the
//! topology settles. An immediate re-poll can observe a TRANSITIONAL state
//! (the 2026-06-04 spike finding). So this test waits a short settle delay
//! and re-pulls the SETTLED topology via `refresh_topology()` before
//! asserting — it does NOT assert on an immediate re-poll.

#![cfg(feature = "live-tests")]

use std::{thread::sleep, time::Duration};

use oto_core::{DiscoverySnapshot, SpeakerId, Wire};
use oto_wire::SonosWire;

/// Settle window: the household reflects a regroup asynchronously. Generous
/// (group form/break + ZGT propagation) so the re-pull sees the settled
/// state, not a transitional one.
const SETTLE: Duration = Duration::from_secs(3);

/// Find the group containing `speaker` in a snapshot, if any.
fn group_of<'a>(
    snap: &'a DiscoverySnapshot,
    speaker: &SpeakerId,
) -> Option<&'a oto_core::GroupIdentity> {
    snap.groups.iter().find(|g| g.members.contains(speaker))
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

    // Need two distinct standalone (or at least two distinct) groups so we
    // can fold one into the other. Pick a joiner from a 1-member group and a
    // coordinator from a DIFFERENT group.
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

    // Wait for the household to settle, THEN re-pull the SETTLED topology.
    sleep(SETTLE);
    let after_join = wire
        .refresh_topology()
        .expect("refresh_topology after join");

    let joined_into = group_of(&after_join, &joiner).unwrap_or_else(|| {
        panic!(
            "joiner {} not found in any group after join",
            joiner.as_str()
        )
    });
    assert_eq!(
        joined_into.coordinator, coordinator,
        "after settle, the joiner must be a member of the coordinator's group"
    );
    assert!(
        joined_into.members.contains(&coordinator),
        "coordinator must still be in the formed group"
    );
    println!(
        "  settled: joiner {} now in group {} (coord {})",
        joiner.as_str(),
        joined_into.id.as_str(),
        joined_into.coordinator.as_str()
    );

    // ── LEAVE (restore) ─────────────────────────────────────────────────────
    wire.leave_group(&joiner).expect("leave_group must succeed");

    sleep(SETTLE);
    let after_leave = wire
        .refresh_topology()
        .expect("refresh_topology after leave");

    let standalone = group_of(&after_leave, &joiner)
        .unwrap_or_else(|| panic!("joiner {} not found after leave", joiner.as_str()));
    assert_eq!(
        standalone.coordinator, joiner,
        "after settle, the leaver must coordinate its own standalone group"
    );
    assert_eq!(
        standalone.members,
        vec![joiner.clone()],
        "the leaver's standalone group must contain only itself"
    );
    println!(
        "  settled: joiner {} back to standalone group {}",
        joiner.as_str(),
        standalone.id.as_str()
    );
}
