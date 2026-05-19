//! v0.2 one-shot read snapshot for a single speaker (group-of-one).
//! `Option` fields = honest partial-failure: a snapshot is ~4 SOAP
//! reads, any subset may fail (matches SDK `get() -> Option` and the
//! v0.4 cold cache). Revisit at v0.4 (state moves to the event cache).

use crate::{transport::TransportState, volume::Volume};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SpeakerState {
    pub volume: Option<Volume>,
    pub muted: Option<bool>,
    pub transport: Option<TransportState>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transport::{PlaybackState, TransportState};

    #[test]
    fn constructs_partial_snapshot() {
        let s = SpeakerState {
            volume: Some(Volume::new(40).unwrap()),
            muted: Some(false),
            transport: None, // transport read failed; volume/mute still ok
        };
        assert_eq!(s.volume.unwrap().get(), 40);
        assert_eq!(s.muted, Some(false));
        assert!(s.transport.is_none());
    }

    #[test]
    fn full_snapshot() {
        let s = SpeakerState {
            volume: Some(Volume::MIN),
            muted: Some(true),
            transport: Some(TransportState {
                state: PlaybackState::Paused,
                current_track: None,
                position: None,
            }),
        };
        assert_eq!(s.transport.unwrap().state, PlaybackState::Paused);
    }
}
