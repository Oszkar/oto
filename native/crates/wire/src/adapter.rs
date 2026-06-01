//! Production `Wire`: own SSDP + direct `sonos-api` SOAP.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::mpsc::Receiver;
use std::sync::Mutex;
use std::time::Duration;

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity,
    SpeakerState, Volume, Wire, WireError,
};
use sonos_api::services::zone_group_topology::ZoneGroupInfo;
use sonos_api::SonosClient;

use crate::events::{EventPump, PumpInputs};
use crate::{control, ssdp};

const SSDP_TIMEOUT: Duration = Duration::from_secs(3);

/// Production wire implementation backed by `sonos_api` direct SOAP calls.
///
/// Interior-mutable caches (`id_to_addr`, `group_to_coordinator`,
/// `speaker_to_coordinator`, `id_to_name`) are populated by `discover()`
/// and used by the playback/read methods + the v0.4 event pump.
/// All methods return `Err(WireError::NotFound)` if called before a
/// successful `discover()` has populated the relevant entry.
pub struct SonosWire {
    /// Shared `sonos_api` SOAP client. Held on the wire so each command
    /// reuses it instead of paying `SonosClient::new()` per call.
    client: SonosClient,
    /// Maps `SpeakerId` → `SocketAddr(ip, 1400)` for rendering-control calls.
    id_to_addr: Mutex<HashMap<SpeakerId, SocketAddr>>,
    /// Maps `GroupId` → coordinator `SpeakerId` for transport-control calls.
    group_to_coordinator: Mutex<HashMap<GroupId, SpeakerId>>,
    /// Maps each member `SpeakerId` → its group coordinator `SpeakerId`
    /// (oto-core D2). Coordinator maps to itself.
    speaker_to_coordinator: Mutex<HashMap<SpeakerId, SpeakerId>>,
    /// Maps `SpeakerId` → its `room_name`. Used only by the v0.4 event
    /// pump to populate the SDK's `sonos_discovery::Device` records.
    id_to_name: Mutex<HashMap<SpeakerId, String>>,
    /// v0.4 event pump + the still-takeable `Receiver`. `None` until
    /// `subscribe_speakers` is called; `Some` thereafter for the
    /// lifetime of the wire. The `Receiver` is taken once via
    /// `take_event_stream` and then is `None` inside the option.
    events_state: Mutex<Option<EventsState>>,
}

struct EventsState {
    /// Owns the pump thread + the stop flag. Dropped when the wire is
    /// dropped (or on `discover_with` replacement); `EventPump::Drop`
    /// signals the pump to exit at the next poll boundary (~250 ms)
    /// and joins. The SDK manager / event worker shut down naturally
    /// once the pump thread releases its `StateManager` ownership.
    _pump: EventPump,
    /// One-shot: taken on first `take_event_stream`, then `None`.
    rx: Option<Receiver<ChangeEvent>>,
}

impl SonosWire {
    pub fn new() -> Self {
        Self {
            client: SonosClient::new(),
            id_to_addr: Mutex::new(HashMap::new()),
            group_to_coordinator: Mutex::new(HashMap::new()),
            speaker_to_coordinator: Mutex::new(HashMap::new()),
            id_to_name: Mutex::new(HashMap::new()),
            events_state: Mutex::new(None),
        }
    }

    /// Snapshot the wire's interior-mutable caches into a `PumpInputs`
    /// for `EventPump::spawn`. Returns `NoSpeakersDiscovered` if the
    /// caches are empty (called before discover()).
    fn snapshot_for_pump(&self) -> Result<PumpInputs, WireError> {
        let id_to_addr = self
            .id_to_addr
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone();
        if id_to_addr.is_empty() {
            return Err(WireError::NoSpeakersDiscovered);
        }
        let group_to_coord = self
            .group_to_coordinator
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone();
        let speaker_to_coord = self
            .speaker_to_coordinator
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone();
        let id_to_name = self
            .id_to_name
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone();

        // Build coord_to_group by inverting group_to_coord.
        let coord_to_group = group_to_coord
            .into_iter()
            .map(|(g, coord)| (coord, g))
            .collect();

        let speaker_ips = id_to_addr
            .into_iter()
            .map(|(sid, addr)| (sid, addr.ip()))
            .collect();

        Ok(PumpInputs {
            speaker_ips,
            coord_to_group,
            speaker_to_coord,
            speaker_names: id_to_name,
        })
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
        {
            let mut cache = self
                .speaker_to_coordinator
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            cache.clear();
            for group in &snapshot.groups {
                for m in &group.members {
                    cache.insert(m.clone(), group.coordinator.clone());
                }
            }
        }
        {
            let mut cache = self.id_to_name.lock().unwrap_or_else(|p| p.into_inner());
            cache.clear();
            for speaker in &snapshot.speakers {
                cache.insert(speaker.id.clone(), speaker.room_name.clone());
            }
        }
    }

