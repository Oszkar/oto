//! Property-change events flowing from `Wire` impls into `oto-app`'s
//! `StateManager` and on to the FRB stream. Volume is the v0.4 starter
//! variant; Mute / Playback / Track land in Slice 2 (this plan, Task 2);
//! `TopologyChanged` is v0.5.
//!
//! Addressing — per spec § 4 "Concrete shapes":
//!   - `Volume` / `Mute`: per-speaker (`SpeakerId`).
//!   - `Playback` / `Track` (Slice 2): per-group (`GroupId`).
//!
//! `SubscriptionError` / `SubscriptionRecovered` are in-band so the
//! single FRB stream stays alive across recoverable upstream blips —
//! see FRB pre-check § 4.

use crate::{
    identifiers::{GroupId, SpeakerId},
    track::Track,
    transport::PlaybackState,
    volume::Volume,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChangeEvent {
    /// A speaker's volume changed (per-speaker — applies to one device).
    Volume { speaker: SpeakerId, volume: Volume },
    /// A speaker's mute state changed (per-speaker — applies to one device).
    Mute { speaker: SpeakerId, muted: bool },
    /// A group's transport state changed (per-group — applies to all
    /// coordinator + member speakers in the group; see oto-core D2).
    Playback {
        group: GroupId,
        state: PlaybackState,
    },
    /// A group's current track changed. Carries the full `Track` so a
    /// Slice 4 cache reader gets metadata + URI in one event.
    Track { group: GroupId, track: Track },
    /// A per-speaker subscription failed and recovery is being
    /// attempted. The stream itself is still alive; the UI may show
    /// "stale" for that speaker. Reserve `sink.add_error` for fatal
    /// stream termination (FRB pre-check § 4).
    SubscriptionError { speaker: SpeakerId, message: String },
    /// A previously-erroring speaker is back online — its cache is
    /// being refreshed via the next NOTIFY.
    SubscriptionRecovered { speaker: SpeakerId },
    /// The household topology changed (speakers regrouped). Payload-less:
    /// the Dart layer re-pulls authoritative topology on receipt (the
    /// mechanism is a Dart concern — v0.5 S1 uses a debounced full
    /// re-discover; v0.6 may swap in a lighter refresh). The app-layer
    /// cache applies this as a no-op — the re-pull drives the update.
    /// Added in v0.5 (S1).
    TopologyChanged,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn volume_variant_round_trips_speaker_id() {
        let sid = SpeakerId::new("RINCON_KITCHEN");
        let v = Volume::new(50).unwrap();
        let ev = ChangeEvent::Volume {
            speaker: sid.clone(),
            volume: v,
        };
        match ev {
            ChangeEvent::Volume { speaker, volume } => {
                assert_eq!(speaker, sid);
                assert_eq!(volume, v);
            }
            _ => panic!("expected Volume variant"),
        }
    }

    #[test]
    fn subscription_error_carries_message() {
        let ev = ChangeEvent::SubscriptionError {
            speaker: SpeakerId::new("RINCON_X"),
            message: "subscribe timed out".into(),
        };
        assert!(matches!(ev, ChangeEvent::SubscriptionError { .. }));
    }

    #[test]
    fn subscription_recovered_carries_speaker() {
        let sid = SpeakerId::new("RINCON_Y");
        let ev = ChangeEvent::SubscriptionRecovered {
            speaker: sid.clone(),
        };
        match ev {
            ChangeEvent::SubscriptionRecovered { speaker } => assert_eq!(speaker, sid),
            _ => panic!("expected SubscriptionRecovered variant"),
        }
    }

    #[test]
    fn topology_changed_variant_exists() {
        let ev = ChangeEvent::TopologyChanged;
        assert!(matches!(ev, ChangeEvent::TopologyChanged));
    }

    #[test]
    fn enum_is_send_sync() {
        // Required for crossing the channel + the FRB worker boundary.
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<ChangeEvent>();
    }

    #[test]
    fn mute_variant_round_trips_speaker_id() {
        let sid = SpeakerId::new("RINCON_OFFICE");
        let ev = ChangeEvent::Mute {
            speaker: sid.clone(),
            muted: true,
        };
        match ev {
            ChangeEvent::Mute { speaker, muted } => {
                assert_eq!(speaker, sid);
                assert!(muted);
            }
            _ => panic!("expected Mute variant"),
        }
    }

    #[test]
    fn playback_variant_round_trips_group_id() {
        let gid = GroupId::new("RINCON_KITCHEN:1");
        let ev = ChangeEvent::Playback {
            group: gid.clone(),
            state: PlaybackState::Playing,
        };
        match ev {
            ChangeEvent::Playback { group, state } => {
                assert_eq!(group, gid);
                assert_eq!(state, PlaybackState::Playing);
            }
            _ => panic!("expected Playback variant"),
        }
    }

    #[test]
    fn track_variant_round_trips_group_id() {
        let gid = GroupId::new("RINCON_KITCHEN:1");
        let track = Track {
            id: None,
            title: Some("Halcyon".into()),
            artist: Some("Orbital".into()),
            album: None,
            track_number: None,
            duration: None,
            art_uri: None,
            uri: None,
        };
        let ev = ChangeEvent::Track {
            group: gid.clone(),
            track: track.clone(),
        };
        match ev {
            ChangeEvent::Track { group, track: t } => {
                assert_eq!(group, gid);
                assert_eq!(t, track);
            }
            _ => panic!("expected Track variant"),
        }
    }
}
