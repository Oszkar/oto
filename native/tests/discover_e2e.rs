//! v0.1 acceptance: discovery proven end-to-end without a LAN. Drives
//! oto-app's `discover_with` seam with the deterministic MockWire and
//! asserts the snapshot oto-app produces. Per plan deviation D2 this
//! stops at the oto-app/oto_core layer; it does NOT cross the FRB DTO
//! mapping in api.rs (the thin Dart-facing provider wiring is covered
//! separately by the Flutter test in Task 7).

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