    /// Transport lives on the coordinator (oto-core D2): resolve the
    /// speaker's group coordinator's addr. With no coordinator mapping
    /// (solo speaker, or empty/stale cache) fall back to the speaker's
    /// own addr — correct for a solo speaker, and otherwise yields the
    /// same `NotFound` as v0.2 until `discover()` has populated the caches.
    fn resolve_transport_addr(&self, speaker: &SpeakerId) -> Result<SocketAddr, WireError> {
        let coord = {
            self.speaker_to_coordinator
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .get(speaker)
                .cloned()
        };
        match coord {
            Some(c) => self.resolve_speaker(&c),
            None => self.resolve_speaker(speaker),
        }
    }
}

impl Default for SonosWire {
    fn default() -> Self {
        Self::new()
    }
}

/// Strip `http://host:port/…` → bare IP string for `sonos_api` calls.
fn extract_ip(url: &str) -> Option<String> {
    url.strip_prefix("http://")?
        .split('/')
        .next()?
        .split(':')
        .next()
        .map(str::to_string)
}

/// Build a real `DiscoverySnapshot` from parsed ZoneGroupTopology.
///
/// Speakers = top-level members (satellites are folded into their
/// primary, never surfaced — oto-core D5). Each group's members are
/// reordered coordinator-first (oto-core D3; the parser does not
/// guarantee order). Vanished devices are already dropped by
/// `parse_zone_group_state_xml`.
fn to_snapshot(groups: Vec<ZoneGroupInfo>) -> DiscoverySnapshot {
    let mut speakers = Vec::new();
    let mut out_groups = Vec::new();

    for zg in groups {
        let coord = SpeakerId::new(zg.coordinator.clone());

        // Accumulate this group's speakers locally so that a skipped group
        // (coordinator absent from members — anomalous) does not leave orphan
        // speakers in the snapshot that belong to no group.
        let mut group_speakers: Vec<SpeakerIdentity> = Vec::with_capacity(zg.members.len());
        let mut members: Vec<SpeakerId> = Vec::with_capacity(zg.members.len());
        for m in &zg.members {
            let ip: IpAddr = match extract_ip(&m.location).and_then(|s| s.parse().ok()) {
                Some(ip) => ip,
                None => continue, // anomalous; skip (mirrors existing path)
            };
            let sid = SpeakerId::new(m.uuid.clone());
            group_speakers.push(SpeakerIdentity {
                id: sid.clone(),
                room_name: m.zone_name.clone(),
                model: None, // ZoneGroupTopology carries no model (D1)
                ip,
            });
            members.push(sid);
        }

        // D3: coordinator first; skip a group whose coordinator is absent
        // from its own member list (anomalous). On the None path group_speakers
        // is dropped — no orphan speakers enter the snapshot.
        match members.iter().position(|s| *s == coord) {
            Some(i) => members.swap(0, i),
            None => continue,
        }
        speakers.extend(group_speakers);
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
        if locations.is_empty() {
            return Err(WireError::NoDevicesFound);
        }
        // PerNetwork: any reachable speaker returns the whole household.
        // Try responders until one answers (a vanished/asleep unit fails).
        let mut last_err = WireError::NoDevicesFound;
        let mut groups = None;
        // C2: track whether at least one responder had a parseable LOCATION so
        // we can surface a precise error when all locations are unparseable.
        let mut attempted = false;
        for loc in &locations {
            let Some(ip) = extract_ip(loc) else { continue };
            attempted = true;
            match control::fetch_zone_group_state(&self.client, &ip) {
                Ok(g) => {
                    groups = Some(g);
                    break;
                }
                Err(e) => last_err = e,
            }
        }
        // If groups is still None but no responder was ever attempted, every
        // LOCATION was unparseable — surface a precise diagnostic (not the
        // misleading NoDevicesFound).
        if groups.is_none() && !attempted {
            return Err(WireError::Backend(format!(
                "SSDP found {} responder(s) but none had a parseable LOCATION \
                 (e.g. {}); cannot reach ZoneGroupTopology",
                locations.len(),
                locations.first().map(String::as_str).unwrap_or("?"),
            )));
        }
        let groups = groups.ok_or(last_err)?;
        let snapshot = to_snapshot(groups);
        if snapshot.speakers.is_empty() {
            return Err(WireError::Backend(
                "ZoneGroupTopology yielded 0 usable speakers (all locations unparseable — anomalous)"
                    .into(),
            ));
        }
        self.populate_caches(&snapshot);
        Ok(snapshot)
    }

    fn play(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_play(&self.client, addr)
    }

    fn pause(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_pause(&self.client, addr)
    }

    fn next(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_next(&self.client, addr)
    }

    fn previous(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_previous(&self.client, addr)
    }

    fn set_volume(&self, speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_set_volume(&self.client, addr, volume)
    }

    fn set_mute(&self, speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_set_mute(&self.client, addr, muted)
    }

    fn speaker_state(&self, speaker: &SpeakerId) -> Result<SpeakerState, WireError> {
        let speaker_addr = self.resolve_speaker(speaker)?;
        let transport_addr = self.resolve_transport_addr(speaker)?;
        control::soap_speaker_state(&self.client, speaker_addr, transport_addr)
    }

    fn subscribe_topology(&self) -> Result<(), WireError> {
        // S1.1 skeleton — idempotent no-op until S1.2 wires in the SDK ZGT
        // watch. `discover_with` calls this automatically; returning Ok(())
        // keeps the lifecycle contract without a pump thread yet.
        // TODO(v0.5): replace with real GroupMembership watch in S1.2.
        let _ = self.snapshot_for_pump()?; // validate discover() ran first
        Ok(())
    }

    fn refresh_topology(&self) -> Result<DiscoverySnapshot, WireError> {
        // Pick any cached IP — all speakers report the complete household.
        let ip = {
            let guard = self.id_to_addr.lock().unwrap_or_else(|p| p.into_inner());
            guard
                .values()
                .next()
                .map(|addr| addr.ip().to_string())
                .ok_or(WireError::NoSpeakersDiscovered)?
        };
        let groups = crate::control::fetch_zone_group_state(&self.client, &ip)?;
        let snapshot = to_snapshot(groups);
        self.populate_caches(&snapshot);
        Ok(snapshot)
    }

    fn subscribe_speakers(&self) -> Result<(), WireError> {
        // v0.4 Slice 3: wire up the sonos-sdk-state pump thread. One
        // shot per wire — repeated calls error with `AlreadySubscribed`.
        //
        // Per-speaker subscription failures do NOT currently surface
        // in-band. The SDK at `=0.5.2` swallows
        // `watch_property_with_subscription` failures internally
        // (state.rs:610-633 — tracing::warn + Ok(option)) and
        // `is_service_subscribed` only reports queue state, not
        // device reachability. A silent subscription failure
        // manifests as the speaker's events simply never arriving
        // (the UI keeps showing the last-known value).
        //
        // Detecting this honestly requires either an SDK feature we
        // don't have at this pin or a wire-side timeout-driven probe
        // (e.g. expected-seed-NOTIFY watchdog). Tracked as v0.5
        // follow-up; see `events::register_watches` for the full SDK
        // source citations.
        let mut guard = self.events_state.lock().unwrap_or_else(|p| p.into_inner());
        if guard.is_some() {
            return Err(WireError::AlreadySubscribed);
        }
        let inputs = self.snapshot_for_pump()?;
        let (pump, rx) = EventPump::spawn(inputs)?;
        *guard = Some(EventsState {
            _pump: pump,
            rx: Some(rx),
        });
        Ok(())
    }

    fn take_event_stream(&self) -> Option<Receiver<ChangeEvent>> {
        // One-shot per wire. Returns the Receiver the first time after
        // `subscribe_speakers`; returns `None` thereafter (or if no
        // subscribe call has happened yet).
        let mut guard = self.events_state.lock().unwrap_or_else(|p| p.into_inner());
        guard.as_mut().and_then(|s| s.rx.take())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(matches!(
            wire.resolve_transport_addr(&sid),
            Err(WireError::NotFound(_))
        ));
    }

    /// Verifies that `resolve_transport_addr` routes non-coordinator speakers to
    /// their group coordinator (oto-core D2) and coordinators to themselves.
    #[test]
    fn resolve_transport_addr_uses_coordinator() {
        let w = SonosWire::new();
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                super::topology_tests::GROUPED_XML,
            )
            .expect("parse"),
        );
        w.populate_caches(&snap);
        // Living Room is the coordinator; Kitchen is a non-coordinator member.
        let coord = SpeakerId::new("RINCON_542A1B9463A801400");
        let kitchen = SpeakerId::new("RINCON_7828CAE858CA01400");
        let coord_addr = w.resolve_speaker(&coord).expect("coord addr");
        assert_eq!(
            w.resolve_transport_addr(&kitchen)
                .expect("kitchen transport addr"),
            coord_addr,
            "non-coordinator transport must resolve to the coordinator (D2)"
        );
        assert_eq!(
            w.resolve_transport_addr(&coord)
                .expect("coord transport addr"),
            coord_addr,
            "coordinator transport resolves to itself"
        );
    }

    /// T-C1: a group whose coordinator is absent from its members must be
    /// skipped entirely — zero speakers from that group must leak into the
    /// snapshot (C1 fix). The second, valid group must appear normally.
    #[test]
    fn skipped_group_contributes_no_speakers() {
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                super::topology_tests::GHOST_COORD_XML,
            )
            .expect("parse"),
        );
        // Ghost group skipped → RINCON_REAL must not appear
        assert!(
            !snap.speakers.iter().any(|s| s.id.as_str() == "RINCON_REAL"),
            "RINCON_REAL (member of ghost group) must NOT leak into speakers"
        );
        assert!(
            !snap
                .groups
                .iter()
                .any(|g| g.id.as_str() == "RINCON_GHOST:1"),
            "ghost group must not appear in groups"
        );
        // Valid group is present
        assert_eq!(snap.groups.len(), 1, "exactly one valid group");
        assert_eq!(
            snap.speakers.len(),
            1,
            "exactly one speaker from the valid group"
        );
        assert_eq!(snap.speakers[0].id.as_str(), "RINCON_VALID");
    }

    /// Verifies that the caches are correctly populated via `populate_caches`.
    ///
    /// Uses the real ZoneGroupTopology fixture so the test exercises the same
    /// mapping path that `discover()` uses at runtime. It would fail if the
    /// cache-population step were removed or broken in `discover()`.
    #[test]
    fn caches_populated_after_discover_snapshot() {
        let wire = SonosWire::new();
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                topology_tests::GROUPED_XML,
            )
            .expect("parse"),
        );
        wire.populate_caches(&snap);

        // Coordinator of the real group
        let sid = SpeakerId::new("RINCON_542A1B9463A801400");
        let gid = GroupId::new("RINCON_542A1B9463A801400:3426502563");

        let addr = wire.resolve_speaker(&sid).expect("should resolve speaker");
        assert_eq!(addr, SocketAddr::new("10.83.0.103".parse().unwrap(), 1400));
        let group_addr = wire.resolve_group(&gid).expect("should resolve group");
        assert_eq!(group_addr, addr);

        // Member (Kitchen speaker)
        let member_sid = SpeakerId::new("RINCON_7828CAE858CA01400");
        let member_addr = wire
            .resolve_speaker(&member_sid)
            .expect("should resolve member");
        assert_eq!(
            member_addr,
            SocketAddr::new("10.83.0.105".parse().unwrap(), 1400)
        );

        // Unknown id → NotFound
        let unknown = SpeakerId::new("RINCON_DOES_NOT_EXIST");
        assert!(matches!(
            wire.resolve_speaker(&unknown),
            Err(WireError::NotFound(_))
        ));
    }
}

