//! LAN-only. Ignored by default — needs real Sonos hardware and cannot
//! run in CI / sandbox (AGENTS.md §5). Run:
//!   cargo test -p oto-wire --test live_discovery -- --ignored --nocapture

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
