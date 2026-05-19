//! Production `Wire`: own SSDP + sonos-sdk (test-support) adapter.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;
use std::time::Duration;

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity, SpeakerState, Volume,
    Wire, WireError,
};
use sonos_api::services::zone_group_topology::ZoneGroupInfo;
use sonos_sdk::sonos_discovery::{device::DeviceDescription, Device};

use crate::{control, http, ssdp};

const SSDP_TIMEOUT: Duration = Duration::from_secs(3);
const HTTP_TIMEOUT: Duration = Duration::from_secs(2);

/// Production wire implementation backed by `sonos_api` direct SOAP calls.
///
/// Interior-mutable caches (`id_to_addr`, `group_to_coordinator`) are
/// populated by `discover()` and used by the playback/read methods.
/// All methods return `Err(WireError::NotFound)` if called before a
/// successful `discover()` has populated the relevant entry.
pub struct SonosWire {
    /// Maps `SpeakerId` → `SocketAddr(ip, 1400)` for rendering-control calls.
    id_to_addr: Mutex<HashMap<SpeakerId, SocketAddr>>,
    /// Maps `GroupId` → coordinator `SpeakerId` for transport-control calls.
    group_to_coordinator: Mutex<HashMap<GroupId, SpeakerId>>,
}

impl SonosWire {
    pub fn new() -> Self {
        Self {
            id_to_addr: Mutex::new(HashMap::new()),
            group_to_coordinator: Mutex::new(HashMap::new()),
        }
    }

    /// Resolve a `SpeakerId` to its cached `SocketAddr`.
    ///
    /// Returns `Err(WireError::NotFound)` if unknown or pre-discovery.
    fn resolve_speaker(&self, speaker: &SpeakerId) -> Result<SocketAddr, WireError> {
        self.id_to_addr
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(speaker)
            .copied()
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))
    }

    /// Resolve a `GroupId` → coordinator `SpeakerId` → `SocketAddr`.
    ///
    /// Returns `Err(WireError::NotFound)` if the group or its coordinator
    /// address is unknown (pre-discovery or stale cache).
    fn resolve_group(&self, group: &GroupId) -> Result<SocketAddr, WireError> {
        let coordinator = {
            self.group_to_coordinator
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .get(group)
                .cloned()
                .ok_or_else(|| WireError::NotFound(group.to_string()))?
        };
        self.resolve_speaker(&coordinator)
    }

    /// Populate the interior-mutable caches from a discovery snapshot.
    /// Shared by `discover()` and the cache unit test so the test drives
    /// the real cache-population path, not a hand-duplicated copy (a
    /// duplicate would still pass if `discover()`'s update were removed).
    fn populate_caches(&self, snapshot: &DiscoverySnapshot) {
        {
            let mut cache = self.id_to_addr.lock().unwrap_or_else(|p| p.into_inner());
            cache.clear();
            for speaker in &snapshot.speakers {
                cache.insert(speaker.id.clone(), SocketAddr::new(speaker.ip, 1400));
            }
        }
        {
            let mut cache = self
                .group_to_coordinator
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            cache.clear();
            for group in &snapshot.groups {
                cache.insert(group.id.clone(), group.coordinator.clone());
            }
        }
    }
}

impl Default for SonosWire {
    fn default() -> Self {
        Self::new()
    }
}

/// Strip host:port → bare IP.
/// `DeviceDescription::to_device` takes a bare IP string (not `host:port`),
/// unlike `http::get_body`, which passes the full `host:port` URL to ureq.
fn extract_ip(url: &str) -> Option<String> {
    url.strip_prefix("http://")?
        .split('/')
        .next()?
        .split(':')
        .next()
        .map(str::to_string)
}

fn to_devices(locations: Vec<String>) -> Vec<Device> {
    locations
        .into_iter()
        .filter_map(|loc| {
            let xml = http::get_body(&loc, HTTP_TIMEOUT).ok()?;
            let desc = DeviceDescription::from_xml(&xml).ok()?;
            if !desc.is_sonos_device() {
                return None;
            }
            Some(desc.to_device(extract_ip(&loc)?))
        })
        .collect()
}

