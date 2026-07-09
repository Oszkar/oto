//! Per-device state for a single Sonos speaker.
//!
//! Playback state lives on [`crate::Group`], not here - see design doc D2.

use std::net::IpAddr;

use crate::{identifiers::SpeakerId, volume::Volume};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Speaker {
    pub id: SpeakerId,
    /// User-set zone label, e.g. "Kitchen". Maps to Sonos's `RoomName`
    /// property. Bonded satellites (stereo pairs, surrounds) share their
    /// primary's `room_name` and aren't surfaced as separate speakers.
    pub room_name: String,
    pub model: Option<String>,
    pub ip: IpAddr,
    pub volume: Volume,
    pub muted: bool,
}

#[cfg(test)]
mod tests {
    use std::net::{IpAddr, Ipv4Addr};

    use super::Speaker;
    use crate::{identifiers::SpeakerId, volume::Volume};

    #[test]
    fn construct_speaker() {
        let s = Speaker {
            id: SpeakerId::new("RINCON_KITCHEN"),
            room_name: "Kitchen".into(),
            model: Some("Sonos One".into()),
            ip: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 50)),
            volume: Volume::new(35).unwrap(),
            muted: false,
        };
        assert_eq!(s.room_name, "Kitchen");
        assert_eq!(s.volume.get(), 35);
        assert!(!s.muted);
        assert_eq!(s.model.as_deref(), Some("Sonos One"));
    }

    #[test]
    fn speaker_without_model_info() {
        let s = Speaker {
            id: SpeakerId::new("RINCON_X"),
            room_name: "Garage".into(),
            model: None,
            ip: IpAddr::V4(Ipv4Addr::LOCALHOST),
            volume: Volume::MIN,
            muted: true,
        };
        assert!(s.model.is_none());
        assert!(s.muted);
    }
}
