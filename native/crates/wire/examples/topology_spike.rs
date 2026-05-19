//! Throwaway de-risking spike — NOT part of the product.
//!
//! Gates the v0.3 grouping design. Answers the ZoneGroupTopology questions
//! in `docs/plans/2026-05-19-v0.3-grouping-spike.md`:
//!
//! - Is direct-SOAP `GetZoneGroupState` the *deterministic, complete*
//!   topology path that `SonosSystem` (v0.1 Open Q1, flapped 1-of-4 ↔ 0)
//!   was not?
//! - Does the crate's `parse_zone_group_state_xml` decode the
//!   *control-response* string (the v0.2 DIDL-equivalent: lib-decodes vs.
//!   we-parse-XML-ourselves)?
//! - Does the bonded stereo-pair / home-theater surround case surface as
//!   `satellites` / `invisible` (the long-deferred Open Q4 / oto-core
//!   bonded-speaker question)?
//!
//! Run on a machine with Sonos speakers on the LAN. **Read-only by
//! default.** `--play-check` (Q5) issues a real `play` and requires you to
//! have formed a ≥2-room group in the Sonos app first (with something
//! queued).
//!
//! ```text
//! cargo run -p oto-wire --example topology_spike -- 10.83.0.103 [10.83.0.187 ...]
//! cargo run -p oto-wire --example topology_spike -- --play-check 10.83.0.103
//! ```
//!
//! Deleted once the v0.3 grouping adapter exists.

use std::time::Instant;

use sonos_api::services::{av_transport, zone_group_topology};
use sonos_api::SonosClient;

const ITERS: usize = 10;

fn main() {
    let raw_args: Vec<String> = std::env::args().skip(1).collect();
    let play_check = raw_args.iter().any(|a| a == "--play-check");
    let ips: Vec<String> = raw_args
        .into_iter()
        .filter(|a| a != "--play-check")
        .collect();
    if ips.is_empty() {
        eprintln!("usage: topology_spike [--play-check] <speaker-ip> [more-ips...]");
        std::process::exit(2);
    }

    let client = SonosClient::new();

    // ── Q1 + Q2: dispatch, sync timing, determinism, per-network parity ──
    for ip in &ips {
        println!("\n================ speaker {ip} ================");
        let mut variants: Vec<String> = Vec::new();
        let mut counts: Vec<(usize, usize)> = Vec::new(); // (groups, members-total)
        let mut ok_calls = 0usize;
        for i in 0..ITERS {
            let t0 = Instant::now();
            let op = match zone_group_topology::get_zone_group_state().build() {
                Ok(o) => o,
                Err(e) => {
                    eprintln!("  build error: {e}");
                    std::process::exit(1);
                }
            };
            match client.execute_enhanced(ip, op) {
                Ok(resp) => {
                    let dt = t0.elapsed();
                    let xml = resp.zone_group_state;
                    let parsed = zone_group_topology::parse_zone_group_state_xml(&xml);
                    let (g, m) = match &parsed {
                        Ok(groups) => (
                            groups.len(),
                            groups.iter().map(|x| x.members.len()).sum::<usize>(),
                        ),
                        Err(_) => (usize::MAX, usize::MAX),
                    };
                    ok_calls += 1;
                    counts.push((g, m));
                    if !variants.contains(&xml) {
                        variants.push(xml);
                    }
                    println!(
                        "  call {:>2}/{ITERS}: {dt:?}  groups={g} members={m} parse={}",
                        i + 1,
                        if parsed.is_ok() { "ok" } else { "ERR" }
                    );
                }
                Err(e) => eprintln!("  call {}/{ITERS}: execute_enhanced ERR: {e:?}", i + 1),
            }
        }
        // Determinism verdict — the v0.1 SonosSystem path flapped this.
        let count_stable = counts.len() >= 2 && counts.windows(2).all(|w| w[0] == w[1]);
        println!(
            "  -> {ok_calls}/{ITERS} ok ; distinct XML variants: {} ; count-stable: {count_stable}",
            variants.len()
        );

        // ── Q3 + Q4: raw XML dump + structured parse for this speaker ──
        if let Some(xml) = variants.first() {
            println!("\n  ---- raw ZoneGroupState XML ({} bytes) ----", xml.len());
            println!("{xml}");
            println!("  ---- end raw XML ----\n");
            match zone_group_topology::parse_zone_group_state_xml(xml) {
                Ok(groups) => {
                    println!(
                        "  ---- parse_zone_group_state_xml -> {} group(s) ----",
                        groups.len()
                    );
                    for grp in &groups {
                        let coord_in_members =
                            grp.members.iter().any(|mem| mem.uuid == grp.coordinator);
                        println!(
                            "  group id={} coordinator={} coord-in-members={coord_in_members} (oto-core D3)",
                            grp.id, grp.coordinator
                        );
                        for mem in &grp.members {
                            println!(
                                "    member uuid={} zone={:?} loc={} satellites={}",
                                mem.uuid,
                                mem.zone_name,
                                mem.location,
                                mem.satellites.len()
                            );
                            for sat in &mem.satellites {
                                println!(
                                    "      satellite uuid={} zone={:?} invisible={:?} htSatChanMapSet={:?}",
                                    sat.uuid, sat.zone_name, sat.invisible, sat.ht_sat_chan_map_set
                                );
                            }
                        }
                    }
                    println!("  ---- end parse ----");
                }
                Err(e) => println!(
                    "  parse_zone_group_state_xml FAILED: {e:?}\n  → oto-wire must parse the XML itself (quick-xml, like DIDL in v0.2)"
                ),
            }
        }
    }

    // ── Q5: coordinator → whole-group play (user-gated, mutating) ──
    if play_check {
        let ip = &ips[0];
        println!("\n================ Q5 play-check via {ip} ================");
        let op = zone_group_topology::get_zone_group_state()
            .build()
            .expect("build get_zone_group_state");
        let resp = client.execute_enhanced(ip, op).expect("get topology");
        let groups = zone_group_topology::parse_zone_group_state_xml(&resp.zone_group_state)
            .expect("parse topology");
        let Some(grp) = groups.iter().find(|g| g.members.len() >= 2) else {
            eprintln!("  no ≥2-member group — form a 2-room group in the Sonos app first");
            std::process::exit(3);
        };
        let coord_ip = grp
            .members
            .iter()
            .find(|m| m.uuid == grp.coordinator)
            .map(|m| host_of(&m.location))
            .unwrap_or_default();
        println!(
            "  group id={} coordinator={} ip={coord_ip} members={}",
            grp.id,
            grp.coordinator,
            grp.members.len()
        );
        println!("  issuing av_transport::play at coordinator {coord_ip} …");
        let pop = av_transport::play("1".to_string())
            .build()
            .expect("build play");
        match client.execute_enhanced(&coord_ip, pop) {
            Ok(_) => println!(
                "  play -> Ok  → OBSERVE: do ALL rooms in the group start? \
                 (confirms the v0.2 GroupId→coordinator→IP seam generalises)"
            ),
            Err(e) => println!("  play -> ERR: {e:?}"),
        }
    }

    println!("\n== topology spike done ==");
}

/// `http://10.83.0.103:1400/xml/device_description.xml` → `10.83.0.103`
fn host_of(location: &str) -> String {
    location
        .strip_prefix("http://")
        .unwrap_or(location)
        .split([':', '/'])
        .next()
        .unwrap_or("")
        .to_string()
}
