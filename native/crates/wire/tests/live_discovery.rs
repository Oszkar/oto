//! LAN-only. Feature-gated AND `#[ignore]`d so CI cannot accidentally
//! run it (needs real Sonos hardware). Run:
//!   cargo nextest run -p oto-wire --features live-tests --test live_discovery --run-ignored ignored-only --nocapture

#![cfg(feature = "live-tests")]

use oto_core::Wire;
use oto_wire::SonosWire;

#[test]
#[ignore = "requires a real Sonos LAN"]
fn live_discovery_finds_speakers() {
    let snap = SonosWire::new().discover().expect("discovery");
    println!(
        "speakers={} groups={}",
        snap.speakers.len(),
        snap.groups.len()
    );
    for s in &snap.speakers {
        println!("  {} [{}] {:?} {}", s.room_name, s.id, s.model, s.ip);
    }
    assert!(!snap.speakers.is_empty(), "expected ≥1 speaker on the LAN");
}
