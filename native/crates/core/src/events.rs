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

use crate::{identifiers::SpeakerId, volume::Volume};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChangeEvent {
    /// A speaker's volume changed (per-speaker — applies to one device).
    Volume {
        speaker: SpeakerId,
        volume: Volume,
    },
    // Mute (per-speaker) lands in Task 2.
    // Playback / Track (per-group) land in Task 2.
    /// A per-speaker subscription failed and recovery is being
    /// attempted. The stream itself is still alive; the UI may show
    /// "stale" for that speaker. Reserve `sink.add_error` for fatal
    /// stream termination (FRB pre-check § 4).
    SubscriptionError {
        speaker: SpeakerId,
        message: String,
    },
    /// A previously-erroring speaker is back online — its cache is
    /// being refreshed via the next NOTIFY.
    SubscriptionRecovered { speaker: SpeakerId },
    // v0.5: TopologyChanged { snapshot: DiscoverySnapshot },
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
    fn enum_is_send_sync() {
        // Required for crossing the channel + the FRB worker boundary.
        fn assert_send_sync<T: Send + Sync>() {}
        assert_send_sync::<ChangeEvent>();
    }
}
