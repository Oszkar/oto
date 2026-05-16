//! Production `Wire`: own SSDP + sonos-sdk (test-support) adapter.

use std::net::IpAddr;
use std::time::Duration;

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity, Wire, WireError,
};
use sonos_sdk::sonos_discovery::{device::DeviceDescription, Device};

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

/// Strip host:port → bare IP.
/// `DeviceDescription::to_device` takes a bare IP string (not `host:port`),
/// unlike `http::get_body` which keeps `host:port` for `TcpStream::connect`.
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

        // v0.1 group-of-one; real topology/bonded modeling deferred to v0.3
        // (ARCHITECTURE open-Q1/Q4) — bonded surrounds appear as standalone
        // here by design.
        groups.push(GroupIdentity {
            id: GroupId::new(format!("{sid}:0")),
            coordinator: sid.clone(),
            members: vec![sid],
        });
    }

    DiscoverySnapshot { speakers, groups }
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
        let snapshot = to_snapshot(devices);
        if snapshot.speakers.is_empty() {
            return Err(WireError::Backend(format!(
                "to_snapshot produced 0 speakers from {location_count} device(s) — all IP addresses unparseable (anomalous)"
            )));
        }
        Ok(snapshot)
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
    ///
    /// This test was written BEFORE `to_snapshot` existed in the codebase —
    /// it failed to compile against the old adapter (which only had
    /// `map_snapshot(&SonosSystem)`).  That non-compilation is the
    /// failing-test-first state required by the systematic-debugging protocol.
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
}