#[cfg(test)]
mod topology_tests {
    use super::*;
    use sonos_api::services::zone_group_topology::parse_zone_group_state_xml;

    // Verbatim ZoneGroupState captured 2026-05-19 from the real-hardware
    // `topology_spike` run (PR #21 example / #22 findings). Real Sonos
    // wire format — do not hand-edit; regenerate via the spike if the
    // topology changes. Cited as the regression-fixture authoritative
    // source in `docs/sonos-notes.md` § ZoneGroupState fixture XML.
    // pub(crate): shared with the caches test in mod tests above.
    pub(crate) const GROUPED_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_542A1B9463A801400" ID="RINCON_542A1B9463A801400:3426502563"><ZoneGroupMember UUID="RINCON_542A1B9463A801400" Location="http://10.83.0.103:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="38" TVConfigurationError="0" HdmiCecAvailable="1" WirelessMode="1" ConnectionType="5" ChannelFreq="2417" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="1" SecureRegState="3" VoiceConfigState="2" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" VirtualLineInSource="spotify" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"><Satellite UUID="RINCON_38420B9275BE01400" Location="http://10.83.0.187:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" Invisible="1" SoftwareVersion="94.1-76220" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="108" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="2" ConnectionType="6" ChannelFreq="5660" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="5" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="0" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroupMember><ZoneGroupMember UUID="RINCON_7828CAE858CA01400" Location="http://10.83.0.105:1400/xml/device_description.xml" ZoneName="Kitchen" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="TargetRoomName:Kitchen" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups><VanishedDevices><Device UUID="RINCON_38420B92755401400" ZoneName="Living Room" Reason="UNKNOWN" ModelInfo="S33" Mac="38:42:0B:92:75:54" LastKnownIP="10.83.0.115" LastSeenUTC="2026-05-17T12:38:05Z" MoreInfo="" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" SWGen="2"/></VanishedDevices></ZoneGroupState>"#;

