//! A Sonos zone group - the unit of playback.
//!
//! A group is one or more speakers playing the same audio in sync. Solo
//! speakers form a group of one. Transport state lives here (not on
//! [`crate::Speaker`]) because Sonos's `AVTransport` events fire per-
//! coordinator and updating a single `transport` field avoids the member-
//! sync bug class. See the design doc (D2) for the full rationale and the
//! "transport on Speaker" alternative we may revisit.

use crate::{
    identifiers::{GroupId, SpeakerId},
    transport::TransportState,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Group {
    pub id: GroupId,
    pub coordinator: SpeakerId,
    /// All speakers in the group, with the coordinator at index 0 - matches
    /// Sonos's `ZoneGroupTopology` event ordering.
    pub members: Vec<SpeakerId>,
    pub transport: TransportState,
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::Group;
    use crate::{
        identifiers::{GroupId, SpeakerId, TrackId},
        track::Track,
        transport::{PlaybackState, TransportState},
    };

    #[test]
    fn group_with_two_members_and_playback() {
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let dining = SpeakerId::new("RINCON_DINING");
        let g = Group {
            id: GroupId::new("RINCON_KITCHEN:1234567890"),
            coordinator: kitchen.clone(),
            members: vec![kitchen.clone(), dining],
            transport: TransportState {
                state: PlaybackState::Playing,
                current_track: Some(Track {
                    id: Some(TrackId::new("t-1")),
                    title: Some("Halcyon".into()),
                    artist: Some("Orbital".into()),
                    album: None,
                    track_number: None,
                    duration: Some(Duration::from_secs(593)),
                    art_uri: None,
                    uri: None,
                }),
                position: Some(Duration::from_secs(60)),
            },
        };
        assert_eq!(g.members.len(), 2);
        assert_eq!(g.members[0], g.coordinator);
        assert_eq!(g.transport.state, PlaybackState::Playing);
    }

    #[test]
    fn solo_group_has_one_member() {
        let id = SpeakerId::new("RINCON_SOLO");
        let g = Group {
            id: GroupId::new("RINCON_SOLO:0"),
            coordinator: id.clone(),
            members: vec![id.clone()],
            transport: TransportState {
                state: PlaybackState::Stopped,
                current_track: None,
                position: None,
            },
        };
        assert_eq!(g.members, vec![id]);
        assert_eq!(g.transport.state, PlaybackState::Stopped);
    }
}
