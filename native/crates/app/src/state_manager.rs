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

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, PlaybackState, SpeakerId, SpeakerState, Track,
    TransportState, Volume,
};

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

/// Speaker→group mapping installed by `install_topology` from each
/// `discover_with` snapshot. Reads in `speaker_state` use it to resolve
/// a speaker's transport from its group's cache. One map (not the full
/// snapshot) is the only thing speaker_state needs; keeping the
/// allocation small.
#[derive(Default)]
struct TopologyMaps {
    speaker_to_group: HashMap<SpeakerId, GroupId>,
}

pub struct StateManager {
    speakers: RwLock<HashMap<SpeakerId, SpeakerCache>>,
    groups: RwLock<HashMap<GroupId, GroupCache>>,
    /// Speaker→group resolution used by Slice 4's cache-backed
    /// `speaker_state`. Refreshed by `install_topology` on every
    /// successful `discover_with`; cleared by `bump_and_clear` so a
    /// failed install never leaves stale topology with fresh caches.
    topology: RwLock<TopologyMaps>,
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
            topology: RwLock::new(TopologyMaps::default()),
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
    /// **Race-closed under-lock generation check** (per /copilot review
    /// on PR #44): each cache-mutating arm takes the relevant write
    /// lock *first*, then re-checks the generation under the lock,
    /// only writing if the gen still matches. A stranded OLD consumer
    /// that resumed after `bump_and_clear` released its write lock
    /// will see the bumped generation here and return without
    /// repopulating the freshly-cleared cache. The earlier design
    /// pre-checked before the lock, which left a window where an OLD
    /// consumer could pass the check, block on the lock during
    /// `bump_and_clear`, then resume and write stale data.
    ///
    /// The check uses `Ordering::Acquire` to pair with the `Release`
    /// store in `bump_and_clear`: a thread that observes the bump
    /// will not subsequently write into a stale cache.
    pub fn apply_event_at_generation(&self, gen: u64, event: &ChangeEvent) {
        match event {
            ChangeEvent::Volume { speaker, volume } => {
                let mut guard = self.speakers.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != gen {
                    return;
                }
                guard.entry(speaker.clone()).or_default().volume = Some(*volume);
            }
            ChangeEvent::Mute { speaker, muted } => {
                let mut guard = self.speakers.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != gen {
                    return;
                }
                guard.entry(speaker.clone()).or_default().muted = Some(*muted);
            }
            ChangeEvent::Playback { group, state } => {
                let mut guard = self.groups.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != gen {
                    return;
                }
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
                if self.generation.load(Ordering::Acquire) != gen {
                    return;
                }
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
            // SubscriptionError / SubscriptionRecovered / TopologyChanged
            // have no cache effect here — they're surface events. The Dart
            // TopologyController reacts to TopologyChanged by re-pulling
            // topology (v0.5 S1: a debounced full re-discover, which
            // rebuilds this cache from scratch); nothing to apply here.
            ChangeEvent::SubscriptionError { .. }
            | ChangeEvent::SubscriptionRecovered { .. }
            | ChangeEvent::TopologyChanged => {}
        }
    }

    /// Apply a `ChangeEvent` to the cache unconditionally. Test-only —
    /// pre-generation tests exercise the dispatch logic without
    /// threading a generation through every call. Production paths
    /// MUST use `apply_event_at_generation`.
    ///
    /// Delegates to `apply_event_at_generation` with the current
    /// generation so the dispatch logic lives in exactly one place.
    #[cfg(test)]
    pub(crate) fn apply_event(&self, event: &ChangeEvent) {
        let gen = self.generation.load(Ordering::Acquire);
        self.apply_event_at_generation(gen, event);
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

    /// True if the speaker is in the current topology. Used by
    /// `oto_app::speaker_state` to preserve the v0.3 "unknown id →
    /// NotFound" error contract without making the cache itself aware
    /// of which ids are "real". The cache is honest-partial; topology
    /// is the source of truth for membership.
    pub fn is_known_speaker(&self, speaker: &SpeakerId) -> bool {
        self.topology
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .speaker_to_group
            .contains_key(speaker)
    }

    /// Install the speaker→group mapping from `snapshot`. Called by
    /// `discover_with` right after `bump_and_clear`, so the topology
    /// always matches the wire whose seeds are about to repopulate the
    /// caches. Replaces any prior topology entirely — no diff/merge.
    pub fn install_topology(&self, snapshot: &DiscoverySnapshot) {
        let mut maps = TopologyMaps::default();
        for g in &snapshot.groups {
            for m in &g.members {
                maps.speaker_to_group.insert(m.clone(), g.id.clone());
            }
        }
        *self.topology.write().unwrap_or_else(|p| p.into_inner()) = maps;
    }

    /// Read the cached state for `speaker`. Honest partial — fields
    /// for which no event has arrived yet (cold-start window, or the
    /// property never changed since subscribe) are `None`. Transport
    /// resolves via speaker → group lookup using the topology installed
    /// by `install_topology`; if no topology is installed or the
    /// speaker isn't a member of any known group, `transport` is `None`.
    pub fn speaker_state(&self, speaker: &SpeakerId) -> SpeakerState {
        let (volume, muted) = self
            .speakers
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(speaker)
            .map(|c| (c.volume, c.muted))
            .unwrap_or((None, None));

        let group = self
            .topology
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .speaker_to_group
            .get(speaker)
            .cloned();

        let transport = group.and_then(|g| {
            self.groups
                .read()
                .unwrap_or_else(|p| p.into_inner())
                .get(&g)
                .and_then(|c| c.transport.clone())
        });

        SpeakerState {
            volume,
            muted,
            transport,
        }
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
    ///
    /// Not atomic across `bump → speakers.clear → groups.clear →
    /// topology.clear`. Safe by construction: no consumer can observe an
    /// intermediate state.
    /// OLD consumers fail the gen check (the bump precedes both clears,
    /// so an OLD consumer always sees the new gen as soon as it sees
    /// any side effect) and skip without reading or writing. NEW
    /// consumers can only enter via `take_event_stream`, which requires
    /// the wire slot to be replaced — and `discover_with` runs the slot
    /// replacement *after* this call returns, so NEW consumers cannot
    /// observe a partially-cleared cache.
    pub fn bump_and_clear(&self) {
        // Order: bump first (Release), then clear. The Acquire-load
        // in `apply_event_at_generation` will see the bumped value
        // first, fail its gen check, and skip the write entirely —
        // so it can't observe the half-cleared map mid-clear. Topology
        // is wiped along with the caches so a `discover_with` that
        // gets as far as bump_and_clear but doesn't reach the
        // `install_topology` step (impossible today, but defensive
        // against future re-orderings) can't leave stale topology
        // attached to a fresh wire's seeds.
        self.generation.fetch_add(1, Ordering::Release);
        self.speakers
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        self.groups
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        *self.topology.write().unwrap_or_else(|p| p.into_inner()) = TopologyMaps::default();
    }

    /// Clear both caches AND topology WITHOUT bumping the generation.
    /// Test-only affordance for `clear_slot()` — production code paths
    /// must use `bump_and_clear`.
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
        *self.topology.write().unwrap_or_else(|p| p.into_inner()) = TopologyMaps::default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use oto_core::{GroupIdentity, SpeakerIdentity};
    use std::net::{IpAddr, Ipv4Addr};

    fn fake_snapshot_two_speaker_group() -> DiscoverySnapshot {
        let kitchen = SpeakerId::new("RINCON_K");
        let dining = SpeakerId::new("RINCON_D");
        let group = GroupId::new("RINCON_K:0");
        DiscoverySnapshot {
            speakers: vec![
                SpeakerIdentity {
                    id: kitchen.clone(),
                    room_name: "Kitchen".into(),
                    model: None,
                    ip: IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1)),
                },
                SpeakerIdentity {
                    id: dining.clone(),
                    room_name: "Dining".into(),
                    model: None,
                    ip: IpAddr::V4(Ipv4Addr::new(10, 0, 0, 2)),
                },
            ],
            groups: vec![GroupIdentity {
                id: group.clone(),
                coordinator: kitchen.clone(),
                members: vec![kitchen, dining],
            }],
        }
    }

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

    // ── Slice 2 data-model coverage ──────────────────────────────────────

    #[test]
    fn apply_mute_event_populates_cache() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        assert!(sm.muted_of(&k).is_none());
        sm.apply_event(&ChangeEvent::Mute {
            speaker: k.clone(),
            muted: true,
        });
        assert_eq!(sm.muted_of(&k), Some(true));
    }