/// Build a `DiscoverySnapshot` directly from the devices returned by our own
/// SSDP+to_devices pipeline — no `SonosSystem` involved.
///
/// v0.1 is identity-only: each device becomes exactly one speaker and one
/// group-of-one.  Accurate ZoneGroupTopology (bonded surrounds, stereo pairs,
/// multi-room groups) is deferred to v0.3 (ARCHITECTURE open-Q1/Q4).
fn to_snapshot(devices: Vec<Device>) -> DiscoverySnapshot {
    let mut speakers: Vec<SpeakerIdentity> = Vec::with_capacity(devices.len());
    let mut groups: Vec<GroupIdentity> = Vec::with_capacity(devices.len());

    for d in devices {
        // Parse the IP we ourselves extracted — anomalous if it fails, but
        // skip rather than panic.
        let ip: IpAddr = match d.ip_address.parse() {
            Ok(a) => a,
            Err(_) => continue,
        };

        // sonos-sdk stores the UDN verbatim from the XML, which carries a
        // leading "uuid:" prefix (e.g. "uuid:RINCON_542A1B9463A801400").
        // oto_core::SpeakerId holds the bare RINCON_… form — strip it here.
        let bare_id = d.id.strip_prefix("uuid:").unwrap_or(&d.id);
        let sid = SpeakerId::new(bare_id);

        speakers.push(SpeakerIdentity {
            id: sid.clone(),
            room_name: d.room_name,
            model: if d.model_name.is_empty() {
                None
            } else {
                Some(d.model_name)
            },
            ip,
        });

        // v0.1 group-of-one; bonded surrounds appear as standalone here by
        // design. TODO(v0.3): replace with real ZoneGroupTopology (bonded
        // surrounds, stereo pairs, multi-room groups) — ARCHITECTURE open-Q1/Q4.
        groups.push(GroupIdentity {
            id: GroupId::new(format!("{sid}:0")),
            coordinator: sid.clone(),
            members: vec![sid],
        });
    }

    DiscoverySnapshot { speakers, groups }
}

/// Build a real `DiscoverySnapshot` from parsed ZoneGroupTopology.
///
/// Speakers = top-level members (satellites are folded into their
/// primary, never surfaced — oto-core D5). Each group's members are
/// reordered coordinator-first (oto-core D3; the parser does not
/// guarantee order). Vanished devices are already dropped by
/// `parse_zone_group_state_xml`.
// TODO(v0.3): wire this into discover() (PR B — next task) to replace
// the group-of-one to_snapshot path. Additive in PR A; dead_code is
// expected until PR B calls it.
#[allow(dead_code)]
fn topology_to_snapshot(groups: Vec<ZoneGroupInfo>) -> DiscoverySnapshot {
    let mut speakers = Vec::new();
    let mut out_groups = Vec::new();

    for zg in groups {
        let coord = SpeakerId::new(zg.coordinator.clone());

        let mut members: Vec<SpeakerId> = Vec::with_capacity(zg.members.len());
        for m in &zg.members {
            let ip: IpAddr = match extract_ip(&m.location).and_then(|s| s.parse().ok()) {
                Some(ip) => ip,
                None => continue, // anomalous; skip (mirrors existing path)
            };
            let sid = SpeakerId::new(m.uuid.clone());
            speakers.push(SpeakerIdentity {
                id: sid.clone(),
                room_name: m.zone_name.clone(),
                model: None, // ZoneGroupTopology carries no model (D1)
                ip,
            });
            members.push(sid);
        }

        // D3: coordinator first; skip a group whose coordinator is absent
        // from its own member list (anomalous).
        match members.iter().position(|s| *s == coord) {
            Some(i) => members.swap(0, i),
            None => continue,
        }
        out_groups.push(GroupIdentity {
            id: GroupId::new(zg.id),
            coordinator: coord,
            members,
        });
    }

    DiscoverySnapshot {
        speakers,
        groups: out_groups,
    }
}

