//! Event-fed per-speaker and per-group state cache. Mutated
//! by `apply_event` from the FRB-worker consumer loop in
//! `subscribe_change_events`. Read by `oto_app::speaker_state` (which
//! bypasses `Wire::speaker_state` and reads directly from this cache).
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
        RwLock,
        atomic::{AtomicU64, Ordering},
    },
};

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, PlaybackState, SpeakerId, SpeakerState, Track,
    TransportState, Volume,
};

/// Per-speaker cached property values (v0.4+). Playback / Track live on the
/// group cache below.
#[derive(Debug, Clone, Default)]
pub(crate) struct SpeakerCache {
    pub volume: Option<Volume>,
    pub muted: Option<bool>,
}

/// Per-group cached transport + track values (v0.4+).
/// Playback updates `transport.state` (preserving `current_track` /
/// `position` if a prior transport snapshot is present); Track updates
/// `track` AND the cached `transport.current_track` for a coherent
/// `speaker_state` read.
#[derive(Debug, Clone, Default)]
pub(crate) struct GroupCache {
    pub transport: Option<TransportState>,
    pub track: Option<Track>,
}

/// Per-group cached GroupRenderingControl values (v0.5.1). Distinct from the
/// per-speaker `Volume`/`Mute` on `SpeakerCache` and from the transport/track
/// on `GroupCache` — group volume/mute are their own evented properties. Kept
/// in a separate cache (its own `RwLock`) so a group-volume drag's ~23 events
/// don't contend with transport writes. Last-wins (no dedup — see the `apply`
/// arms): each event overwrites the prior value, matching per-speaker `Volume`.
#[derive(Debug, Clone, Default)]
pub(crate) struct GroupRenderCache {
    pub volume: Option<Volume>,
    pub muted: Option<bool>,
}

/// Speaker→group mapping installed by `install_topology` from each
/// `discover_with` snapshot. Reads in `speaker_state` use it to resolve
/// a speaker's transport from its group's cache. One map (not the full
/// snapshot) is the only thing speaker_state needs; keeping the
/// allocation small.
#[derive(Default)]
struct TopologyMaps {
    speaker_to_group: HashMap<SpeakerId, GroupId>,
    /// `GroupId` → coordinator `SpeakerId`. Used by health tracking to
    /// attribute a group-addressed command's failure to a concrete speaker
    /// (the coordinator the command was routed to).
    group_to_coordinator: HashMap<GroupId, SpeakerId>,
}

/// Build the speaker→group / group→coordinator maps from a snapshot.
/// Shared by `install_topology` and `bump_clear_and_install` so the two
/// paths can't drift.
fn build_topology_maps(snapshot: &DiscoverySnapshot) -> TopologyMaps {
    let mut maps = TopologyMaps::default();
    for g in &snapshot.groups {
        maps.group_to_coordinator
            .insert(g.id.clone(), g.coordinator.clone());
        for m in &g.members {
            maps.speaker_to_group.insert(m.clone(), g.id.clone());
        }
    }
    maps
}

pub struct StateManager {
    speakers: RwLock<HashMap<SpeakerId, SpeakerCache>>,
    groups: RwLock<HashMap<GroupId, GroupCache>>,
    /// Per-group GroupRenderingControl volume/mute (v0.5.1). Its own lock so
    /// the high-frequency group-volume event stream doesn't contend with the
    /// transport/track writes on `groups`. Cleared alongside `groups` on every
    /// generation bump.
    group_render: RwLock<HashMap<GroupId, GroupRenderCache>>,
    /// Speaker→group resolution used by the cache-backed
    /// `speaker_state`. Refreshed by `bump_clear_and_install` on every
    /// successful `discover_with` — atomically with the generation bump +
    /// cache clear, so it is never momentarily empty while a wire is
    /// installed (which would surface as a spurious `speaker_state`
    /// NotFound; see that method).
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
            group_render: RwLock::new(HashMap::new()),
            topology: RwLock::new(TopologyMaps::default()),
            generation: AtomicU64::new(0),
        }
    }
}

