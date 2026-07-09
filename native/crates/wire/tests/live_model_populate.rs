//! LAN-only. Feature-gated AND `#[ignore]`d so CI can't run it (needs real
//! Sonos hardware). Run:
//!   cargo nextest run -p oto-wire --features live-tests \
//!     --test live_model_populate --run-ignored ignored-only --nocapture
//!
//! Verifies v0.5: `discover()` repopulates `SpeakerIdentity.model` from
//! each speaker's `device_description.xml` (ZGT carries no model - D1).
//! `refresh_topology()` shares the same path, so it's checked too.

#![cfg(feature = "live-tests")]

use oto_core::Wire;
use oto_wire::SonosWire;

#[test]
#[ignore = "live-tests: requires a real Sonos LAN"]
fn model_populated_after_discover() {
    let wire = SonosWire::new();

    let snap = wire.discover().expect("discover");
    for s in &snap.speakers {
        println!("[discover]  {} ({}) → {:?}", s.id, s.room_name, s.model);
    }
    let with_model = snap.speakers.iter().filter(|s| s.model.is_some()).count();
    assert!(
        with_model > 0,
        "expected ≥1 speaker with model populated after discover; got 0 of {}",
        snap.speakers.len()
    );

    // refresh_topology() must populate model too (consistent path, no SSDP).
    let refreshed = wire.refresh_topology().expect("refresh_topology");
    for s in &refreshed.speakers {
        println!("[refresh]   {} ({}) → {:?}", s.id, s.room_name, s.model);
    }
    assert!(
        refreshed.speakers.iter().any(|s| s.model.is_some()),
        "refresh_topology must also populate model"
    );
}