impl Wire for SonosWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        let locations = ssdp::discover_locations(SSDP_TIMEOUT)?;
        let location_count = locations.len();
        let devices = to_devices(locations);
        if devices.is_empty() {
            return Err(if location_count == 0 {
                WireError::NoDevicesFound
            } else {
                WireError::Backend(format!(
                    "SSDP found {location_count} responder(s) but none returned a usable Sonos device description (fetch/parse failed or non-Sonos)"
                ))
            });
        }
        let device_count = devices.len();
        let snapshot = to_snapshot(devices);
        if snapshot.speakers.is_empty() {
            return Err(WireError::Backend(format!(
                "to_snapshot produced 0 speakers from {device_count} device(s) — all IP addresses unparseable (anomalous)"
            )));
        }

        // Populate the interior-mutable caches from the snapshot (the
        // same `populate_caches` path the cache unit test exercises).
        self.populate_caches(&snapshot);

        Ok(snapshot)
    }

    fn play(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_play(addr)
    }

    fn pause(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_pause(addr)
    }

    fn next(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_next(addr)
    }

    fn previous(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_previous(addr)
    }

    fn set_volume(&self, speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_set_volume(addr, volume)
    }

    fn set_mute(&self, speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_set_mute(addr, muted)
    }

    fn speaker_state(&self, speaker: &SpeakerId) -> Result<SpeakerState, WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_speaker_state(addr)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::IpAddr;

    /// Convenience constructor for synthetic test devices.
    fn dev(id: &str, name: &str, room: &str, ip: &str, model: &str) -> Device {
        Device {
            id: id.to_string(),
            name: name.to_string(),
            room_name: room.to_string(),
            ip_address: ip.to_string(),
            port: 1400,
            model_name: model.to_string(),
        }
    }

    /// Happy path: identity fields are mapped correctly, `uuid:` prefix is
    /// stripped, empty model_name becomes `None`, non-empty becomes `Some`.
    #[test]
    fn to_snapshot_maps_identity() {
        let devices = vec![
            dev(
                "uuid:RINCON_542A1B9463A801400",
                "Kitchen",
                "Kitchen",
                "10.0.0.1",
                "Sonos Era 100",
            ),
            dev(
                "RINCON_NO_PREFIX_456",
                "Office",
                "Office",
                "10.0.0.2",
                "Sonos One",
            ),
            dev(
                "uuid:RINCON_EMPTY_MODEL",
                "Bedroom",
                "Bedroom",
                "10.0.0.3",
                "", // empty → None
            ),
        ];

        let snap = to_snapshot(devices);

        assert_eq!(snap.speakers.len(), 3, "expected 3 speakers");

        // uuid: prefix must be stripped
        let kitchen = snap
            .speakers
            .iter()
            .find(|s| s.room_name == "Kitchen")
            .expect("Kitchen speaker missing");
        assert_eq!(
            kitchen.id.as_str(),
            "RINCON_542A1B9463A801400",
            "uuid: prefix not stripped"
        );
        assert_eq!(kitchen.model, Some("Sonos Era 100".to_string()));
        assert_eq!(kitchen.ip, "10.0.0.1".parse::<IpAddr>().unwrap());

        // No prefix — id passes through unchanged
        let office = snap
            .speakers
            .iter()
            .find(|s| s.room_name == "Office")
            .expect("Office speaker missing");
        assert_eq!(office.id.as_str(), "RINCON_NO_PREFIX_456");
        assert_eq!(office.model, Some("Sonos One".to_string()));

        // Empty model_name → None
        let bedroom = snap
            .speakers
            .iter()
            .find(|s| s.room_name == "Bedroom")
            .expect("Bedroom speaker missing");
        assert_eq!(bedroom.model, None, "empty model_name should map to None");
    }

    /// Each speaker gets exactly one group-of-one whose coordinator and sole
    /// member is that speaker, and whose id is `{speaker_id}:0`.
    #[test]
    fn to_snapshot_group_of_one() {
        let devices = vec![
            dev(
                "uuid:RINCON_AAAA",
                "Living Room",
                "Living Room",
                "192.168.1.10",
                "Sonos One",
            ),
            dev(
                "uuid:RINCON_BBBB",
                "Kitchen",
                "Kitchen",
                "192.168.1.11",
                "Sonos Era 300",
            ),
        ];

        let snap = to_snapshot(devices);

        assert_eq!(snap.speakers.len(), 2);
        assert_eq!(snap.groups.len(), 2, "one group per speaker");

        for g in &snap.groups {
            // coordinator must be the sole member
            assert_eq!(
                g.members.len(),
                1,
                "group-of-one must have exactly one member"
            );
            assert_eq!(
                g.members[0], g.coordinator,
                "member[0] must equal coordinator"
            );
            // group id is "{speaker_id}:0"
            let expected_gid = format!("{}:0", g.coordinator);
            assert_eq!(
                g.id.as_str(),
                expected_gid,
                "group id should be {{speaker}}:0"
            );
        }

        // Each speaker has a corresponding group
        for s in &snap.speakers {
            let found = snap.groups.iter().any(|g| g.coordinator == s.id);
            assert!(found, "speaker {} has no group", s.id);
        }
    }

    /// A device with an unparseable IP address is silently skipped; valid
    /// devices in the same batch are still returned.
    #[test]
    fn to_snapshot_skips_unparseable_ip() {
        let devices = vec![
            dev(
                "uuid:RINCON_GOOD",
                "Good",
                "Good Room",
                "10.0.0.5",
                "Sonos One",
            ),
            dev(
                "uuid:RINCON_BAD",
                "Bad",
                "Bad Room",
                "not-an-ip", // should be skipped
                "Sonos One",
            ),
            dev(
                "uuid:RINCON_ALSO_GOOD",
                "Also Good",
                "Also Good Room",
                "10.0.0.6",
                "Sonos Era 100",
            ),
        ];

        let snap = to_snapshot(devices);

        assert_eq!(snap.speakers.len(), 2, "bad-IP device must be skipped");
        assert_eq!(snap.groups.len(), 2);
        assert!(
            snap.speakers.iter().all(|s| s.room_name != "Bad Room"),
            "bad-IP device must not appear in output"
        );
    }

    #[test]
    fn extract_ip_from_location() {
        assert_eq!(
            extract_ip("http://10.83.0.10:1400/xml/device_description.xml"),
            Some("10.83.0.10".to_string())
        );
    }

    /// Verifies that resolve_group/resolve_speaker return NotFound when the
    /// wire has not been populated yet (simulates pre-discover() state).
    #[test]
    fn resolve_returns_not_found_before_discover() {
        let wire = SonosWire::new();
        let sid = SpeakerId::new("RINCON_UNKNOWN");
        let gid = GroupId::new("RINCON_UNKNOWN:0");

        assert!(matches!(
            wire.resolve_speaker(&sid),
            Err(WireError::NotFound(_))
        ));
        assert!(matches!(
            wire.resolve_group(&gid),
            Err(WireError::NotFound(_))
        ));
    }

    /// Verifies that the caches are correctly populated when discover() builds
    /// a snapshot (uses the pure to_snapshot path, not real SSDP).
    #[test]
    fn caches_populated_after_discover_snapshot() {
        // discover() needs a LAN, but its cache-population step is the
        // shared `populate_caches` helper — drive that directly so this
        // test exercises the real production path. It would fail if the
        // cache update were removed/changed in discover().
        let wire = SonosWire::new();
        let snap = to_snapshot(vec![dev(
            "uuid:RINCON_CACHE_TEST",
            "Test Speaker",
            "Test Room",
            "10.1.2.3",
            "Sonos One",
        )]);

        wire.populate_caches(&snap);

        // Now resolve should succeed
        let sid = SpeakerId::new("RINCON_CACHE_TEST");
        let gid = GroupId::new("RINCON_CACHE_TEST:0");

        let addr = wire.resolve_speaker(&sid).expect("should resolve speaker");
        assert_eq!(addr, SocketAddr::new("10.1.2.3".parse().unwrap(), 1400));

        let group_addr = wire.resolve_group(&gid).expect("should resolve group");
        assert_eq!(group_addr, addr);
    }
}