impl StateManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Generation-aware apply. No-op if `generation` doesn't match the
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
    pub fn apply_event_at_generation(&self, generation: u64, event: &ChangeEvent) {
        match event {
            ChangeEvent::Volume { speaker, volume } => {
                let mut guard = self.speakers.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != generation {
                    return;
                }
                guard.entry(speaker.clone()).or_default().volume = Some(*volume);
            }
            ChangeEvent::Mute { speaker, muted } => {
                let mut guard = self.speakers.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != generation {
                    return;
                }
                guard.entry(speaker.clone()).or_default().muted = Some(*muted);
            }
            ChangeEvent::Playback { group, state } => {
                let mut guard = self.groups.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != generation {
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
                if self.generation.load(Ordering::Acquire) != generation {
                    return;
                }
                let entry = guard.entry(group.clone()).or_default();
                entry.track = Some(track.clone());
                // Keep cached transport.current_track coherent with
                // the dedicated `track` field — otherwise a
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
            ChangeEvent::GroupVolume { group, volume } => {
                let mut guard = self.group_render.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != generation {
                    return;
                }
                // Last-wins (no dedup): a group-volume drag fires ~23 events;
                // each overwrites the cached value, like per-speaker Volume.
                guard.entry(group.clone()).or_default().volume = Some(*volume);
            }
            ChangeEvent::GroupMute { group, muted } => {
                let mut guard = self.group_render.write().unwrap_or_else(|p| p.into_inner());
                if self.generation.load(Ordering::Acquire) != generation {
                    return;
                }
                guard.entry(group.clone()).or_default().muted = Some(*muted);
            }
            // SubscriptionError / SubscriptionRecovered / TopologyChanged
            // have no cache effect here — they're surface events. The Dart
            // TopologyController reacts to TopologyChanged by re-pulling
            // topology (v0.5: a debounced full re-discover, which
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
        let generation = self.generation.load(Ordering::Acquire);
        self.apply_event_at_generation(generation, event);
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
    /// seen yet — distinct from `transport.current_track` so the
    /// reader can prefer the freshest source).
    pub fn track_of(&self, group: &GroupId) -> Option<Track> {
        self.groups
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(group)
            .and_then(|c| c.track.clone())
    }

    /// Read a group's cached GroupRenderingControl volume (None if no
    /// GroupVolume event seen yet for that group). v0.5.1 read surface.
    pub fn group_volume_of(&self, group: &GroupId) -> Option<Volume> {
        self.group_render
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(group)
            .and_then(|c| c.volume)
    }

    /// Read a group's cached GroupRenderingControl mute state (None if no
    /// GroupMute event seen yet for that group). v0.5.1 read surface.
    pub fn group_muted_of(&self, group: &GroupId) -> Option<bool> {
        self.group_render
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(group)
            .and_then(|c| c.muted)
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

    /// Install the speaker→group mapping from `snapshot`, replacing any
    /// prior topology entirely (no diff/merge). **Test-only now:**
    /// production wire replacement installs topology via
    /// `bump_clear_and_install` (atomically with the generation bump +
    /// cache clear). Retained for the unit tests that exercise topology
    /// installation in isolation.
    #[cfg(test)]
    pub fn install_topology(&self, snapshot: &DiscoverySnapshot) {
        *self.topology.write().unwrap_or_else(|p| p.into_inner()) = build_topology_maps(snapshot);
    }

    /// Resolve a group to its coordinator `SpeakerId` from the installed
    /// topology. `None` if the group is unknown (no topology, or a stale id).
    /// Used by health tracking for group-addressed commands.
    pub fn coordinator_of(&self, group: &GroupId) -> Option<SpeakerId> {
        self.topology
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .group_to_coordinator
            .get(group)
            .cloned()
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

    /// Bump the generation counter AND clear both caches + topology in
    /// one call. Production wire-replacement uses `bump_clear_and_install`
    /// (which folds the new-topology install into the same step); this
    /// primitive is **test-only**, retained for the unit tests that
    /// exercise the clear-to-empty behaviour. Any in-flight
    /// `apply_event_at_generation` calls from the OLD wire's consumer loop
    /// will no-op after the bump (the generation check fails), AND the
    /// now-stale state is gone before the NEW wire's seed events
    /// repopulate it.
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
    #[cfg(test)]
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
        self.group_render
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        *self.topology.write().unwrap_or_else(|p| p.into_inner()) = TopologyMaps::default();
    }

    /// Bump the generation, clear both property caches, AND install the
    /// new topology — in one call — returning the generation this bumped
    /// to. This is the production wire-replacement path (`discover_with`).
    ///
    /// **Why fold the install into the bump** (vs. `bump_and_clear` then
    /// a separate `install_topology`): the two-step path left a window
    /// where the generation had bumped and topology was cleared to
    /// *empty* but the new topology wasn't installed yet — while the OLD
    /// wire was still in the slot. A `speaker_state` landing in that
    /// window saw a present wire with empty topology and returned a
    /// spurious `NotFound` for a speaker that exists in both the old and
    /// new topology. Folding the install in means topology goes old → new
    /// directly (never empty); only the property caches blink empty,
    /// which `speaker_state` already reports as honest-partial `None`s,
    /// not `NotFound`.
    ///
    /// Ordering mirrors `bump_and_clear`: the `fetch_add` is
    /// `Release` and precedes the cache clears, so a stale OLD consumer's
    /// `Acquire`-load in `apply_event_at_generation` sees the new
    /// generation and skips before it can read or write a half-updated
    /// cache. The returned value is `prev + 1`; `discover_with` holds
    /// `DISCOVER_LOCK` across the whole call, so no other thread bumps
    /// concurrently and the return is the authoritative new generation.
    pub fn bump_clear_and_install(&self, snapshot: &DiscoverySnapshot) -> u64 {
        let new_gen = self.generation.fetch_add(1, Ordering::Release) + 1;
        self.speakers
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        self.groups
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        self.group_render
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        // Install the NEW topology directly — do NOT clear to empty
        // first, so a racing `speaker_state` never sees topology empty
        // while a wire is present.
        *self.topology.write().unwrap_or_else(|p| p.into_inner()) = build_topology_maps(snapshot);
        new_gen
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
        self.group_render
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

    // ── Mute / Playback / Track data-model coverage ──────────────────────

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
        // `speaker_state` read of transport.current_track is coherent.
        let t = sm.transport_of(&g).unwrap();
        assert_eq!(t.current_track, Some(track));
    }

    // ── v0.5.1 group volume/mute cache ───────────────────────────────────

    #[test]
    fn apply_group_volume_event_populates_cache() {
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:1");
        assert!(sm.group_volume_of(&g).is_none());
        sm.apply_event(&ChangeEvent::GroupVolume {
            group: g.clone(),
            volume: Volume::new(42).unwrap(),
        });
        assert_eq!(sm.group_volume_of(&g), Some(Volume::new(42).unwrap()));
    }

    #[test]
    fn apply_group_mute_event_populates_cache() {
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:1");
        assert!(sm.group_muted_of(&g).is_none());
        sm.apply_event(&ChangeEvent::GroupMute {
            group: g.clone(),
            muted: true,
        });
        assert_eq!(sm.group_muted_of(&g), Some(true));
    }

    #[test]
    fn group_volume_is_last_wins() {
        // No dedup: each event overwrites the prior value (mirrors a
        // group-volume drag's ~23 events landing last-wins in the cache).
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:1");
        for v in [10u8, 20, 30, 55] {
            sm.apply_event(&ChangeEvent::GroupVolume {
                group: g.clone(),
                volume: Volume::new(v).unwrap(),
            });
        }
        assert_eq!(sm.group_volume_of(&g), Some(Volume::new(55).unwrap()));
    }

    #[test]
    fn bump_clear_and_install_clears_group_render_cache() {
        let sm = StateManager::new();
        let g = GroupId::new("RINCON_K:0");
        sm.apply_event(&ChangeEvent::GroupVolume {
            group: g.clone(),
            volume: Volume::new(60).unwrap(),
        });
        sm.apply_event(&ChangeEvent::GroupMute {
            group: g.clone(),
            muted: true,
        });
        assert!(sm.group_volume_of(&g).is_some());
        assert!(sm.group_muted_of(&g).is_some());

        sm.bump_clear_and_install(&fake_snapshot_two_speaker_group());
        assert!(
            sm.group_volume_of(&g).is_none(),
            "group_render cache must be cleared by the generation bump"
        );
        assert!(sm.group_muted_of(&g).is_none());
    }

    // ── Generation token coverage (PR #43 Codex P2 #5 / Important #4) ─

    #[test]
    fn apply_event_at_generation_with_wrong_generation_is_noop() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");
        let generation = sm.current_generation();
        // Bump so the captured `generation` is now stale.
        sm.bump_and_clear();
        sm.apply_event_at_generation(
            generation,
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
        let generation = sm.current_generation();
        sm.apply_event_at_generation(
            generation,
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

    // ── Cache-backed speaker_state ────────────────────────────────────────

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
        assert!(
            sm.speaker_state(&SpeakerId::new("RINCON_K"))
                .transport
                .is_some()
        );

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

    /// L5: `bump_clear_and_install` must bump the generation, clear the
    /// property caches, AND install the new topology in one call — so a
    /// speaker present in both the old and new topology is NEVER seen as
    /// unknown (which would make `oto_app::speaker_state` return a
    /// spurious `NotFound`). Topology goes old → new directly; only the
    /// property caches blink empty.
    #[test]
    fn bump_clear_and_install_keeps_topology_non_empty() {
        let sm = StateManager::new();
        let k = SpeakerId::new("RINCON_K");

        // Old era: topology + a cached volume.
        sm.install_topology(&fake_snapshot_two_speaker_group());
        sm.apply_event(&ChangeEvent::Volume {
            speaker: k.clone(),
            volume: Volume::new(40).unwrap(),
        });
        assert!(sm.is_known_speaker(&k));
        assert!(sm.volume_of(&k).is_some());

        let before = sm.current_generation();
        // New era via the combined call (same household → kitchen persists).
        let new_gen = sm.bump_clear_and_install(&fake_snapshot_two_speaker_group());

        assert_eq!(new_gen, before + 1, "returns the bumped generation");
        assert_eq!(sm.current_generation(), before + 1);
        assert!(
            sm.volume_of(&k).is_none(),
            "property caches are cleared by the bump (honest-partial cold-start)"
        );
        assert!(
            sm.is_known_speaker(&k),
            "topology installed in the SAME call — never empty, so no spurious NotFound (L5)"
        );
    }
}
