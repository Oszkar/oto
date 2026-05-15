//! Track metadata for the currently-playing item on a [`crate::Group`].
//!
//! All metadata fields are optional because Sonos returns partial DIDL-Lite
//! payloads for radio streams, line-in inputs, and TV audio.

use std::time::Duration;

use crate::identifiers::TrackId;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Track {
    pub id: Option<TrackId>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub track_number: Option<u32>,
    pub duration: Option<Duration>,
    /// URI of the cover art, if available.
    pub art_uri: Option<String>,
    /// Stream URI for the underlying audio resource.
    pub uri: Option<String>,
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::Track;
    use crate::identifiers::TrackId;

    #[test]
    fn fully_populated_track() {
        let t = Track {
            id: Some(TrackId::new("t-1")),
            title: Some("Halcyon".into()),
            artist: Some("Orbital".into()),
            album: Some("Snivilisation".into()),
            track_number: Some(3),
            duration: Some(Duration::from_secs(593)),
            art_uri: Some("http://example/art.jpg".into()),
            uri: Some("x-file-cifs://nas/halcyon.flac".into()),
        };
        assert_eq!(t.title.as_deref(), Some("Halcyon"));
        assert_eq!(t.duration, Some(Duration::from_secs(593)));
        assert_eq!(t.track_number, Some(3));
    }

    #[test]
    fn radio_stream_track_has_no_metadata() {
        // Streams arrive with only a `uri` populated; everything else is None.
        let t = Track {
            id: None,
            title: None,
            artist: None,
            album: None,
            track_number: None,
            duration: None,
            art_uri: None,
            uri: Some("x-rincon-mp3radio://stream".into()),
        };
        assert!(t.title.is_none());
        assert_eq!(t.uri.as_deref(), Some("x-rincon-mp3radio://stream"));
    }
}
