//! P0c — ZoneGroupTopology subscription probe (v0.5 prereq, THROWAWAY).
//!
//! Confirms on real hardware that `sonos-sdk-state` `=0.5.2` delivers a
//! change signal when speakers are regrouped, so v0.5 S1 (topology events)
//! can ride the existing event pump. Run against a real Sonos LAN:
//!
//!   cargo run -p oto-wire --example topology_probe --features live-tests
//!
//! Then, in the Sonos app, form a group and then break it. Watch stdout.
//!
//! Gated behind `live-tests` so it never compiles into normal builds (the
//! binary is empty unless `--features live-tests`), matching the
//! `ssdp_multicast_if_probe` example convention. It's an EXAMPLE (not a
//! `tests/` integration test) so it can reach the crate's normal
//! `[dependencies]` — `sonos_state` / `sonos_event_manager` — without any
//! Cargo.toml change, and touches no production source. THROWAWAY: parked on
//! branch `feat/v0.5-p0c-zgt-probe`; delete or fold into S1 when topology
//! events are implemented.
//!
//! KEY FINDING (read from SDK source 2026-05-30; this probe verifies it on
//! hardware): the v0.5 plan's original assumption was wrong. There is no
//! `ZoneGroupTopology` *property* to watch — `ZoneGroupTopology` is a
//! `Service`. Topology changes surface via the watchable property
//! **`GroupMembership`** (`KEY = "group_membership"`,
//! `SERVICE = ZoneGroupTopology`, `SCOPE = Speaker`). The SDK handles ZGT
//! NOTIFYs on a special path (`event_worker.rs:49`) and emits a
//! `ChangeEvent { property_key: "group_membership", .. }` for every speaker
//! whose membership changed AND is in the `watched` set. So S1 must register
//! `watch_property_with_subscription::<GroupMembership>` PER SPEAKER (not
//! per-coordinator) and map `"group_membership" => ChangeEvent::TopologyChanged`.

#[cfg(not(feature = "live-tests"))]
fn main() {
    eprintln!("topology_probe is gated behind `--features live-tests`; rebuild with it to run.");
}

#[cfg(feature = "live-tests")]
fn main() {
    use std::{
        io::Write,
        sync::Arc,
        time::{Duration, Instant},
    };

    use oto_core::Wire;
    use oto_wire::SonosWire;

    use sonos_event_manager::{Device, SonosEventManager};
    // Import paths mirror the production pump (crates/wire/src/events.rs)
    // exactly, which is known-compiling against `=0.5.2`.
    use sonos_state::model::Speaker as SdkSpeaker;
    use sonos_state::property::{GroupInfo, Topology};
    use sonos_state::{
        GroupId as SdkGroupId, GroupMembership, SpeakerId as SdkSpeakerId, StateManager,
    };

    // The watchable-property key the SDK stamps on a topology-derived change
    // (mirrors `<GroupMembership as Property>::KEY`).
    const GROUP_MEMBERSHIP_KEY: &str = "group_membership";

    // 1. Real discovery for speaker IPs + current topology.
    let wire = SonosWire::new();
    let snap = wire.discover().expect("discover");
    println!(
        "Discovered {} speakers / {} groups",
        snap.speakers.len(),
        snap.groups.len()
    );
    assert!(
        !snap.speakers.is_empty(),
        "probe needs at least one speaker"
    );

    // 2. Build the SDK stack directly (mirrors src/events.rs::spawn). We do
    //    NOT use SonosWire's pump — it watches Volume/Mute/Playback/Track but
    //    not GroupMembership, which is exactly what this probe must observe.
    let devices: Vec<Device> = snap
        .speakers
        .iter()
        .map(|s| Device {
            id: s.id.as_str().to_string(),
            name: s.room_name.clone(),
            room_name: s.room_name.clone(),
            ip_address: s.ip.to_string(),
            port: 1400,
            model_name: String::new(),
        })
        .collect();

    let sdk_speakers: Vec<SdkSpeaker> = snap
        .speakers
        .iter()
        .map(|s| SdkSpeaker {
            id: SdkSpeakerId::new(s.id.as_str()),
            name: s.room_name.clone(),
            room_name: s.room_name.clone(),
            ip_address: s.ip,
            port: 1400,
            model_name: String::new(),
            software_version: "unknown".to_string(),
            boot_seq: 0,
            satellites: vec![],
        })
        .collect();

    let groups: Vec<GroupInfo> = snap
        .groups
        .iter()
        .map(|g| GroupInfo {
            id: SdkGroupId::new(g.id.as_str()),
            coordinator_id: SdkSpeakerId::new(g.coordinator.as_str()),
            member_ids: g
                .members
                .iter()
                .map(|m| SdkSpeakerId::new(m.as_str()))
                .collect(),
        })
        .collect();

    let em = Arc::new(SonosEventManager::new().expect("event manager init"));
    let manager = StateManager::builder()
        .with_event_manager(Arc::clone(&em))
        .build()
        .expect("state manager build");
    manager.add_devices(devices).expect("add_devices");
    manager.initialize(Topology::new(sdk_speakers, groups));

    // 3. Watch GroupMembership PER SPEAKER (membership is speaker-scoped).
    for s in &snap.speakers {
        let sid = SdkSpeakerId::new(s.id.as_str());
        let _ = manager.watch_property_with_subscription::<GroupMembership>(&sid);
    }

    // 4. Drain the seed NOTIFYs (~3 s) so we only count regroup-driven events.
    let iter = manager.iter();
    let drain_end = Instant::now() + Duration::from_secs(3);
    while Instant::now() < drain_end {
        let _ = iter.recv_timeout(Duration::from_millis(100));
    }

    print!(
        "\n>>> Now REGROUP in the Sonos app: add a room to a group, then \
         remove it. Watching 5 min...\n\n"
    );
    std::io::stdout().flush().unwrap();

    // 5. Observe. Print every event; flag the topology ones.
    let mut gm_count = 0usize;
    let deadline = Instant::now() + Duration::from_secs(300);
    while Instant::now() < deadline {
        if let Some(ev) = iter.recv_timeout(Duration::from_millis(500)) {
            let marker = if ev.property_key == GROUP_MEMBERSHIP_KEY {
                gm_count += 1;
                ">>> TOPOLOGY"
            } else {
                "    other   "
            };
            println!(
                "{marker}  speaker={}  key={}  service={:?}",
                ev.speaker_id.as_str(),
                ev.property_key,
                ev.service
            );
            std::io::stdout().flush().unwrap();
        }
    }

    println!("\n=== P0c probe done: {gm_count} group_membership event(s) observed ===");
    if gm_count == 0 {
        eprintln!(
            "WARNING: no group_membership events seen — either no regroup happened, \
             or ZGT NOTIFYs are not arriving. This is the P0c risk path (fall back to \
             the v0.4 stale-GroupId -> NotFound contract). See the v0.5 plan Task 2."
        );
    }
}
