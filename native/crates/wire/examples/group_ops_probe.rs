//! group_ops_probe - group-operation SOAP + event hardware probe (v0.5.1, THROWAWAY).
//!
//! Confirms on real hardware the SOAP behaviors needed by v0.5.1:
//!   - JOIN:  `SetAVTransportURI` with `x-rincon:<coordinator_id>`
//!   - LEAVE: `BecomeCoordinatorOfStandaloneGroup`
//!   - GROUP-VOLUME COMMANDS: `GetGroupVolume`, `SetGroupVolume`,
//!     `SetRelativeGroupVolume`, `GetGroupMute`, `SetGroupMute`
//!   - GROUP-VOLUME EVENTS: `GroupVolume` / `GroupMute` watchable properties
//!   - FAST TOPOLOGY REFRESH: `manager.initialize(new_topology)` on a live StateManager
//!
//! Run against a real Sonos LAN (4 speakers recommended):
//!
//!   cargo run -p oto-wire --example group_ops_probe --features live-tests
//!
//! Gated behind `live-tests` so it never compiles in normal builds.
//! THROWAWAY: delete or fold into the v0.5.1 implementation once findings
//! are recorded in sonos-notes.md.

#[cfg(not(feature = "live-tests"))]
fn main() {
    eprintln!(
        "group_ops_probe is gated behind `--features live-tests`; \
         rebuild with it to run."
    );
}

