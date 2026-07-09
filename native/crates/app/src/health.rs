//! Per-speaker subscription-health tracker (v0.5).
//!
//! The SDK at the pinned `=0.5.2` does not expose per-speaker subscription
//! failures (it swallows them internally - see
//! `oto-wire/src/events.rs::register_watches`), so v0.4 carried
//! `ChangeEvent::SubscriptionError` / `SubscriptionRecovered` on the surface
//! but never emitted them. v0.5 closes that gap reactively from command
//! dispatch: every user command's `Result` is observed here, and a
//! `Healthy ↔ Errored` edge for a speaker emits the matching event.
//!
//! Only `WireError::Network` flips a speaker to `Errored` - it's the
//! transport-reachability signal. `Backend` (a SOAP fault from a reachable
//! device) and `NotFound` (a stale/typo'd id - a precondition error, not a
//! reachability one) leave health untouched. Emission is **edge-triggered**:
//! repeated failures or successes after the first do not re-emit.

use std::{collections::HashMap, sync::RwLock};

use oto_core::{ChangeEvent, SpeakerId, WireError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HealthState {
    Healthy,
    Errored,
}

pub(crate) struct HealthTracker {
    /// Absent ↔ `Healthy` (the default). Only `Errored` speakers occupy a
    /// slot, so `reset_all` is a `clear()`.
    states: RwLock<HashMap<SpeakerId, HealthState>>,
}

impl HealthTracker {
    pub(crate) fn new() -> Self {
        Self {
            states: RwLock::new(HashMap::new()),
        }
    }

    /// Reset every speaker to `Healthy`. Called by `discover_with` on wire
    /// replacement so a fresh wire starts with a clean health slate.
    pub(crate) fn reset_all(&self) {
        self.states
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
    }

    /// Observe a command's `Result` for `speaker` and return the event to
    /// emit on a health *transition* (or `None` if health is unchanged).
    ///
    /// - `Healthy` + `Network` → `Errored`, emit `SubscriptionError`.
    /// - `Errored` + `Ok`      → `Healthy`, emit `SubscriptionRecovered`.
    /// - everything else (Backend/NotFound errors, repeated same-state,
    ///   `Ok` while already Healthy) → no transition, `None`.
    ///
    /// `cmd_gen` is the wire generation the command ran under; `current_gen`
    /// reads the live generation. Both are re-checked UNDER the states write
    /// lock: `reset_all` (called by `discover_with` on wire replacement) takes
    /// this same lock, so once we hold it AND the generation still matches, no
    /// replacement can have interleaved between the check and the mutation
    /// below. This closes the race where a stale command's observation lands in
    /// the freshly-reset tracker of a NEW wire (which would surface a spurious
    /// `SubscriptionRecovered` on the next successful command).
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
        match (cur, result) {
            (HealthState::Healthy, Err(WireError::Network(msg))) => {
                states.insert(speaker.clone(), HealthState::Errored);
                Some(ChangeEvent::SubscriptionError {
                    speaker: speaker.clone(),
                    message: msg.clone(),
                })
            }
            (HealthState::Errored, Ok(_)) => {
                // Back to default: remove the slot rather than store Healthy.
                states.remove(speaker);
                Some(ChangeEvent::SubscriptionRecovered {
                    speaker: speaker.clone(),
                })
            }
            // No transition: Backend/NotFound never flip health; repeated
            // Network while Errored, or Ok while Healthy, are no-ops.
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
    fn repeated_network_does_not_re_emit() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &net()).is_some()); // first → error
        assert!(
            t.observe(0, || 0, &sid(), &net()).is_none(),
            "no duplicate error"
        );
        assert!(t.observe(0, || 0, &sid(), &net()).is_none());
    }

    #[test]
    fn repeated_ok_while_healthy_does_not_emit() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &ok()).is_none());
        assert!(t.observe(0, || 0, &sid(), &ok()).is_none());
    }

    #[test]
    fn backend_error_does_not_change_health() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &backend()).is_none());
        // Still Healthy → a later Ok must not emit Recovered.
        assert!(t.observe(0, || 0, &sid(), &ok()).is_none());
    }

    #[test]
    fn notfound_error_does_not_change_health() {
        let t = HealthTracker::new();
        assert!(t.observe(0, || 0, &sid(), &notfound()).is_none());
        assert!(t.observe(0, || 0, &sid(), &ok()).is_none());
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
        // After reset the speaker is Healthy again: an Ok must NOT emit
        // Recovered (no transition from the default).
        assert!(t.observe(0, || 0, &sid(), &ok()).is_none());
    }

    #[test]
    fn per_speaker_independent() {
        let t = HealthTracker::new();
        let a = SpeakerId::new("RINCON_A");
        let b = SpeakerId::new("RINCON_B");
        assert!(t.observe(0, || 0, &a, &net()).is_some()); // A → Errored
        // B is independent: Ok while Healthy → no event.
        assert!(t.observe(0, || 0, &b, &ok()).is_none());
        // A recovers independently.
        assert!(matches!(
            t.observe(0, || 0, &a, &ok()),
            Some(ChangeEvent::SubscriptionRecovered { .. })
        ));
    }

    #[test]
    fn observe_is_generic_over_result_payload() {
        // Commands return Result<(), _>; speaker_state returns
        // Result<SpeakerState, _>. observe must accept any Ok payload.
        let t = HealthTracker::new();
        let r: Result<Volume, WireError> = Ok(Volume::new(50).unwrap());
        assert!(t.observe(0, || 0, &sid(), &r).is_none());
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
        // The speaker was never marked Errored, so an Ok at the CURRENT
        // generation is a no-op - no spurious SubscriptionRecovered.
        assert!(
            t.observe(1, || 1, &sid(), &ok()).is_none(),
            "the dropped stale observation must not leave the speaker Errored"
        );
    }
}
