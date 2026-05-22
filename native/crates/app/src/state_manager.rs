//! Event-fed per-speaker (+ per-group in Task 2) state cache. Mutated
//! by `apply_event` from the FRB-worker consumer loop in
//! `subscribe_change_events`. Read by `oto_app::speaker_state` (which
//! in Slice 4 bypasses `Wire::speaker_state` and reads directly here).
//!
//! v0.5-readiness — per spec § 5.4 (lock-granularity audit at v0.4
//! end): each cache is its own `RwLock<HashMap<…>>`. Write holds are
//! short (one variant-dispatch in `apply_event`); reads are not
//! contended with `SLOT` (commands go via `with_wire`, not via this
//! manager). Document any sub-lock change here AND in `lib.rs`'s
//! module comment so v0.5 cannot accidentally regress it.

use std::{collections::HashMap, sync::RwLock};

use oto_core::{ChangeEvent, SpeakerId, Volume};

/// Per-speaker cached property values. v0.4 starter shape — Mute
/// lands in Task 2 of this plan.
#[derive(Debug, Clone, Default)]
pub(crate) struct SpeakerCache {
    pub volume: Option<Volume>,
    // pub muted: Option<bool>,  // Task 2
}

pub struct StateManager {
    speakers: RwLock<HashMap<SpeakerId, SpeakerCache>>,
    // groups: RwLock<HashMap<GroupId, GroupCache>>,  // Task 2
}

impl Default for StateManager {
    fn default() -> Self {
        Self {
            speakers: RwLock::new(HashMap::new()),
        }
    }
}

impl StateManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Apply a `ChangeEvent` to the cache. Called from the FRB-worker
    /// consumer loop in `api.rs::subscribe_change_events`.
    pub fn apply_event(&self, event: &ChangeEvent) {
        match event {
            ChangeEvent::Volume { speaker, volume } => {
                let mut guard = self
                    .speakers
                    .write()
                    .unwrap_or_else(|p| p.into_inner());
                guard.entry(speaker.clone()).or_default().volume = Some(*volume);
            }
            // SubscriptionError / SubscriptionRecovered have no cache
            // effect — they're surface events for the UI.
            ChangeEvent::SubscriptionError { .. } | ChangeEvent::SubscriptionRecovered { .. } => {}
        }
    }

    /// Read a speaker's cached volume (None if no event seen yet).
    pub fn volume_of(&self, speaker: &SpeakerId) -> Option<Volume> {
        self.speakers
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(speaker)
            .and_then(|c| c.volume)
    }

    /// Clear the cache. Used by `discover_with` when replacing the wire.
    pub fn clear(&self) {
        self.speakers
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apply_volume_event_populates_cache() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        assert!(sm.volume_of(&k).is_none());
        sm.apply_event(&ChangeEvent::Volume {
            speaker: k.clone(),
            volume: Volume::new(42).unwrap(),
        });
        assert_eq!(sm.volume_of(&k), Some(Volume::new(42).unwrap()));
    }

    #[test]
    fn subscription_error_does_not_touch_cache() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        sm.apply_event(&ChangeEvent::SubscriptionError {
            speaker: k.clone(),
            message: "x".into(),
        });
        assert!(sm.volume_of(&k).is_none());
    }

    #[test]
    fn subscription_recovered_does_not_touch_cache() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        sm.apply_event(&ChangeEvent::SubscriptionRecovered {
            speaker: k.clone(),
        });
        assert!(sm.volume_of(&k).is_none());
    }

    #[test]
    fn clear_empties_cache() {
        let sm = StateManager::new();
        sm.apply_event(&ChangeEvent::Volume {
            speaker: SpeakerId::new("RINCON_K"),
            volume: Volume::new(50).unwrap(),
        });
        sm.clear();
        assert!(sm.volume_of(&SpeakerId::new("RINCON_K")).is_none());
    }
}
