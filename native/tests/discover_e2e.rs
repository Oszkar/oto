//! v0.1 acceptance: discovery proven end-to-end without a LAN.
//!
//! Drives oto-app's `discover_with` seam with the deterministic `MockWire`,
//! then crosses the **FRB DTO boundary** via `oto_native::map` — the exact
//! representational map `api::discover()` applies (snapshot → `Topology`,
//! `WireError` → `DiscoveryError`). This realises plan deviation D2 in full:
//! the e2e asserts the snapshot *and* the `oto_native` DTO mapping with zero
//! LAN. The thin Dart provider wiring is covered separately by the Flutter
//! test (Task 7); a real LAN run is the user-run step (Task 8).

use oto_app::discover_with;
use oto_core::WireError;
use oto_mock::MockWire;
use oto_native::api::DiscoveryError;
use oto_native::map::{to_discovery_error, to_topology};

#[test]
fn discovery_end_to_end_against_mock() {
    let snap = discover_with(|| Box::new(MockWire::default())).expect("mock discovery succeeds");

    // Domain layer (oto-app / oto-core).
    assert_eq!(snap.speakers.len(), 3);
    assert_eq!(snap.groups.len(), 2);
    for g in &snap.groups {
        assert_eq!(g.members[0], g.coordinator);
    }

    // Bridge-DTO layer: the exact map api::discover() returns to Dart.
    let topo = to_topology(snap);
    assert_eq!(topo.speakers.len(), 3);
    assert_eq!(topo.groups.len(), 2);

    let kitchen = topo
        .speakers
        .iter()
        .find(|s| s.room_name == "Kitchen")
        .expect("Kitchen in DTO");
    assert_eq!(kitchen.id, "RINCON_KITCHEN");
    assert_eq!(kitchen.ip, "10.83.0.10", "IpAddr must render to a string");
    assert_eq!(kitchen.model.as_deref(), Some("Sonos One"));

    let office = topo
        .speakers
        .iter()
        .find(|s| s.room_name == "Office")
        .expect("Office in DTO");
    assert_eq!(office.model, None, "absent model stays None across the map");

    let kitchen_group = topo
        .groups
        .iter()
        .find(|g| g.id == "RINCON_KITCHEN:1")
        .expect("Kitchen group in DTO");
    assert_eq!(kitchen_group.coordinator, "RINCON_KITCHEN");
    assert_eq!(
        kitchen_group.members,
        vec!["RINCON_KITCHEN", "RINCON_DINING"]
    );
}

#[test]
fn failure_crosses_the_dto_error_map() {
    // The Err arm of api::discover(): WireError → FRB DiscoveryError, LAN-free.
    let err = discover_with(|| Box::new(MockWire::failing(WireError::NoDevicesFound)))
        .expect_err("failing mock returns Err");
    assert!(matches!(
        to_discovery_error(err),
        DiscoveryError::NoDevicesFound
    ));
}