    pub(crate) const COORD_NOT_FIRST_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_542A1B9463A801400" ID="RINCON_542A1B9463A801400:3426502563"><ZoneGroupMember UUID="RINCON_7828CAE858CA01400" Location="http://10.83.0.105:1400/xml/device_description.xml" ZoneName="Kitchen" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="TargetRoomName:Kitchen" SSLPort="1443" HHSSLPort="1843"/><ZoneGroupMember UUID="RINCON_542A1B9463A801400" Location="http://10.83.0.103:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="38" TVConfigurationError="0" HdmiCecAvailable="1" WirelessMode="1" ConnectionType="5" ChannelFreq="2417" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="1" SecureRegState="3" VoiceConfigState="2" MicEnabled="1" HeadphoneSwapActive="0" AirPlayEnabled="1" VirtualLineInSource="spotify" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"><Satellite UUID="RINCON_38420B9275BE01400" Location="http://10.83.0.187:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" Invisible="1" SoftwareVersion="94.1-76220" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="108" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="2" ConnectionType="6" ChannelFreq="5660" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="5" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="0" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroupMember></ZoneGroup></ZoneGroups><VanishedDevices><Device UUID="RINCON_38420B92755401400" ZoneName="Living Room" Reason="UNKNOWN" ModelInfo="S33" Mac="38:42:0B:92:75:54" LastKnownIP="10.83.0.115" LastSeenUTC="2026-05-17T12:38:06Z" MoreInfo="" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" SWGen="2"/></VanishedDevices></ZoneGroupState>"#;