    #[test]
    fn apply_playback_event_creates_transport_with_state() {
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:1");
        sm.apply_event(&ChangeEvent::Playback {
            group: g.clone(),
            state: PlaybackState::Playing,
        });
        let t = sm.transport_of(&g).expect("transport seeded by Playback");
        assert_eq!(t.state, PlaybackState::Playing);
        assert!(t.current_track.is_none());
        assert!(t.position.is_none());
    }

    #[test]
    fn apply_playback_preserves_existing_track_and_position() {
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:1");
        let track = Track {
            id: None,
            title: Some("T".into()),
            artist: None,
            album: None,
            track_number: None,
            duration: None,
            art_uri: None,
            uri: None,
        };
        // First Track populates entry.track + entry.transport.current_track.
        sm.apply_event(&ChangeEvent::Track {
            group: g.clone(),
            track: track.clone(),
        });
        // Then Playback must NOT drop the track.
        sm.apply_event(&ChangeEvent::Playback {
            group: g.clone(),
            state: PlaybackState::Paused,
        });
        let t = sm.transport_of(&g).unwrap();
        assert_eq!(t.state, PlaybackState::Paused);
        assert_eq!(t.current_track, Some(track));
    }

    #[test]
    fn apply_track_updates_both_track_field_and_transport_current_track() {
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:1");
        let track = Track {
            id: None,
            title: Some("Belfast".into()),
            artist: None,
            album: None,
            track_number: None,
            duration: None,
            art_uri: None,
            uri: None,
        };
        sm.apply_event(&ChangeEvent::Track {
            group: g.clone(),
            track: track.clone(),
        });
        assert_eq!(sm.track_of(&g), Some(track.clone()));
        // transport must be synthesised with the same track so a
        // Slice 4 read of transport.current_track is coherent.
        let t = sm.transport_of(&g).unwrap();
        assert_eq!(t.current_track, Some(track));
    }

