#![deny(unsafe_code)]

//! Deterministic in-memory `Wire` for tests — no network. Integration
//! tests drive these fixtures so v0.1 discovery is provable without a LAN.

use std::net::{IpAddr, Ipv4Addr};

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity, Wire, WireError,
};

/// A `Wire` that yields a fixed topology, or a fixed error.
pub struct MockWire {
    outcome: Result<DiscoverySnapshot, WireError>,
}

impl MockWire {
    /// A `Wire` that fails with `err`.
    pub fn failing(err: WireError) -> Self {
        Self { outcome: Err(err) }
    }

    fn fixture() -> DiscoverySnapshot {
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let dining = SpeakerId::new("RINCON_DINING");
        let office = SpeakerId::new("RINCON_OFFICE");
        DiscoverySnapshot {
            speakers: vec![
                SpeakerIdentity {
                    id: kitchen.clone(),
                    room_name: "Kitchen".into(),
                    model: Some("Sonos One".into()),
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 10)),
                },
                SpeakerIdentity {
                    id: dining.clone(),
                    room_name: "Dining".into(),
                    model: Some("Sonos One".into()),
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 11)),
                },
                SpeakerIdentity {
                    id: office.clone(),
                    room_name: "Office".into(),
                    model: None,
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 12)),
                },
            ],
            groups: vec![
                GroupIdentity {
                    id: GroupId::new("RINCON_KITCHEN:1"),
                    coordinator: kitchen.clone(),
                    members: vec![kitchen, dining],
                },
                GroupIdentity {
                    id: GroupId::new("RINCON_OFFICE:0"),
                    coordinator: office.clone(),
                    members: vec![office],
                },
            ],
        }
    }
}

impl Default for MockWire {
    fn default() -> Self {
        Self {
            outcome: Ok(Self::fixture()),
        }
    }
}

impl Wire for MockWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        self.outcome.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_returns_fixture() {
        let snap = MockWire::default().discover().unwrap();
        assert_eq!(snap.speakers.len(), 3);
        assert_eq!(snap.groups.len(), 2);
        // Anchor specific fixture values so downstream integration tests
        // (and this fixture) fail loudly if the data is silently edited.
        assert_eq!(snap.speakers[0].room_name, "Kitchen");
        assert_eq!(snap.speakers[2].model, None);
        assert_eq!(snap.groups[0].id.as_str(), "RINCON_KITCHEN:1");
        assert_eq!(snap.groups[0].members.len(), 2);
        assert_eq!(snap.groups[0].members[0], snap.groups[0].coordinator);
        assert_eq!(snap.groups[1].members.len(), 1);
    }

    #[test]
    fn failing_returns_error() {
        let err = MockWire::failing(WireError::NoDevicesFound).discover();
        assert_eq!(err, Err(WireError::NoDevicesFound));
    }
}
