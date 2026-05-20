//! Hardware-gated acceptance for v0.3 real ZoneGroupTopology grouping
//! (plan Task 8 / spike findings directive-7). Feature-gated AND
//! `#[ignore]`d so CI cannot accidentally run it (needs a real Sonos LAN).
//!
//! User-run procedure:
//!   1. In the Sonos app, group two rooms (e.g. Kitchen + Living Room)
//!      and queue something on the group.
//!   2. cargo nextest run -p oto-wire --features live-tests --test live_topology --run-ignored ignored-only
//!   3. Observe: the resolved coordinator's rooms all respond.

#![cfg(feature = "live-tests")]

use oto_core::Wire;
use oto_wire::SonosWire;

#[test]
#[ignore = "requires a real Sonos LAN; user-run v0.3 acceptance (directive-7)"]
fn live_discover_returns_real_groups() {
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discover() against the real LAN");

    assert!(!snap.groups.is_empty(), "expected >= 1 real group");
    assert!(!snap.speakers.is_empty(), "expected >= 1 real speaker");
    println!(
        "discover(): {} group(s), {} speaker(s)",
        snap.groups.len(),
        snap.speakers.len()
    );

    for g in &snap.groups {
        assert!(
            !g.members.is_empty(),
            "group {} has no members",
            g.id.as_str()
        );
        assert_eq!(
            g.members[0],
            g.coordinator,
            "oto-core D3: members[0] must be the coordinator (group {})",
            g.id.as_str()
        );
        assert!(
            snap.speakers.iter().any(|s| s.id == g.coordinator),
            "coordinator {} of group {} is not in speakers",
            g.coordinator.as_str(),
            g.id.as_str()
        );
        println!(
            "  group {} coordinator={} members={}",
            g.id.as_str(),
            g.coordinator.as_str(),
            g.members.len()
        );
    }

    let multi = snap.groups.iter().any(|g| g.members.len() >= 2);
    println!(
        "multi-room group present: {multi} \
         (form a 2-room group in the Sonos app to exercise directive-7)"
    );
}