#[cfg(feature = "live-tests")]
fn main() {
    use std::{
        io::Write as IoWrite,
        net::IpAddr,
        sync::Arc,
        time::{Duration, Instant},
    };

    use oto_core::Wire;
    use oto_wire::SonosWire;

    use sonos_api::{
        SonosClient,
        services::{av_transport, group_rendering_control, zone_group_topology},
    };
    use sonos_event_manager::{Device, SonosEventManager};
    use sonos_state::{
        GroupId as SdkGroupId, GroupMute, GroupVolume, SpeakerId as SdkSpeakerId, StateManager,
        model::Speaker as SdkSpeaker,
        property::{GroupInfo, Property, Topology},
    };

    // =========================================================================
    // SECTION 1 - DISCOVER + PRINT TOPOLOGY
    // =========================================================================
    println!("========================================================");
    println!(" group_ops_probe - v0.5.1 hardware probe");
    println!("========================================================");

    let wire = SonosWire::new();
    let snap = wire.discover().expect("discover");
    println!(
        "\nDiscovered {} speakers / {} groups\n",
        snap.speakers.len(),
        snap.groups.len()
    );

    for s in &snap.speakers {
        println!(
            "  speaker  id={}  room={}  ip={}",
            s.id.as_str(),
            s.room_name,
            s.ip
        );
    }
    for g in &snap.groups {
        println!(
            "  group    id={}  coordinator={}  members={:?}",
            g.id.as_str(),
            g.coordinator.as_str(),
            g.members.iter().map(|m| m.as_str()).collect::<Vec<_>>()
        );
    }

    if snap.speakers.is_empty() {
        eprintln!("SKIP: no speakers discovered - aborting.");
        return;
    }

    // Helper: look up IP for a speaker id.
    let ip_for = |sid: &oto_core::identifiers::SpeakerId| -> Option<String> {
        snap.speakers
            .iter()
            .find(|s| &s.id == sid)
            .map(|s| match s.ip {
                IpAddr::V4(v4) => v4.to_string(),
                IpAddr::V6(v6) => v6.to_string(),
            })
    };

    let client = SonosClient::new();

    // Pick a coordinator for the volume/mute tests: the coordinator of the
    // first group that has at least one member.
    let coord_id = snap.groups.first().map(|g| g.coordinator.clone());
    let coord_ip = coord_id.as_ref().and_then(&ip_for);

    // Any speaker IP to use for ZGT re-polls.
    let any_ip = snap.speakers.first().map(|s| match s.ip {
        IpAddr::V4(v4) => v4.to_string(),
        IpAddr::V6(v6) => v6.to_string(),
    });

    // =========================================================================
    // SECTION 2 - JOIN PROBE
    // =========================================================================
    println!("\n========================================================");
    println!(" SECTION 2 - JOIN PROBE (SetAVTransportURI x-rincon:…)");
    println!("========================================================");

    // Find a standalone speaker (group.members.len() == 1) as the joiner (S),
    // and a *different* coordinator (C) to join.
    let standalone = snap.groups.iter().find(|g| {
        g.members.len() == 1
            && snap
                .groups
                .first()
                .map(|f| g.coordinator != f.coordinator)
                .unwrap_or(false)
    });

    // Also accept: first group with 1 member where there exists another group to join.
    let (join_src, join_dst) = if snap.groups.len() >= 2 {
        let src = snap
            .groups
            .iter()
            .find(|g| g.members.len() == 1)
            .or_else(|| snap.groups.first());
        let dst = snap
            .groups
            .iter()
            .find(|g| src.map(|s| g.coordinator != s.coordinator).unwrap_or(true));
        (src, dst)
    } else {
        (standalone, None)
    };

    match (join_src, join_dst) {
        (Some(src), Some(dst)) => {
            let src_ip = match ip_for(&src.coordinator) {
                Some(ip) => ip,
                None => {
                    println!(
                        "SKIP: cannot resolve IP for source speaker {}",
                        src.coordinator.as_str()
                    );
                    String::new()
                }
            };
            let dst_coordinator_id = dst.coordinator.as_str();

            if !src_ip.is_empty() {
                println!(
                    "JOIN: sending {} (ip={}) to join coordinator {} (group={})",
                    src.coordinator.as_str(),
                    src_ip,
                    dst_coordinator_id,
                    dst.id.as_str()
                );
                let join_uri = format!("x-rincon:{dst_coordinator_id}");
                let op = av_transport::set_av_transport_uri(join_uri, String::new())
                    .build()
                    .expect("build set_av_transport_uri");
                match client.execute_enhanced(&src_ip, op) {
                    Ok(_) => println!("  SetAVTransportURI → OK"),
                    Err(e) => println!("  SetAVTransportURI → ERR: {e:?}"),
                }

                // Re-poll topology to see if the join took effect.
                if let Some(ref aip) = any_ip {
                    match zone_group_topology::get_zone_group_state().build() {
                        Ok(op) => match client.execute_enhanced(aip, op) {
                            Ok(resp) => {
                                match zone_group_topology::parse_zone_group_state_xml(
                                    &resp.zone_group_state,
                                ) {
                                    Ok(groups) => {
                                        println!("  Post-join topology ({} groups):", groups.len());
                                        for g in &groups {
                                            let member_ids: Vec<&str> =
                                                g.members.iter().map(|m| m.uuid.as_str()).collect();
                                            let has_src =
                                                member_ids.contains(&src.coordinator.as_str());
                                            println!(
                                                "    group id={}  coord={}  members={:?}  {}",
                                                g.id,
                                                g.coordinator,
                                                member_ids,
                                                if has_src { "<-- src joined here" } else { "" }
                                            );
                                        }
                                    }
                                    Err(e) => println!("  parse_zone_group_state_xml ERR: {e:?}"),
                                }
                            }
                            Err(e) => println!("  GetZoneGroupState ERR: {e:?}"),
                        },
                        Err(e) => println!("  build GetZoneGroupState ERR: {e:?}"),
                    }
                }
            }
        }
        _ => {
            println!(
                "SKIP JOIN: need at least 2 groups (found {}).  \
                 Add a second room in the Sonos app, then re-run.",
                snap.groups.len()
            );
        }
    }

    // =========================================================================
    // SECTION 3 - LEAVE PROBE
    // =========================================================================
    println!("\n========================================================");
    println!(" SECTION 3 - LEAVE PROBE (BecomeCoordinatorOfStandaloneGroup)");
    println!("========================================================");

    // Re-discover so we see the group just formed in SECTION 2 (the original
    // `snap` is pre-join). On this 2-zone bonded-satellite LAN the only group
    // we can form is a 2-member one (Beam + Sonos One) - leaving its
    // coordinator is the coordinator-leave case we can actually exercise here.
    let leave_snap = wire.discover().unwrap_or_else(|_| snap.clone());
    let leave_group = leave_snap.groups.iter().find(|g| g.members.len() >= 2);
    match leave_group {
        Some(g) => {
            // Use the coordinator's IP for the leave command (BCOS is sent to
            // the speaker that wants to become standalone).
            let coord_ip_leave = match ip_for(&g.coordinator) {
                Some(ip) => ip,
                None => {
                    println!(
                        "SKIP: cannot resolve IP for coordinator {}",
                        g.coordinator.as_str()
                    );
                    String::new()
                }
            };
            if !coord_ip_leave.is_empty() {
                println!(
                    "LEAVE (coordinator): sending BecomeCoordinatorOfStandaloneGroup to {} (group={}  {} members)",
                    g.coordinator.as_str(),
                    g.id.as_str(),
                    g.members.len()
                );
                let op = av_transport::become_coordinator_of_standalone_group()
                    .build()
                    .expect("build become_coordinator_of_standalone_group");
                match client.execute_enhanced(&coord_ip_leave, op) {
                    Ok(resp) => println!(
                        "  BecomeCoordinatorOfStandaloneGroup → OK  \
                         delegated_group_coordinator_id={}  new_group_id={}",
                        resp.delegated_group_coordinator_id, resp.new_group_id
                    ),
                    Err(e) => println!("  BecomeCoordinatorOfStandaloneGroup → ERR: {e:?}"),
                }

                // Re-poll topology.
                if let Some(ref aip) = any_ip {
                    match zone_group_topology::get_zone_group_state().build() {
                        Ok(op) => match client.execute_enhanced(aip, op) {
                            Ok(resp) => {
                                match zone_group_topology::parse_zone_group_state_xml(
                                    &resp.zone_group_state,
                                ) {
                                    Ok(groups) => {
                                        println!(
                                            "  Post-leave topology ({} groups):",
                                            groups.len()
                                        );
                                        for grp in &groups {
                                            let member_ids: Vec<&str> = grp
                                                .members
                                                .iter()
                                                .map(|m| m.uuid.as_str())
                                                .collect();
                                            println!(
                                                "    group id={}  coord={}  members={:?}",
                                                grp.id, grp.coordinator, member_ids
                                            );
                                        }
                                    }
                                    Err(e) => println!("  parse_zone_group_state_xml ERR: {e:?}"),
                                }
                            }
                            Err(e) => println!("  GetZoneGroupState ERR: {e:?}"),
                        },
                        Err(e) => println!("  build GetZoneGroupState ERR: {e:?}"),
                    }
                }
            }
        }
        None => {
            println!(
                "SKIP LEAVE (no multi-member group present after re-discover).  \
                 Ensure SECTION 2 JOIN succeeded (Beam + Sonos One grouped), then re-run."
            );
        }
    }

    // ── SECTION 3b - 3+-member coordinator-leave: N/A on this 2-zone LAN ──────
    //
    // This household has only 2 *controllable* zones: the Beam (its bonded
    // surround satellites are Invisible="1" and fold into the Beam - one zone)
    // and the Sonos One. A 3-member group therefore can't be formed, so the
    // "coordinator leaves, 2+ members remain and re-elect" case is not
    // exercisable here.
    //
    // It does NOT need a probe to de-risk the design: `leave_group(speaker)`
    // issues the SAME `BecomeCoordinatorOfStandaloneGroup` primitive regardless
    // of whether `speaker` coordinates a group. When a coordinator of a
    // multi-member group leaves, the Sonos household firmware elects the new
    // coordinator for the remaining members (standard Sonos behaviour); oto
    // simply re-pulls topology afterward and reflects whatever the household
    // decided. So there is no special-case branch to design - the 2-member
    // coordinator-leave above already confirms the BCOS-on-a-coordinator path.
    // The 3+-member re-election is firmware-handled and untested on this
    // hardware; revisit only if a user with 3+ independent zones reports an
    // issue.
    println!("\n========================================================");
    println!(" SECTION 3b - 3+-member coordinator-leave: N/A on this 2-zone LAN");
    println!("   bonded surrounds are not independent zones; firmware handles");
    println!("   re-election for 3+ members. See the leave_group design note.");
    println!("========================================================");

    // =========================================================================
    // SECTION 4 - GROUP-VOLUME COMMAND PROBE
    // =========================================================================
    println!("\n========================================================");
    println!(" SECTION 4 - GROUP-VOLUME COMMAND PROBE (GroupRenderingControl)");
    println!("========================================================");

    match (&coord_id, &coord_ip) {
        (Some(cid), Some(cip)) => {
            println!("Using coordinator: {}  ip={}", cid.as_str(), cip);

            // GetGroupVolume
            match group_rendering_control::get_group_volume().build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(resp) => {
                        println!("  GetGroupVolume → current_volume={}", resp.current_volume)
                    }
                    Err(e) => println!("  GetGroupVolume → ERR: {e:?}"),
                },
                Err(e) => println!("  build GetGroupVolume → ERR: {e:?}"),
            }

            // SetGroupVolume to 30
            match group_rendering_control::set_group_volume(30).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(_) => println!("  SetGroupVolume(30) → OK"),
                    Err(e) => println!("  SetGroupVolume(30) → ERR: {e:?}"),
                },
                Err(e) => println!("  build SetGroupVolume(30) → ERR: {e:?}"),
            }

            // SetGroupVolume to 50 (confirm value sticks)
            match group_rendering_control::set_group_volume(50).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(_) => println!("  SetGroupVolume(50) → OK"),
                    Err(e) => println!("  SetGroupVolume(50) → ERR: {e:?}"),
                },
                Err(e) => println!("  build SetGroupVolume(50) → ERR: {e:?}"),
            }

            // Probe over-100 clamping: the SDK validates at build time (desired_volume: u16
            // with validate_basic rejecting > 100), so this tests the builder's validation.
            println!(
                "  SetGroupVolume(101) [over-100 clamping test - expect build-time ValidationError]:"
            );
            match group_rendering_control::set_group_volume(101).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(_) => println!(
                        "    → OK (device accepted 101 - NOTE: no SDK clamp, device clamped or accepted)"
                    ),
                    Err(e) => println!("    → device ERR: {e:?}"),
                },
                Err(e) => println!("    → build-time Err (clamped by SDK validator): {e:?}"),
            }

            // SetRelativeGroupVolume +5
            match group_rendering_control::set_relative_group_volume(5).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(resp) => println!(
                        "  SetRelativeGroupVolume(+5) → new_volume={}",
                        resp.new_volume
                    ),
                    Err(e) => println!("  SetRelativeGroupVolume(+5) → ERR: {e:?}"),
                },
                Err(e) => println!("  build SetRelativeGroupVolume(+5) → ERR: {e:?}"),
            }

            // SetRelativeGroupVolume -5
            match group_rendering_control::set_relative_group_volume(-5).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(resp) => println!(
                        "  SetRelativeGroupVolume(-5) → new_volume={}",
                        resp.new_volume
                    ),
                    Err(e) => println!("  SetRelativeGroupVolume(-5) → ERR: {e:?}"),
                },
                Err(e) => println!("  build SetRelativeGroupVolume(-5) → ERR: {e:?}"),
            }

            // GetGroupMute
            match group_rendering_control::get_group_mute().build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(resp) => println!("  GetGroupMute → current_mute={}", resp.current_mute),
                    Err(e) => println!("  GetGroupMute → ERR: {e:?}"),
                },
                Err(e) => println!("  build GetGroupMute → ERR: {e:?}"),
            }

            // SetGroupMute true
            match group_rendering_control::set_group_mute(true).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(_) => println!("  SetGroupMute(true) → OK"),
                    Err(e) => println!("  SetGroupMute(true) → ERR: {e:?}"),
                },
                Err(e) => println!("  build SetGroupMute(true) → ERR: {e:?}"),
            }

            // SetGroupMute false (restore)
            match group_rendering_control::set_group_mute(false).build() {
                Ok(op) => match client.execute_enhanced(cip, op) {
                    Ok(_) => println!("  SetGroupMute(false) → OK"),
                    Err(e) => println!("  SetGroupMute(false) → ERR: {e:?}"),
                },
                Err(e) => println!("  build SetGroupMute(false) → ERR: {e:?}"),
            }
        }
        _ => {
            println!("SKIP: no coordinator or IP available for group-volume command probe.");
        }
    }

    // =========================================================================
    // SECTION 5 - GROUP-VOLUME EVENT PROBE
    // =========================================================================
    println!("\n========================================================");
    println!(" SECTION 5 - GROUP-VOLUME EVENT PROBE (GroupVolume / GroupMute properties)");
    println!("========================================================");

    // Rebuild the SDK event stack (mirrors topology_probe).
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

    let sdk_groups: Vec<GroupInfo> = snap
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
    manager.add_devices(devices.clone()).expect("add_devices");
    manager.initialize(Topology::new(sdk_speakers.clone(), sdk_groups.clone()));
    // SDK 0.8 iterators do not replay events emitted before subscription.
    let iter = manager.iter();

    // Watch GroupVolume and GroupMute per coordinator.
    for g in &snap.groups {
        let sid = SdkSpeakerId::new(g.coordinator.as_str());
        let _ = manager.watch_property_with_subscription::<GroupVolume>(&sid);
        let _ = manager.watch_property_with_subscription::<GroupMute>(&sid);
    }

    // Drain seed NOTIFYs (~3 s).
    let drain_end = Instant::now() + Duration::from_secs(3);
    while Instant::now() < drain_end {
        let _ = iter.recv_timeout(Duration::from_millis(100));
    }
    println!("  (seed NOTIFYs drained)");

    print!(
        "\n>>> OPERATOR ACTION: in the Sonos app change a group's volume or mute.\n\
         >>> Watching for ~2 min. Press Ctrl+C to abort early.\n\n"
    );
    std::io::stdout().flush().unwrap();

    let mut group_vol_count = 0usize;
    let mut group_mute_count = 0usize;
    let deadline = Instant::now() + Duration::from_secs(120);
    while Instant::now() < deadline {
        if let Some(ev) = iter.recv_timeout(Duration::from_millis(500)) {
            let marker = if ev.property_key() == GroupVolume::KEY {
                group_vol_count += 1;
                ">>> GROUP_VOLUME"
            } else if ev.property_key() == GroupMute::KEY {
                group_mute_count += 1;
                ">>> GROUP_MUTE  "
            } else {
                "    other       "
            };
            println!(
                "{marker}  speaker={}  key={}  service={:?}",
                ev.speaker_id.as_str(),
                ev.property_key(),
                ev.service()
            );
            std::io::stdout().flush().unwrap();
        }
    }
    println!(
        "\n  Section 5 summary: group_volume_events={}  group_mute_events={}",
        group_vol_count, group_mute_count
    );

    // =========================================================================
    // SECTION 6 - OPTION D PROBE (re-initialize live StateManager)
    // =========================================================================
    println!("\n========================================================");
    println!(" SECTION 6 - OPTION D PROBE (manager.initialize on live StateManager)");
    println!(" [EXPLORATORY - informs in-place-vs-respawn decision for v0.5.1]");
    println!("========================================================");

    print!(
        "\n>>> OPERATOR ACTION: in the Sonos app, regroup (add/remove a room).\n\
         >>> Then press Enter to fetch fresh topology and re-initialize the live manager.\n\
         >>> (Press 's' + Enter to skip): "
    );
    std::io::stdout().flush().unwrap();
    let mut line2 = String::new();
    let _ = std::io::stdin().read_line(&mut line2);

    if !line2.trim().eq_ignore_ascii_case("s") {
        // Fetch fresh topology via SOAP.
        let fresh_groups_result = any_ip.as_ref().and_then(|aip| {
            zone_group_topology::get_zone_group_state()
                .build()
                .ok()
                .and_then(|op| client.execute_enhanced(aip, op).ok())
                .and_then(|resp| {
                    zone_group_topology::parse_zone_group_state_xml(&resp.zone_group_state).ok()
                })
        });

        match fresh_groups_result {
            Some(fresh_zgt) => {
                println!("  Fresh topology ({} groups):", fresh_zgt.len());
                for g in &fresh_zgt {
                    let mids: Vec<&str> = g.members.iter().map(|m| m.uuid.as_str()).collect();
                    println!(
                        "    group id={}  coord={}  members={:?}",
                        g.id, g.coordinator, mids
                    );
                }

                // Build new Topology from fresh ZGT data.
                // Only retain speakers we originally discovered (same sdk_speakers list);
                // new speakers won't have Device entries so we keep the original device list.
                let new_sdk_groups: Vec<GroupInfo> = fresh_zgt
                    .iter()
                    .map(|g| GroupInfo {
                        id: SdkGroupId::new(&g.id),
                        coordinator_id: SdkSpeakerId::new(&g.coordinator),
                        member_ids: g
                            .members
                            .iter()
                            .map(|m| SdkSpeakerId::new(&m.uuid))
                            .collect(),
                    })
                    .collect();

                let new_topology = Topology::new(sdk_speakers.clone(), new_sdk_groups);
                manager.initialize(new_topology);
                println!("  manager.initialize(new_topology) called on LIVE manager - OK");

                // Re-watch GroupVolume on any new coordinators.
                for g in &fresh_zgt {
                    let sid = SdkSpeakerId::new(&g.coordinator);
                    let _ = manager.watch_property_with_subscription::<GroupVolume>(&sid);
                    let _ = manager.watch_property_with_subscription::<GroupMute>(&sid);
                }

                // Observe for 30 s to see if subsequent events route correctly.
                print!(
                    "\n>>> Watching for 30 s after re-initialize - change a group volume in the \n\
                     >>> Sonos app now.\n\n"
                );
                std::io::stdout().flush().unwrap();

                let obs_end = Instant::now() + Duration::from_secs(30);
                let mut post_reinit_count = 0usize;
                while Instant::now() < obs_end {
                    if let Some(ev) = iter.recv_timeout(Duration::from_millis(500)) {
                        post_reinit_count += 1;
                        let marker = if ev.property_key() == GroupVolume::KEY
                            || ev.property_key() == GroupMute::KEY
                        {
                            ">>> GROUP_VOL/MUTE"
                        } else {
                            "    other         "
                        };
                        println!(
                            "  {marker}  speaker={}  key={}",
                            ev.speaker_id.as_str(),
                            ev.property_key()
                        );
                        std::io::stdout().flush().unwrap();
                    }
                }
                println!(
                    "\n  Fast topology result: {} event(s) received after re-initialize.  \
                     Check above whether they route to NEW coordinator IDs.",
                    post_reinit_count
                );
            }
            None => {
                println!("  SKIP: could not fetch fresh ZGT (no speaker IP or SOAP failed).");
            }
        }
    }

    // =========================================================================
    // CLOSING SUMMARY
    // =========================================================================
    println!("\n========================================================");
    println!(" group_ops_probe COMPLETE - record findings in sonos-notes.md");
    println!("  Key answers to look for:");
    println!("  Join: Does SetAVTransportURI x-rincon:ID join the speaker?");
    println!("  Leave: Does BecomeCoordinatorOfStandaloneGroup work on a member AND coordinator?");
    println!("  Leave: What happens to remaining members when coordinator leaves?");
    println!("  GroupVol: Does SetGroupVolume validate at > 100 or does device clamp?");
    println!("  Events: Do GroupVolume/GroupMute events fire per-coordinator?  Double-fire?");
    println!("  Fast topology: Does re-initialize route events to new coordinator?");
    println!("========================================================");
}
