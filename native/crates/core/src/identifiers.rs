//! Strongly-typed identifiers for the oto domain model.
//!
//! All three IDs wrap a `String` to keep ergonomics close to Sonos's wire
//! format (UPnP `RINCON_…` UUIDs and similar opaque tokens) while preventing
//! accidental cross-use at the type level — a [`GroupId`] cannot be passed
//! where a [`SpeakerId`] is expected.

use std::fmt;

macro_rules! opaque_id {
    ($(#[$attr:meta])* $name:ident) => {
        $(#[$attr])*
        #[derive(Debug, Clone, PartialEq, Eq, Hash)]
        pub struct $name(String);

        impl $name {
            /// Construct from any string-like value.
            pub fn new(s: impl Into<String>) -> Self {
                Self(s.into())
            }

            /// Borrow the underlying string slice.
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl From<String> for $name {
            fn from(s: String) -> Self {
                Self(s)
            }
        }

        impl From<&str> for $name {
            fn from(s: &str) -> Self {
                Self(s.to_owned())
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(&self.0)
            }
        }
    };
}

opaque_id! {
    /// Identifier for an individual Sonos device, typically the `RINCON_…`
    /// UUID reported in UPnP device descriptions.
    SpeakerId
}

opaque_id! {
    /// Identifier for a Sonos zone group — the playback unit; one or more
    /// speakers playing the same audio in sync.
    GroupId
}

opaque_id! {
    /// Identifier for a track in the current queue or media library.
    /// Optional on [`crate::Track`] because radio streams and line-in inputs
    /// don't carry one.
    TrackId
}

#[cfg(test)]
mod tests {
    use super::{GroupId, SpeakerId, TrackId};

    #[test]
    fn speaker_id_round_trip() {
        let id = SpeakerId::new("RINCON_ABC123");
        assert_eq!(id.as_str(), "RINCON_ABC123");
        assert_eq!(id.to_string(), "RINCON_ABC123");
        assert_eq!(SpeakerId::from("RINCON_ABC123"), id);
        assert_eq!(SpeakerId::from(String::from("RINCON_ABC123")), id);
    }

    #[test]
    fn group_id_round_trip() {
        let g = GroupId::from("RINCON_KITCHEN:1234567890");
        assert_eq!(g.as_str(), "RINCON_KITCHEN:1234567890");
    }

    #[test]
    fn track_id_round_trip() {
        let t = TrackId::new("track-1");
        assert_eq!(t.to_string(), "track-1");
    }

    #[test]
    fn distinct_values_are_inequal() {
        assert_ne!(SpeakerId::new("a"), SpeakerId::new("b"));
    }
}
