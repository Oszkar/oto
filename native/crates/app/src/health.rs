//! Per-speaker subscription-health tracker (v0.5).
//!
//! Every completed mutating command publishes its observed reachability:
//! `Network` emits `SubscriptionError`; success emits `SubscriptionRecovered`.
//! These observations are repeatable, even if Rust already holds that state:
//! Dart can clear an error on a user scan or miss an event during replacement.
//! The next command must therefore establish health without requiring an edge.
//!
//! `Backend` and `NotFound` leave health untouched and emit nothing. Cached
//! reads and best-effort position reads do not call this tracker because their
//! success does not establish device reachability.

use std::{
    collections::{HashMap, HashSet},
    sync::RwLock,
};

use oto_core::{ChangeEvent, SpeakerId, WireError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HealthState {
    Healthy,
    Errored,
}

pub(crate) struct HealthTracker {
    /// Absent ↔ `Healthy` (the default). Only `Errored` speakers occupy a
    /// slot.
    states: RwLock<HashMap<SpeakerId, HealthState>>,
}

impl HealthTracker {
    pub(crate) fn new() -> Self {
        Self {
            states: RwLock::new(HashMap::new()),
        }
    }

    /// Reset every speaker to `Healthy`. Test-only: unlike `retain_known`,
    /// this is a genuine blanket clear, used to isolate `cfg(test)` runs
    /// from each other in the same process - never call it from production
    /// wire-replacement code (#104: it would erase a still-Errored mark on
    /// a speaker with no evidence it recovered).
    #[cfg(test)]
    pub(crate) fn reset_all(&self) {
        self.states
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
    }

    /// Drop health entries for speakers absent from `known` (the speakers in
    /// a freshly installed topology). Called by `discover_with` on wire
    /// replacement.
    ///
    /// Deliberately NOT a blanket reset (#104). A speaker that survives the
    /// swap keeps whatever mark it had: the wire-generation guard in
    /// `observe` already stops a stale command from mutating it, so the only
    /// legitimate way for it to leave `Errored` is a genuine successful
    /// command against it under the new generation, which emits
    /// `SubscriptionRecovered` normally. Clearing every mark here would flap
    /// a still-unreachable speaker back to `Healthy` on every automatic
    /// regroup, since a topology snapshot is not proof of reachability - a
    /// single speaker's `ZoneGroupState` answer can list a peer that never
    /// responded (see `householdFromTopology`'s `clearHealth` doc comment on
    /// the Dart side). A speaker that drops out of the topology entirely
    /// can never receive another command to clear its slot naturally, so it
    /// is dropped here instead - pure garbage collection, not a recovery
    /// signal.
    pub(crate) fn retain_known(&self, known: &HashSet<SpeakerId>) {
        self.states
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .retain(|speaker, _| known.contains(speaker));
    }

    /// Record and publish every conclusive command observation, including
    /// repeated failures and successes. Only a current-generation `Network`
    /// failure or success changes health; other errors emit nothing.
    ///
    /// Check the command generation under the health lock before mutation.
    /// Discovery may still bump the generation concurrently, so callers must
    /// also stamp the emitted event with `cmd_gen` for consumer filtering.
    pub(crate) fn observe<R>(
        &self,
        cmd_gen: u64,
        current_gen: impl Fn() -> u64,
        speaker: &SpeakerId,
        result: &Result<R, WireError>,
    ) -> Option<ChangeEvent> {
        let mut states = self.states.write().unwrap_or_else(|p| p.into_inner());
        if current_gen() != cmd_gen {
            return None;
        }
        let cur = states.get(speaker).copied().unwrap_or(HealthState::Healthy);
        match result {
            Err(WireError::Network(msg)) => {
                if cur != HealthState::Errored {
                    states.insert(speaker.clone(), HealthState::Errored);
                }
                Some(ChangeEvent::SubscriptionError {
                    speaker: speaker.clone(),
                    message: msg.clone(),
                })
            }
            Ok(_) => {
                // Back to default: remove the slot rather than store Healthy.
                states.remove(speaker);
                Some(ChangeEvent::SubscriptionRecovered {
                    speaker: speaker.clone(),
                })
            }
            // Backend/NotFound and lifecycle errors do not establish health.
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use oto_core::Volume;

    fn ok() -> Result<(), WireError> {
        Ok(())
    }
    fn net() -> Result<(), WireError> {
        Err(WireError::Network("timeout".into()))
    }
    fn backend() -> Result<(), WireError> {
        Err(WireError::Backend("soap fault".into()))
    }
    fn notfound() -> Result<(), WireError> {
        Err(WireError::NotFound("RINCON_X".into()))
    }

    fn sid() -> SpeakerId {
        SpeakerId::new("RINCON_K")
    }

    #[test]
    fn healthy_then_network_emits_subscription_error() {
        let t = HealthTracker::new();
        let ev = t.observe(0, || 0, &sid(), &net());
        assert!(matches!(ev, Some(ChangeEvent::SubscriptionError { .. })));
    }

    #[test]
    fn errored_then_ok_emits_recovered() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &net()).is_some()); // → Errored
        let ev = t.observe(0, || 0, &sid(), &ok());
        assert!(matches!(
            ev,
            Some(ChangeEvent::SubscriptionRecovered { .. })
        ));
    }

    #[test]
    fn repeated_network_publishes_latest_failure() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &net()).is_some());
        let latest: Result<(), WireError> = Err(WireError::Network("connection refused".into()));
        assert_eq!(
            t.observe(0, || 0, &sid(), &latest),
            Some(ChangeEvent::SubscriptionError {
                speaker: sid(),
                message: "connection refused".into(),
            })
        );
    }

    #[test]
    fn repeated_success_republishes_reachability() {
        let t = HealthTracker::new();
        for _ in 0..2 {
            assert_eq!(
                t.observe(0, || 0, &sid(), &ok()),
                Some(ChangeEvent::SubscriptionRecovered { speaker: sid() })
            );
        }
    }

    #[test]
    fn backend_and_notfound_never_emit_or_change_health() {
        let t = HealthTracker::new();
        for result in [backend(), notfound()] {
            assert!(t.observe(0, || 0, &sid(), &result).is_none());
            assert!(t.states.read().unwrap().is_empty());
        }
        assert!(t.observe(0, || 0, &sid(), &net()).is_some());
        for result in [backend(), notfound()] {
            assert!(t.observe(0, || 0, &sid(), &result).is_none());
            assert_eq!(
                t.states.read().unwrap().get(&sid()),
                Some(&HealthState::Errored)
            );
        }
    }

    #[test]
    fn backend_while_errored_does_not_recover() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &net()).is_some()); // → Errored
        // A Backend error is still an error - must NOT recover.
        assert!(t.observe(0, || 0, &sid(), &backend()).is_none());
        // And the speaker is still Errored: a real Ok now recovers.
        assert!(matches!(
            t.observe(0, || 0, &sid(), &ok()),
            Some(ChangeEvent::SubscriptionRecovered { .. })
        ));
    }

    #[test]
    fn reset_all_clears_errored_state() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &net()).is_some()); // → Errored
        t.reset_all();
        assert!(t.states.read().unwrap().is_empty());
    }

    #[test]
    fn retain_known_drops_only_absent_speakers() {
        let t = HealthTracker::new();
        let a = SpeakerId::new("RINCON_A");
        let b = SpeakerId::new("RINCON_B");
        assert!(t.observe(0, || 0, &a, &net()).is_some()); // A → Errored
        assert!(t.observe(0, || 0, &b, &net()).is_some()); // B → Errored

        // B dropped out of the new topology; A survived the swap.
        let known: HashSet<_> = [a.clone()].into_iter().collect();
        t.retain_known(&known);

        // A is still Errored: a real Ok now recovers it, exactly as if no
        // wire swap had happened.
        assert!(matches!(
            t.observe(1, || 1, &a, &ok()),
            Some(ChangeEvent::SubscriptionRecovered { .. })
        ));
        assert!(!t.states.read().unwrap().contains_key(&b));
    }

    #[test]
    fn per_speaker_independent() {
        let t = HealthTracker::new();
        let a = SpeakerId::new("RINCON_A");
        let b = SpeakerId::new("RINCON_B");
        assert!(t.observe(0, || 0, &a, &net()).is_some()); // A → Errored
        assert!(t.observe(0, || 0, &b, &ok()).is_some());
        assert_eq!(
            t.states.read().unwrap().get(&a),
            Some(&HealthState::Errored)
        );
        // A recovers independently.
        assert!(matches!(
            t.observe(0, || 0, &a, &ok()),
            Some(ChangeEvent::SubscriptionRecovered { .. })
        ));
    }

    #[test]
    fn observe_is_generic_over_result_payload() {
        // The observer accepts the payload without treating read results as
        // health signals; only mutating command wrappers call it.
        let t = HealthTracker::new();
        let r: Result<Volume, WireError> = Ok(Volume::new(50).unwrap());
        assert!(matches!(
            t.observe(0, || 0, &sid(), &r),
            Some(ChangeEvent::SubscriptionRecovered { .. })
        ));
    }

    #[test]
    fn stale_generation_observation_is_dropped_and_does_not_poison() {
        // The under-lock generation re-check: a Network result observed at a
        // STALE generation (a rediscover already moved the live gen to 1) must
        // be dropped - no event - AND must not poison the fresh tracker.
        let t = HealthTracker::new();
        assert!(
            t.observe(0, || 1, &sid(), &net()).is_none(),
            "a stale-generation observation must be dropped (no emit)"
        );
        assert!(t.states.read().unwrap().is_empty());
        assert!(t.observe(1, || 1, &sid(), &net()).is_some());
        assert!(t.observe(0, || 1, &sid(), &ok()).is_none());
        assert_eq!(
            t.states.read().unwrap().get(&sid()),
            Some(&HealthState::Errored)
        );
    }
}
