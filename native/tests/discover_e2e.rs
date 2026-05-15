//! v0.1 acceptance: discovery proven end-to-end without a LAN, driving
//! oto-app's seam with the deterministic MockWire and asserting the
//! oto_core -> identity mapping the FRB layer renders.

use oto_app::discover_with;
use oto_mock::MockWire;

#[test]
fn discovery_end_to_end_against_mock() {
    let snap = discover_with(|| Box::new(MockWire::default())).expect("mock discovery succeeds");
    assert_eq!(snap.speakers.len(), 3);
    assert_eq!(snap.groups.len(), 2);
    for g in &snap.groups {
        assert_eq!(g.members[0], g.coordinator);
    }
}
