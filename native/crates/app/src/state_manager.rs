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

use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        RwLock,
    },
};

use oto_core::{ChangeEvent, GroupId, PlaybackState, SpeakerId, Track, TransportState, Volume};

/// Per-speaker cached property values. v0.4 — Volume + Mute landed in
/// Task 2. Playback / Track live on the group cache below.
#[derive(Debug, Clone, Default)]
pub(crate) struct SpeakerCache {
    pub volume: Option<Volume>,
    pub muted: Option<bool>,
}

/// Per-group cached transport + track values. v0.4 Task 2 shape:
/// Playback updates `transport.state` (preserving `current_track` /
/// `position` if a prior transport snapshot is present); Track updates
/// `track` AND the cached `transport.current_track` so a one-shot
/// `speaker_state` read at the Slice 4 cache boundary stays coherent.
#[derive(Debug, Clone, Default)]
pub(crate) struct GroupCache {
    pub transport: Option<TransportState>,
    pub track: Option<Track>,
}

pub struct StateManager {
    speakers: RwLock<HashMap<SpeakerId, SpeakerCache>>,
    groups: RwLock<HashMap<GroupId, GroupCache>>,
    /// Generation counter — bumped by `discover_with` on every wire
    /// replacement so the previous consumer loop (still draining the
    /// OLD wire's `Receiver`) can no-op its `apply_event_at_generation`
    /// writes after the bump. Monotonically increasing; starts at 0.
    generation: AtomicU64,
}

impl Default for StateManager {
    fn default() -> Self {
        Self {
            speakers: RwLock::new(HashMap::new()),
            groups: RwLock::new(HashMap::new()),
            generation: AtomicU64::new(0),
        }
    }
}

impl StateManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Generation-aware apply. No-op if `gen` doesn't match the
    /// current generation — used by `subscribe_change_events` to drop
    /// in-flight writes from an old wire's consumer loop after a
    /// `discover_with` replacement.
    ///
    /// The check uses `Ordering::Acquire` to pair with the `Release`
    /// store in `bump_and_clear`: a thread that *first* sees the bump
    /// here will not subsequently observe the pre-bump cache state,
    /// which would race against the clear.
    pub fn apply_event_at_generation(&self, gen: u64, event: &ChangeEvent) {
        if self.generation.load(Ordering::Acquire) != gen {
            return;
        }
        self.apply_event_inner(event);
    }

    /// Apply a `ChangeEvent` to the cache unconditionally. Kept for
    /// internal use + the existing `apply_event` shim so the
    /// pre-generation tests continue to exercise the dispatch logic.
    ///
    /// External callers should prefer `apply_event_at_generation`;
    /// `apply_event` exists as a thin proxy for tests that don't care
    /// about the generation race.
    pub fn apply_event(&self, event: &ChangeEvent) {
        self.apply_event_inner(event);
    }

    fn apply_event_inner(&self, event: &ChangeEvent) {
        match event {
            ChangeEvent::Volume { speaker, volume } => {
                let mut guard = self.speakers.write().unwrap_or_else(|p| p.into_inner());
                guard.entry(speaker.clone()).or_default().volume = Some(*volume);
            }
            ChangeEvent::Mute { speaker, muted } => {
                let mut guard = self.speakers.write().unwrap_or_else(|p| p.into_inner());
                guard.entry(speaker.clone()).or_default().muted = Some(*muted);
            }
            ChangeEvent::Playback { group, state } => {
                let mut guard = self.groups.write().unwrap_or_else(|p| p.into_inner());
                let entry = guard.entry(group.clone()).or_default();
                // Preserve current_track + position from any prior
                // transport snapshot; only the state field changes
                // (per the plan: "preserving current_track + position
                // from prior cache entry if present; replace state
                // only"). If no prior transport, synthesise one with
                // the new state and Nones for the rest.
                let (current_track, position) = match entry.transport.take() {
                    Some(t) => (t.current_track, t.position),
                    None => (entry.track.clone(), None),
                };
                entry.transport = Some(TransportState {
                    state: *state,
                    current_track,
                    position,
                });
            }
            ChangeEvent::Track { group, track } => {
                let mut guard = self.groups.write().unwrap_or_else(|p| p.into_inner());
                let entry = guard.entry(group.clone()).or_default();
                entry.track = Some(track.clone());
                // Keep cached transport.current_track coherent with
                // the dedicated `track` field — otherwise a Slice 4
                // `speaker_state` read could surface a stale title
                // on the transport while the freshest Track event
                // sat in `entry.track`.
                if let Some(t) = entry.transport.as_mut() {
                    t.current_track = Some(track.clone());
                } else {
                    entry.transport = Some(TransportState {
                        state: PlaybackState::Stopped,
                        current_track: Some(track.clone()),
                        position: None,
                    });
                }
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

    /// Read a speaker's cached mute state (None if no event seen yet).
    pub fn muted_of(&self, speaker: &SpeakerId) -> Option<bool> {
        self.speakers
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(speaker)
            .and_then(|c| c.muted)
    }

    /// Read a group's cached transport (None if no Playback / Track
    /// event seen yet for that group).
    pub fn transport_of(&self, group: &GroupId) -> Option<TransportState> {
        self.groups
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(group)
            .and_then(|c| c.transport.clone())
    }

    /// Read a group's cached current track (None if no Track event
    /// seen yet — distinct from `transport.current_track` so a Slice 4
    /// reader can prefer the freshest source).
    pub fn track_of(&self, group: &GroupId) -> Option<Track> {
        self.groups
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(group)
            .and_then(|c| c.track.clone())
    }

    /// Current generation counter — captured by
    /// `subscribe_change_events` once per consumer loop. Reads use
    /// `Acquire` to pair with the `Release` store in `bump_and_clear`.
    pub fn current_generation(&self) -> u64 {
        self.generation.load(Ordering::Acquire)
    }

    /// Bump the generation counter AND clear both caches in one call.
    /// Used by `discover_with` when replacing the wire: any in-flight
    /// `apply_event_at_generation` calls from the OLD wire's consumer
    /// loop will no-op after the bump (the generation check fails),
    /// AND the now-stale state is gone before the NEW wire's seed
    /// events repopulate it.
    ///
    /// The bump uses `Release` and the clear writes happen *after* it,
    /// so a reader who first observes the new generation via
    /// `Acquire` will then observe the cleared maps (which is the
    /// correct invariant: an event that lands at the new generation
    /// should be the only thing in the cache).
    pub fn bump_and_clear(&self) {
        // Order: bump first (Release), then clear. The Acquire-load
        // in `apply_event_at_generation` will see the bumped value
        // first, fail its gen check, and skip the write entirely —
        // so it can't observe the half-cleared map mid-clear.
        self.generation.fetch_add(1, Ordering::Release);
        self.speakers
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        self.groups
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
    }

    /// Clear both caches WITHOUT bumping the generation. Test-only
    /// affordance for `clear_slot()` — production code paths must use
    /// `bump_and_clear`.
    #[cfg(test)]
    pub(crate) fn clear(&self) {
        self.speakers
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        self.groups
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
        sm.apply_event(&ChangeEvent::SubscriptionRecovered { speaker: k.clone() });
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