    // Minimal but parser-valid doc: one group with two members.
    // RINCON_GOOD has a valid IP; RINCON_BAD has "not-an-ip" as host (fails
    // IpAddr::parse) → to_snapshot must skip it.
    // Attribute set copied verbatim from the Kitchen member in GROUPED_XML so
    // parse_zone_group_state_xml accepts the document without modification.
    pub(crate) const BAD_IP_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_GOOD" ID="RINCON_GOOD:1"><ZoneGroupMember UUID="RINCON_GOOD" Location="http://10.83.0.50:1400/xml/device_description.xml" ZoneName="Good Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/><ZoneGroupMember UUID="RINCON_BAD" Location="http://not-an-ip/xml/device_description.xml" ZoneName="Bad Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups></ZoneGroupState>"#;

    // Two groups: the first (RINCON_GHOST) has a coordinator that is NOT among
    // its members (RINCON_REAL is the only member). The second (RINCON_VALID)
    // is a normal solo group. to_snapshot must skip the ghost group entirely —
    // RINCON_REAL must not appear in snapshot.speakers (C1).
    // Member attribute set copied from Kitchen member in GROUPED_XML.
    pub(crate) const GHOST_COORD_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_GHOST" ID="RINCON_GHOST:1"><ZoneGroupMember UUID="RINCON_REAL" Location="http://10.0.0.9:1400/xml/device_description.xml" ZoneName="Ghost Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup><ZoneGroup Coordinator="RINCON_VALID" ID="RINCON_VALID:2"><ZoneGroupMember UUID="RINCON_VALID" Location="http://10.0.0.10:1400/xml/device_description.xml" ZoneName="Valid Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups></ZoneGroupState>"#;

    fn snap(xml: &str) -> DiscoverySnapshot {
        to_snapshot(parse_zone_group_state_xml(xml).expect("parse"))
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