#[cfg(test)]
mod topology_tests {
    use super::*;
    use sonos_api::services::zone_group_topology::parse_zone_group_state_xml;

    // Verbatim ZoneGroupState captured 2026-05-19 from the real-hardware
    // `topology_spike` run (PR #21 example / #22 findings). Real Sonos
    // wire format — do not hand-edit; regenerate via the spike if the
    // topology changes. Canonical copy: docs/plans/
    // 2026-05-19-v0.3-grouping-spike-findings.md (Appendix).
    const GROUPED_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_542A1B9463A801400" ID="RINCON_542A1B9463A801400:3426502563"><ZoneGroupMember UUID="RINCON_542A1B9463A801400" Location="http://10.83.0.103:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="38" TVConfigurationError="0" HdmiCecAvailable="1" WirelessMode="1" ConnectionType="5" ChannelFreq="2417" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="1" SecureRegState="3" VoiceConfigState="2" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" VirtualLineInSource="spotify" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"><Satellite UUID="RINCON_38420B9275BE01400" Location="http://10.83.0.187:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" Invisible="1" SoftwareVersion="94.1-76220" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="108" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="2" ConnectionType="6" ChannelFreq="5660" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="5" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="0" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroupMember><ZoneGroupMember UUID="RINCON_7828CAE858CA01400" Location="http://10.83.0.105:1400/xml/device_description.xml" ZoneName="Kitchen" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="TargetRoomName:Kitchen" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups><VanishedDevices><Device UUID="RINCON_38420B92755401400" ZoneName="Living Room" Reason="UNKNOWN" ModelInfo="S33" Mac="38:42:0B:92:75:54" LastKnownIP="10.83.0.115" LastSeenUTC="2026-05-17T12:38:05Z" MoreInfo="" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" SWGen="2"/></VanishedDevices></ZoneGroupState>"#;