    // ── Generation token coverage (PR #43 Codex P2 #5 / Important #4) ─

    #[test]
    fn apply_event_at_generation_with_wrong_generation_is_noop() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        let gen = sm.current_generation();
        // Bump so the captured `gen` is now stale.
        sm.bump_and_clear();
        sm.apply_event_at_generation(
            gen,
            &ChangeEvent::Volume {
                speaker: k.clone(),
                volume: Volume::new(99).unwrap(),
            },
        );
        assert!(
            sm.volume_of(&k).is_none(),
            "stale-gen write must not mutate the cache"
        );
    }

    #[test]
    fn apply_event_at_generation_with_right_generation_mutates_cache() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        let gen = sm.current_generation();
        sm.apply_event_at_generation(
            gen,
            &ChangeEvent::Volume {
                speaker: k.clone(),
                volume: Volume::new(60).unwrap(),
            },
        );
        assert_eq!(sm.volume_of(&k), Some(Volume::new(60).unwrap()));
    }

    #[test]
    fn bump_and_clear_increments_generation_and_clears_both_caches() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        let g = GroupId::new("RINCON_K:1");
        // Populate both caches.
        sm.apply_event(&ChangeEvent::Volume {
            speaker: k.clone(),
            volume: Volume::new(50).unwrap(),
        });
        sm.apply_event(&ChangeEvent::Playback {
            group: g.clone(),
            state: PlaybackState::Playing,
        });
        assert!(sm.volume_of(&k).is_some());
        assert!(sm.transport_of(&g).is_some());

        let before = sm.current_generation();
        sm.bump_and_clear();
        let after = sm.current_generation();

        assert_eq!(after, before + 1, "generation must be exactly bumped by 1");
        assert!(
            sm.volume_of(&k).is_none(),
            "speakers cache must be cleared atomically with the bump"
        );
        assert!(
            sm.transport_of(&g).is_none(),
            "groups cache must be cleared atomically with the bump"
        );
    }

    /// Adversarial concurrency: simulate a stale consumer loop still
    /// draining the OLD wire's channel while the NEW wire is already
    /// up. The stale consumer's `apply_event_at_generation(old_gen,
    /// ...)` calls must not pollute the freshly-seeded cache after
    /// `bump_and_clear`.
    ///
    /// This drives the *exact* shape of the api.rs::subscribe_change_events
    /// path: `gen` is captured once, then used for every subsequent
    /// apply. The fix is that the second apply (after `bump_and_clear`)
    /// is a no-op because the captured generation is now stale.
    #[test]
    fn stale_consumer_loop_does_not_pollute_after_bump_and_clear() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");

        // OLD consumer captures its generation on entry.
        let old_gen = sm.current_generation();
        // OLD consumer drains one event from the OLD wire — applies fine.
        sm.apply_event_at_generation(
            old_gen,
            &ChangeEvent::Volume {
                speaker: k.clone(),
                volume: Volume::new(40).unwrap(),
            },
        );
        assert_eq!(sm.volume_of(&k), Some(Volume::new(40).unwrap()));

        // A new discover_with runs: bump + clear (per the new path).
        sm.bump_and_clear();
        // NEW wire has not seeded yet — cache is empty.
        assert!(sm.volume_of(&k).is_none());

        // OLD consumer's loop is still alive (Sender hasn't been
        // dropped yet — slot replacement is the next step), so it
        // pulls one more leftover event from the OLD channel and
        // calls apply_event_at_generation with its CAPTURED old_gen.
        sm.apply_event_at_generation(
            old_gen,
            &ChangeEvent::Volume {
                speaker: k.clone(),
                volume: Volume::new(40).unwrap(),
            },
        );

        // The cache must STILL be empty — the stale apply is dropped.
        assert!(
            sm.volume_of(&k).is_none(),
            "stale OLD-wire event must not repopulate cleared cache"
        );

        // Sanity: the NEW consumer (running at the post-bump gen)
        // can seed normally.
        let new_gen = sm.current_generation();
        assert_ne!(new_gen, old_gen);
        sm.apply_event_at_generation(
            new_gen,
            &ChangeEvent::Volume {
                speaker: k.clone(),
                volume: Volume::new(70).unwrap(),
            },
        );
        assert_eq!(sm.volume_of(&k), Some(Volume::new(70).unwrap()));
    }

    // ── Slice 4 cache-backed speaker_state ───────────────────────────────

    #[test]
    fn speaker_state_returns_all_none_when_no_events_seen() {
        let sm = StateManager::new();
        let st = sm.speaker_state(&SpeakerId::new("RINCON_X"));
        assert!(st.volume.is_none());
        assert!(st.muted.is_none());
        assert!(
            st.transport.is_none(),
            "no topology installed → no group → no transport"
        );
    }

    #[test]
    fn speaker_state_returns_volume_and_mute_without_topology() {
        // Per-speaker fields don't need topology — only `transport` does.
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        sm.apply_event(&ChangeEvent::Volume {
            speaker: k.clone(),
            volume: Volume::new(42).unwrap(),
        });
        sm.apply_event(&ChangeEvent::Mute {
            speaker: k.clone(),
            muted: true,
        });
        let st = sm.speaker_state(&k);
        assert_eq!(st.volume, Some(Volume::new(42).unwrap()));
        assert_eq!(st.muted, Some(true));
        assert!(st.transport.is_none(), "no topology → still no transport");
    }

    #[test]
    fn speaker_state_resolves_transport_via_group_topology() {
        let sm = StateManager::new();
        let snap = fake_snapshot_two_speaker_group();
        sm.install_topology(&snap);

        // Apply Playback to the group; both members should see it.
        let g = GroupId::new("RINCON_K:0");
        sm.apply_event(&ChangeEvent::Playback {
            group: g.clone(),
            state: PlaybackState::Playing,
        });

        let kitchen = sm.speaker_state(&SpeakerId::new("RINCON_K"));
        let dining = sm.speaker_state(&SpeakerId::new("RINCON_D"));
        assert_eq!(
            kitchen.transport.as_ref().map(|t| t.state),
            Some(PlaybackState::Playing),
            "coordinator member sees the group's transport"
        );
        assert_eq!(
            dining.transport.as_ref().map(|t| t.state),
            Some(PlaybackState::Playing),
            "non-coordinator member also sees the group's transport"
        );
    }

    #[test]
    fn install_topology_replaces_prior_topology() {
        let sm = StateManager::new();
        sm.install_topology(&fake_snapshot_two_speaker_group());

        // Now install a fresh snapshot that drops the dining speaker.
        let kitchen = SpeakerId::new("RINCON_K");
        let solo_group = GroupId::new("RINCON_K:1");
        let snap2 = DiscoverySnapshot {
            speakers: vec![SpeakerIdentity {
                id: kitchen.clone(),
                room_name: "Kitchen".into(),
                model: None,
                ip: IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1)),
            }],
            groups: vec![GroupIdentity {
                id: solo_group.clone(),
                coordinator: kitchen.clone(),
                members: vec![kitchen.clone()],
            }],
        };
        sm.install_topology(&snap2);

        // Apply Playback to the NEW group id; kitchen should resolve via it.
        sm.apply_event(&ChangeEvent::Playback {
            group: solo_group.clone(),
            state: PlaybackState::Paused,
        });
        let st = sm.speaker_state(&kitchen);
        assert_eq!(
            st.transport.as_ref().map(|t| t.state),
            Some(PlaybackState::Paused)
        );

        // Dining should resolve to nothing — it's no longer in any group.
        let st2 = sm.speaker_state(&SpeakerId::new("RINCON_D"));
        assert!(
            st2.transport.is_none(),
            "speaker removed from topology has no transport"
        );
    }

    #[test]
    fn bump_and_clear_also_clears_topology() {
        let sm = StateManager::new();
        sm.install_topology(&fake_snapshot_two_speaker_group());

        // Sanity: topology is in place.
        sm.apply_event(&ChangeEvent::Playback {
            group: GroupId::new("RINCON_K:0"),
            state: PlaybackState::Playing,
        });
        assert!(sm
            .speaker_state(&SpeakerId::new("RINCON_K"))
            .transport
            .is_some());

        sm.bump_and_clear();

        // Re-apply a Playback at the same group id (gen is fresh, so it
        // sticks in the groups cache). Without topology, the speaker can
        // no longer resolve to the group.
        let new_gen = sm.current_generation();
        sm.apply_event_at_generation(
            new_gen,
            &ChangeEvent::Playback {
                group: GroupId::new("RINCON_K:0"),
                state: PlaybackState::Playing,
            },
        );
        let st = sm.speaker_state(&SpeakerId::new("RINCON_K"));
        assert!(
            st.transport.is_none(),
            "bump_and_clear must wipe topology so a fresh install is required"
        );
    }
}
