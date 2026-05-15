//! Production `Wire`: own SSDP + sonos-sdk (test-support) adapter.

use std::time::Duration;

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity, Wire, WireError,
};
use sonos_sdk::sonos_discovery::{device::DeviceDescription, Device};
use sonos_sdk::SonosSystem;

use crate::{http, ssdp};

const SSDP_TIMEOUT: Duration = Duration::from_secs(3);
const HTTP_TIMEOUT: Duration = Duration::from_secs(2);

pub struct SonosWire;

impl SonosWire {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SonosWire {
    fn default() -> Self {
        Self::new()
    }
}

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

fn map_snapshot(system: &SonosSystem) -> DiscoverySnapshot {
    let speakers = system
        .speakers()
        .into_iter()
        .map(|s| SpeakerIdentity {
            id: SpeakerId::new(s.id.to_string()),
            room_name: s.name,
            model: if s.model_name.is_empty() {
                None
            } else {
                Some(s.model_name)
            },
            ip: s.ip,
        })
        .collect();
    let groups = system
        .groups()
        .into_iter()
        .map(|g| {
            // coordinator_id and member_ids are pub fields on Group; prefer
            // them over coordinator()/members() which return Option<Speaker>/Vec<Speaker>
            // resolved from state and could be None if state is inconsistent.
            let coord = SpeakerId::new(g.coordinator_id.to_string());
            // member_ids includes the coordinator; preserve that ordering with
            // coordinator guaranteed at index 0.
            let mut members: Vec<SpeakerId> = Vec::with_capacity(g.member_ids.len());
            members.push(coord.clone());
            for mid in &g.member_ids {
                let id = SpeakerId::new(mid.to_string());
                if id != coord {
                    members.push(id);
                }
            }
            GroupIdentity {
                id: GroupId::new(g.id.to_string()),
                coordinator: coord,
                members,
            }
        })
        .collect();
    DiscoverySnapshot { speakers, groups }
}

impl Wire for SonosWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        let locations = ssdp::discover_locations(SSDP_TIMEOUT)?;
        let devices = to_devices(locations);
        if devices.is_empty() {
            return Err(WireError::NoDevicesFound);
        }
        let system = SonosSystem::from_discovered_devices(devices)
            .map_err(|e| WireError::Backend(format!("{e:?}")))?;
        Ok(map_snapshot(&system))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev(id: &str, room: &str, ip: &str, model: &str) -> Device {
        Device {
            id: id.into(),
            name: room.into(),
            room_name: room.into(),
            ip_address: ip.into(),
            port: 1400,
            model_name: model.into(),
        }
    }

    /// Speaker identity mapping — uses `from_discovered_devices` (no network).
    /// Groups are NOT tested here because `system.groups()` calls
    /// `ensure_topology()` which issues SOAP over the network; see
    /// `maps_groups_coordinator_first` below, which uses `with_groups`.
    #[test]
    fn maps_speakers_without_network() {
        let system = SonosSystem::from_discovered_devices(vec![
            dev("RINCON_A", "Kitchen", "10.83.0.10", "Sonos One"),
            dev("RINCON_B", "Office", "10.83.0.11", ""),
        ])
        .expect("from_discovered_devices");
        let snap = map_snapshot(&system);
        assert_eq!(snap.speakers.len(), 2);
        let office = snap
            .speakers
            .iter()
            .find(|s| s.room_name == "Office")
            .unwrap();
        // Empty model_name on the Device → None on SpeakerIdentity
        assert_eq!(office.model, None);
        let kitchen = snap
            .speakers
            .iter()
            .find(|s| s.room_name == "Kitchen")
            .unwrap();
        assert_eq!(kitchen.model, Some("Sonos One".to_string()));
    }

    /// Group mapping — uses `SonosSystem::with_groups` (test-support, no network).
    /// `with_groups` pre-initialises topology so `system.groups()` never
    /// calls `ensure_topology()` over the LAN.
    #[test]
    fn maps_groups_coordinator_first() {
        // with_groups creates 2 standalone speakers (each its own coordinator).
        let system = SonosSystem::with_groups(&["Kitchen", "Office"]);
        let snap = map_snapshot(&system);
        assert_eq!(snap.speakers.len(), 2);
        assert_eq!(snap.groups.len(), 2);
        for g in &snap.groups {
            // coordinator must be at index 0 (GroupIdentity invariant)
            assert_eq!(g.members[0], g.coordinator);
            // standalone group: only the coordinator is a member
            assert_eq!(g.members.len(), 1);
        }
    }

    #[test]
    fn extract_ip_from_location() {
        assert_eq!(
            extract_ip("http://10.83.0.10:1400/xml/device_description.xml"),
            Some("10.83.0.10".to_string())
        );
    }
}