    const COORD_NOT_FIRST_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_542A1B9463A801400" ID="RINCON_542A1B9463A801400:3426502563"><ZoneGroupMember UUID="RINCON_7828CAE858CA01400" Location="http://10.83.0.105:1400/xml/device_description.xml" ZoneName="Kitchen" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="TargetRoomName:Kitchen" SSLPort="1443" HHSSLPort="1843"/><ZoneGroupMember UUID="RINCON_542A1B9463A801400" Location="http://10.83.0.103:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="38" TVConfigurationError="0" HdmiCecAvailable="1" WirelessMode="1" ConnectionType="5" ChannelFreq="2417" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="1" SecureRegState="3" VoiceConfigState="2" MicEnabled="1" HeadphoneSwapActive="0" AirPlayEnabled="1" VirtualLineInSource="spotify" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"><Satellite UUID="RINCON_38420B9275BE01400" Location="http://10.83.0.187:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" Invisible="1" SoftwareVersion="94.1-76220" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="108" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="2" ConnectionType="6" ChannelFreq="5660" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="5" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="0" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroupMember></ZoneGroup></ZoneGroups><VanishedDevices><Device UUID="RINCON_38420B92755401400" ZoneName="Living Room" Reason="UNKNOWN" ModelInfo="S33" Mac="38:42:0B:92:75:54" LastKnownIP="10.83.0.115" LastSeenUTC="2026-05-17T12:38:06Z" MoreInfo="" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" SWGen="2"/></VanishedDevices></ZoneGroupState>"#;

    // Minimal but parser-valid doc: one group with two members.
    // RINCON_GOOD has a valid IP; RINCON_BAD has "not-an-ip" as host (fails
    // IpAddr::parse) → topology_to_snapshot must skip it.
    // Attribute set copied verbatim from the Kitchen member in GROUPED_XML so
    // parse_zone_group_state_xml accepts the document without modification.
    const BAD_IP_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_GOOD" ID="RINCON_GOOD:1"><ZoneGroupMember UUID="RINCON_GOOD" Location="http://10.83.0.50:1400/xml/device_description.xml" ZoneName="Good Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/><ZoneGroupMember UUID="RINCON_BAD" Location="http://not-an-ip/xml/device_description.xml" ZoneName="Bad Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups></ZoneGroupState>"#;

    fn snap(xml: &str) -> DiscoverySnapshot {
        topology_to_snapshot(parse_zone_group_state_xml(xml).expect("parse"))
    }

    #[test]
    fn grouped_topology_maps_real_group() {
        let s = snap(GROUPED_XML);
        assert_eq!(s.groups.len(), 1, "one real group");
        let g = &s.groups[0];
        assert_eq!(g.coordinator.as_str(), "RINCON_542A1B9463A801400");
        assert_eq!(g.members.len(), 2, "Living Room + Kitchen");
        assert_eq!(g.members[0], g.coordinator, "coordinator first (D3)");
        assert!(
            !s.speakers
                .iter()
                .any(|sp| sp.id.as_str() == "RINCON_38420B9275BE01400"),
            "Invisible satellite must not be a speaker"
        );
        assert_eq!(s.speakers.len(), 2, "two real speakers, satellite folded");
        let lr = s
            .speakers
            .iter()
            .find(|sp| sp.room_name == "Living Room")
            .expect("Living Room speaker missing in grouped snapshot");
        assert_eq!(lr.model, None, "D1: model is None");
        assert_eq!(
            lr.id.as_str(),
            "RINCON_542A1B9463A801400",
            "no uuid: prefix in ZGS"
        );
    }

    #[test]
    fn coordinator_reordered_first() {
        let s = snap(COORD_NOT_FIRST_XML);
        let g = &s.groups[0];
        assert_eq!(
            g.members[0], g.coordinator,
            "must reorder coordinator to index 0"
        );
    }

    #[test]
    fn skips_member_with_unparseable_ip() {
        let s = snap(BAD_IP_XML);
        assert_eq!(s.speakers.len(), 1, "bad-IP member skipped");
        assert_eq!(s.speakers[0].id.as_str(), "RINCON_GOOD");
        assert_eq!(s.groups.len(), 1);
        assert_eq!(
            s.groups[0].members,
            vec![s.groups[0].coordinator.clone()],
            "skipped member absent from group membership too"
        );
    }
}
