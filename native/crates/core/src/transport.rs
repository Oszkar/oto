//! Playback state for a [`crate::Group`].

use std::time::Duration;

use crate::track::Track;

/// High-level playback state, mirroring Sonos's `AVTransport.TransportState`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PlaybackState {
    Stopped,
    Playing,
    Paused,
    /// Briefly entered while the speaker buffers a new stream or seeks.
    Transitioning,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransportState {
    pub state: PlaybackState,
    pub current_track: Option<Track>,
    /// Elapsed time within `current_track`, if known.
    pub position: Option<Duration>,
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{PlaybackState, TransportState};
    use crate::{identifiers::TrackId, track::Track};

    fn track(title: &str) -> Track {
        Track {
            id: Some(TrackId::new("t-1")),
            title: Some(title.into()),
            artist: None,
            album: None,
            track_number: None,
            duration: Some(Duration::from_secs(593)),
            art_uri: None,
            uri: None,
        }
    }

    #[test]
    fn playing_with_track_and_position() {
        let s = TransportState {
            state: PlaybackState::Playing,
            current_track: Some(track("Halcyon")),
            position: Some(Duration::from_secs(120)),
        };
        assert_eq!(s.state, PlaybackState::Playing);
        assert_eq!(s.position, Some(Duration::from_secs(120)));
    }

    #[test]
    fn stopped_can_retain_last_track() {
        // Sonos retains the last-loaded track when stopped — see design D4.
        let s = TransportState {
            state: PlaybackState::Stopped,
            current_track: Some(track("Last played")),
            position: None,
        };
        assert_eq!(s.state, PlaybackState::Stopped);
        assert!(s.current_track.is_some());
    }

    #[test]
    fn playback_state_is_copy() {
        let a = PlaybackState::Playing;
        let b = a;
        assert_eq!(a, b);
    }
}
