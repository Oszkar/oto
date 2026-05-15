//! Throwaway de-risking spike — NOT part of the product.
//!
//! Answers the open questions in `docs/ARCHITECTURE.md` before we commit to
//! a `Wire` trait shape. Run on a machine with Sonos speakers on the LAN:
//!
//! ```text
//! cargo run -p oto-wire --example spike
//! ```
//!
//! Phase 1 is strictly read-only: discover, list, watch. It does not change
//! grouping or playback. Deleted/rewritten once the real adapter exists.

use std::time::{Duration, Instant};

use sonos_sdk::SonosSystem;

fn main() {
    // Q1: does SonosSystem::new() block, and for how long? (cache-first)
    let t0 = Instant::now();
    let system = match SonosSystem::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("SonosSystem::new() FAILED after {:?}: {e:?}", t0.elapsed());
            std::process::exit(1);
        }
    };
    let new_elapsed = t0.elapsed();
    println!("== SonosSystem::new() returned in {new_elapsed:?} ==");

    // Q2: what does discovery surface? Names are definitely Vec<String>.
    let names = system.speaker_names();
    println!("\n== speaker_names ({}) ==", names.len());
    for n in &names {
        println!("  - {n}");
    }

    let speakers = system.speakers();
    println!("\n== speakers ({}) ==", speakers.len());
    for sp in &speakers {
        println!(
            "  id={:?} name={:?} ip={} model={:?}",
            sp.id, sp.name, sp.ip, sp.model_name
        );
        println!(
            "    volume.get()={:?}  mute.get()={:?}  playback_state.get()={:?}",
            sp.volume.get(),
            sp.mute.get(),
            sp.playback_state.get()
        );
    }

    let groups = system.groups();
    println!("\n== groups ({}) ==", groups.len());
    for g in &groups {
        let coord = g.coordinator();
        println!(
            "  id={:?} members={} standalone={} coordinator={:?}",
            g.id,
            g.member_count(),
            g.is_standalone(),
            coord.as_ref().map(|c| &c.name)
        );
        for m in g.members() {
            println!("    member: id={:?} name={:?}", m.id, m.name);
        }
        // D2 cross-check: sonos-sdk exposes playback_state per-speaker on
        // the coordinator; oto-core models it on Group. This is the seam.
        if let Some(c) = coord {
            println!(
                "    coordinator.playback_state.get()={:?}",
                c.playback_state.get()
            );
        }
    }

    // Q3: event model. iter() yields only previously-.watch()'d properties,
    // and this spike watches nothing yet — so an empty 12s window is itself
    // the finding (confirms watch-is-required). Change volume/playback in
    // the Sonos app during the window to double-check nothing leaks through.
    println!("\n== watching events for 12s (no .watch() registered) ==");
    let it = system.iter();
    let deadline = Instant::now() + Duration::from_secs(12);
    let mut count = 0u32;
    while Instant::now() < deadline {
        match it.recv_timeout(Duration::from_secs(3)) {
            Some(ev) => {
                count += 1;
                println!("  event #{count}: {ev:?}");
            }
            None => println!("  (idle 3s)"),
        }
    }
    println!("\n== total events: {count} ==");
    println!("== spike phase 1 done ==");
}
