//! Identity-only projections used by v0.1 discovery. `Speaker`/`Group`
//! carry volume/transport that are unpopulated post-discovery (spike
//! finding); these lean types keep "identity-only" true at every layer.
//! v0.2 grows `Speaker` *around* `SpeakerIdentity`.

use std::net::IpAddr;

use crate::identifiers::{GroupId, SpeakerId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpeakerIdentity {
    pub id: SpeakerId,
    pub room_name: String,
    pub model: Option<String>,
    pub ip: IpAddr,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroupIdentity {
    pub id: GroupId,
    pub coordinator: SpeakerId,
    /// Coordinator at index 0 (matches Sonos ZoneGroupTopology ordering).
    pub members: Vec<SpeakerId>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoverySnapshot {
    pub speakers: Vec<SpeakerIdentity>,
    pub groups: Vec<GroupIdentity>,
}

#[cfg(test)]
mod tests {
    use std::net::{IpAddr, Ipv4Addr};

    use super::*;

    #[test]
    fn snapshot_holds_identities() {
        let kid = SpeakerId::new("RINCON_K");
        let snap = DiscoverySnapshot {
            speakers: vec![SpeakerIdentity {
                id: kid.clone(),
                room_name: "Kitchen".into(),
                model: Some("Sonos One".into()),
                ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 10)),
            }],
            groups: vec![GroupIdentity {
                id: GroupId::new("RINCON_K:0"),
                coordinator: kid.clone(),
                members: vec![kid],
            }],
        };
        assert_eq!(snap.speakers.len(), 1);
        assert_eq!(snap.groups[0].members[0], snap.groups[0].coordinator);
    }
}
