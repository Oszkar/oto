#![deny(unsafe_code)]

//! Deterministic in-memory `Wire` for tests - no network. Integration
//! tests drive these fixtures so v0.1 discovery is provable without a LAN.
//!
//! `MockWire::default()` seeds a stateful per-speaker model (volume, mute,
//! transport) from the fixture topology. Commands (`set_volume`, `pause`, ...)
//! mutate that model; `speaker_state` reads it back - no real Sonos required.

use std::{
    collections::HashMap,
    net::{IpAddr, Ipv4Addr},
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
    },
};

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, GroupIdentity, PlaybackState, SpeakerId,
    SpeakerIdentity, SpeakerState, TrackPosition, TransportState, Volume, Wire, WireError,
};

// ── Internal model ───────────────────────────────────────────────────────────

/// A grouping snapshot: `GroupId` → coordinator and member → coordinator
/// lookups. The device holds the authoritative one (`Model::grouping`, mutated
/// by join/leave); the routing `Model::cache` holds a copy that `discover()` /
/// `refresh_topology()` commit.
#[derive(Clone, Default)]
struct Grouping {
    /// `GroupId` → coordinator `SpeakerId`.
    coords: HashMap<GroupId, SpeakerId>,
    /// member → coordinator (solo speaker maps to itself). Backs D2
    /// `speaker_state`: own volume/mute + the coordinator's transport.
    member_to_coord: HashMap<SpeakerId, SpeakerId>,
}

impl Grouping {
    fn from_snapshot(snap: &DiscoverySnapshot) -> Self {
        let mut coords = HashMap::new();
        let mut member_to_coord = HashMap::new();
        for g in &snap.groups {
            coords.insert(g.id.clone(), g.coordinator.clone());
            for m in &g.members {
                member_to_coord.insert(m.clone(), g.coordinator.clone());
            }
        }
        Self {
            coords,
            member_to_coord,
        }
    }

    /// Re-home members left behind when `departed` stops coordinating its
    /// group (it joined another group, or went standalone). Mirrors the Sonos
    /// firmware delegating coordination to a remaining member, so the model
    /// never holds an impossible topology - a member pointing at a coordinator
    /// that now follows someone else. Keeps `member_to_coord` and `coords`
    /// mutually consistent. The caller must already have re-pointed `departed`
    /// itself.
    fn reelect_orphans(&mut self, departed: &SpeakerId) {
        let mut orphans: Vec<SpeakerId> = self
            .member_to_coord
            .iter()
            .filter(|(member, coord)| *coord == departed && *member != departed)
            .map(|(member, _)| member.clone())
            .collect();
        // Any group `departed` used to coordinate is stale now - drop it.
        self.coords.retain(|_gid, coord| coord != departed);
        if orphans.is_empty() {
            return;
        }
        // Deterministic new coordinator (lowest id) so tests are stable.
        orphans.sort_by(|a, b| a.as_str().cmp(b.as_str()));
        let new_coord = orphans[0].clone();
        for member in &orphans {
            self.member_to_coord
                .insert(member.clone(), new_coord.clone());
        }
        self.coords
            .insert(GroupId::new(format!("{}:0", new_coord.as_str())), new_coord);
    }

    /// Synthesize the `GroupIdentity` list for a discovery snapshot. Coordinator
    /// first (D3: `members[0]` is the coordinator), then the remaining members
    /// sorted for determinism; groups sorted by id so the snapshot is stable
    /// across `HashMap` iteration order (tests rely on `==`).
    fn to_group_identities(&self) -> Vec<GroupIdentity> {
        let mut members_by_coord: HashMap<SpeakerId, Vec<SpeakerId>> = HashMap::new();
        for (member, coord) in &self.member_to_coord {
            members_by_coord
                .entry(coord.clone())
                .or_default()
                .push(member.clone());
        }
        let mut groups: Vec<GroupIdentity> = self
            .coords
            .iter()
            .map(|(gid, coord)| {
                let mut members = members_by_coord.get(coord).cloned().unwrap_or_default();
                members.sort_by(|a, b| match (a == coord, b == coord) {
                    (true, false) => std::cmp::Ordering::Less,
                    (false, true) => std::cmp::Ordering::Greater,
                    _ => a.as_str().cmp(b.as_str()),
                });
                GroupIdentity {
                    id: gid.clone(),
                    coordinator: coord.clone(),
                    members,
                }
            })
            .collect();
        groups.sort_by(|a, b| a.id.to_string().cmp(&b.id.to_string()));
        groups
    }
}

/// Per-speaker mutable state + the device/cache grouping, held inside the
/// `Mutex`.
struct Model {
    speakers: HashMap<SpeakerId, SpeakerState>,
    /// The device's authoritative grouping (Sonos "ground truth"). `join_group`
    /// / `leave_group` mutate THIS - like a real regroup mutating the devices.
    grouping: Grouping,
    /// Routing cache. Every command/read resolves group→coordinator through
    /// this. Seeded at construction (so a `MockWire::default()` round-trips
    /// commands without ceremony - see [`MockWire`]) and RE-committed from
    /// `grouping` only by `discover()` / `refresh_topology()`. join/leave never
    /// touch it, so - exactly like `SonosWire`'s id→addr / group→coord caches -
    /// a regroup does not change routing until a re-pull.
    cache: Grouping,
    /// Sender half of the v0.4 unified event channel. Lazy-init: only
    /// populated by `subscribe_speakers`. `None` ↔ "no pump active".
    tx: Option<Sender<ChangeEvent>>,
    /// Receiver half - taken once via `take_event_stream`.
    rx: Option<Receiver<ChangeEvent>>,
    /// `true` after `subscribe_topology` succeeds. Gates `TopologyChanged`
    /// emission (mirrors SonosWire only watching `GroupMembership` when
    /// topology was subscribed before the pump spawned).
    topology_subscribed: bool,
    /// Per-speaker forced command error (v0.5 test seam). When a speaker
    /// (or a group's coordinator) has an entry, its commands return the
    /// stored error instead of mutating/emitting - modelling an unreachable
    /// device so oto-app's health tracking can be exercised.
    command_errors: HashMap<SpeakerId, WireError>,
}

/// Volume every speaker is seeded at. Shared by `Model::seeded` and the
/// `seeded_state_initial_values` test so the invariant can't silently drift.
const SEED_VOLUME: u8 = 30;

impl Model {
    fn empty() -> Self {
        Self {
            speakers: HashMap::new(),
            grouping: Grouping::default(),
            cache: Grouping::default(),
            tx: None,
            rx: None,
            topology_subscribed: false,
            command_errors: HashMap::new(),
        }
    }

    fn seeded(snap: &DiscoverySnapshot) -> Self {
        let mut speakers = HashMap::new();
        for s in &snap.speakers {
            speakers.insert(
                s.id.clone(),
                SpeakerState {
                    volume: Some(Volume::new(SEED_VOLUME).expect("SEED_VOLUME in range")),
                    muted: Some(false),
                    transport: Some(TransportState {
                        state: PlaybackState::Stopped,
                        current_track: None,
                        position: None,
                    }),
                },
            );
        }
        let grouping = Grouping::from_snapshot(snap);
        // Cache starts committed so pre-discover commands round-trip (the
        // documented convenience); `discover()` re-commits it anyway.
        let cache = grouping.clone();
        Self {
            speakers,
            grouping,
            cache,
            tx: None,
            rx: None,
            topology_subscribed: false,
            command_errors: HashMap::new(),
        }
    }
}

// ── MockWire ─────────────────────────────────────────────────────────────────

/// A `Wire` that yields a fixed topology (or a fixed error) and maintains
/// per-speaker state so command→state round-trips are testable without a LAN.
///
/// Lifecycle: `MockWire::default()` pre-seeds the model so commands round-trip
/// to state out of the box, but `discovered: AtomicBool` is **false** until a
/// successful `discover()` call. `subscribe_speakers` checks the flag rather
/// than `speakers.is_empty()` so the mock enforces the same "discover first,
/// then subscribe" lifecycle as a real `SonosWire`. Reason: a fixture-only
/// MockWire is not the same thing as a wire whose discovery has been
/// acknowledged by the caller - per /codex review on PR #43, finding P2 #4.
///
/// **Fidelity vs. the real wire (v0.6.3):**
/// - **Grouping is deferred like `SonosWire`.** `join_group` / `leave_group`
///   mutate the device grouping but NOT the routing cache, so a regroup does
///   not change command routing (`play`, `speaker_state`, ...) until a
///   `refresh_topology()` / `discover()` re-pull commits it - exactly as the
///   real wire's caches only change on a `GetZoneGroupState` re-pull. A regroup
///   surfaces as `TopologyChanged` (only when topology was subscribed), which
///   in production drives the debounced Dart refresh.
/// - **Pre-`discover()` commands are a DELIBERATE convenience, not fidelity.**
///   The seeded cache lets a direct `MockWire::default().set_volume(...)` round-
///   trip without ceremony; a real `SonosWire` returns `NotFound` until its
///   caches are populated by `discover()`. This divergence does not leak into
///   integration tests: the production seam always installs the mock through
///   `oto_app::discover_with`, which calls `discover()` first. If a future
///   direct-use test needs the strict contract, call `discover()` up front.
pub struct MockWire {
    outcome: Result<DiscoverySnapshot, WireError>,
    state: Mutex<Model>,
    /// `true` after at least one successful `discover()` call. Mirrors the
    /// real-wire invariant that subscription requires a prior discovery
    /// snapshot. Atomic so `discover()` (sync, `&self`) can flip it without
    /// touching the state `Mutex`.
    discovered: AtomicBool,
}

impl MockWire {
    /// A `Wire` that fails discovery with `err`; commands return `NotFound`
    /// because the model is empty (nothing was seeded).
    pub fn failing(err: WireError) -> Self {
        Self {
            outcome: Err(err),
            state: Mutex::new(Model::empty()),
            discovered: AtomicBool::new(false),
        }
    }

    fn fixture() -> DiscoverySnapshot {
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let dining = SpeakerId::new("RINCON_DINING");
        let office = SpeakerId::new("RINCON_OFFICE");
        DiscoverySnapshot {
            speakers: vec![
                SpeakerIdentity {
                    id: kitchen.clone(),
                    room_name: "Kitchen".into(),
                    model: Some("Sonos One".into()),
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 10)),
                },
                SpeakerIdentity {
                    id: dining.clone(),
                    room_name: "Dining".into(),
                    model: Some("Sonos One".into()),
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 11)),
                },
                SpeakerIdentity {
                    id: office.clone(),
                    room_name: "Office".into(),
                    model: None,
                    ip: IpAddr::V4(Ipv4Addr::new(10, 83, 0, 12)),
                },
            ],
            groups: vec![
                GroupIdentity {
                    id: GroupId::new("RINCON_KITCHEN:1"),
                    coordinator: kitchen.clone(),
                    members: vec![kitchen, dining],
                },
                GroupIdentity {
                    id: GroupId::new("RINCON_OFFICE:0"),
                    coordinator: office.clone(),
                    members: vec![office],
                },
            ],
        }
    }
}

impl Default for MockWire {
    fn default() -> Self {
        let snap = Self::fixture();
        let model = Model::seeded(&snap);
        // Pre-seeded model lets commands work pre-discover, but `discovered`
        // is still false: callers must run `discover()` before
        // `subscribe_speakers()` to match the real-wire contract.
        Self {
            outcome: Ok(snap),
            state: Mutex::new(model),
            discovered: AtomicBool::new(false),
        }
    }
}

// ── Wire implementation ───────────────────────────────────────────────────────

/// Lock the Mutex, recovering from poisoning (panic in another test thread).
macro_rules! lock {
    ($self:expr) => {
        $self
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    };
}

/// Emit a `TopologyChanged` on the event stream - but only when a topology
/// watch is active (`topology_subscribed`) AND a pump is running (`tx`).
/// Mirrors the real wire: the `GroupMembership` watch is registered only if
/// `subscribe_topology` ran before the pump spawned, so a regroup surfaces a
/// `ChangeEvent::TopologyChanged` only when the caller subscribed to topology.
/// No-op before `subscribe_speakers` (no `tx`) or without a topology watch.
fn emit_topology_changed(model: &Model) {
    if model.topology_subscribed
        && let Some(tx) = &model.tx
    {
        let _ = tx.send(ChangeEvent::TopologyChanged);
    }
}

impl MockWire {
    /// Push an arbitrary `ChangeEvent` into the unified channel.
    /// Test-only affordance for adversarial scenarios
    /// (`SubscriptionError`, recovery, out-of-order). No-op if no
    /// pump is active.
    pub fn push_event(&self, event: ChangeEvent) {
        if let Some(tx) = &lock!(self).tx {
            let _ = tx.send(event);
        }
    }

    /// Convenience seam: push a `TopologyChanged` event as if a real GENA
    /// NOTIFY arrived. Goes through the gated emit path, so - like a real
    /// NOTIFY - it delivers only when topology was subscribed and a pump is
    /// active. No-op otherwise.
    pub fn push_topology_change(&self) {
        emit_topology_changed(&lock!(self));
    }

    /// Force commands targeting `speaker` (directly, or as a group's
    /// coordinator) to return `err` instead of succeeding. Models an
    /// unreachable device - used by health-tracking tests. Persists
    /// until `clear_command_error`.
    pub fn set_command_error(&self, speaker: &SpeakerId, err: WireError) {
        lock!(self).command_errors.insert(speaker.clone(), err);
    }

    /// Clear a forced command error so `speaker`'s commands succeed again
    /// (models the device coming back - drives the recovery transition).
    pub fn clear_command_error(&self, speaker: &SpeakerId) {
        lock!(self).command_errors.remove(speaker);
    }

    /// Returns `true` if `subscribe_topology` has been called successfully.
    /// Test-only introspection - confirms `discover_with` auto-subscribes.
    pub fn topology_subscribed(&self) -> bool {
        lock!(self).topology_subscribed
    }

    /// Shared `next`/`previous` body. On real Sonos a skip triggers an
    /// AVTransport NOTIFY (track change, possibly a transitional state),
    /// so the mock mirrors that by emitting a per-group `Playback` event
    /// carrying the coordinator's current cached state - closing the
    /// silent-no-op gap (v0.4 review follow-up). The skip itself doesn't
    /// model a queue, so the state value is the current one (no fabricated
    /// metadata); the point is that a skip is observable on the stream.
    /// Commit the device grouping into the routing cache and synthesize the
    /// discovery snapshot from it: identity (room / model / ip) from the
    /// configured outcome, grouping from the device model. Shared by
    /// `discover()` and `refresh_topology()` so they can't drift. `?` propagates
    /// a `failing()` mock's discovery error before any cache commit.
    fn resnapshot(&self) -> Result<DiscoverySnapshot, WireError> {
        let base = self.outcome.clone()?;
        let mut guard = lock!(self);
        guard.cache = guard.grouping.clone();
        let groups = guard.grouping.to_group_identities();
        Ok(DiscoverySnapshot {
            speakers: base.speakers,
            groups,
        })
    }

    fn skip(&self, group: &GroupId) -> Result<(), WireError> {
        let guard = lock!(self);
        let coord = guard
            .cache
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        if let Some(err) = guard.command_errors.get(&coord) {
            return Err(err.clone());
        }
        let state = guard
            .speakers
            .get(&coord)
            .and_then(|s| s.transport.as_ref().map(|t| t.state))
            .unwrap_or(PlaybackState::Stopped);
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::Playback {
                group: group.clone(),
                state,
            });
        }
        Ok(())
    }
}

impl Wire for MockWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        // Commit the device grouping into the routing cache and synthesize the
        // snapshot from it (shared with `refresh_topology`, so the two agree
        // after a regroup - a plain `self.outcome.clone()` would return the
        // stale original fixture). The `?` propagates a `failing()` mock's error
        // WITHOUT flipping `discovered`.
        let snap = self.resnapshot()?;
        // Flip the lifecycle gate so `subscribe_speakers` can succeed.
        // Idempotent: repeat discovers stay `true`.
        self.discovered.store(true, Ordering::SeqCst);
        Ok(snap)
    }

    fn play(&self, group: &GroupId) -> Result<(), WireError> {
        let mut guard = lock!(self);
        let coord = guard
            .cache
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        if let Some(err) = guard.command_errors.get(&coord) {
            return Err(err.clone());
        }
        let entry = guard
            .speakers
            .get_mut(&coord)
            .ok_or_else(|| WireError::NotFound(coord.to_string()))?;
        // Keep the loaded track (Sonos retains it across pause/stop); clear
        // position - the mock has no playhead.
        let prev_track = entry.transport.take().and_then(|t| t.current_track);
        entry.transport = Some(TransportState {
            state: PlaybackState::Playing,
            current_track: prev_track,
            position: None,
        });
        // Auto-emit per-group Playback event. Real Sonos
        // surfaces AVTransport TransportState NOTIFYs after a Play
        // SOAP success; the mock mirrors that path.
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::Playback {
                group: group.clone(),
                state: PlaybackState::Playing,
            });
        }
        Ok(())
    }

    fn pause(&self, group: &GroupId) -> Result<(), WireError> {
        let mut guard = lock!(self);
        let coord = guard
            .cache
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        if let Some(err) = guard.command_errors.get(&coord) {
            return Err(err.clone());
        }
        let entry = guard
            .speakers
            .get_mut(&coord)
            .ok_or_else(|| WireError::NotFound(coord.to_string()))?;
        // Track-preserve / position-clear rationale as play().
        let prev_track = entry.transport.take().and_then(|t| t.current_track);
        entry.transport = Some(TransportState {
            state: PlaybackState::Paused,
            current_track: prev_track,
            position: None,
        });
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::Playback {
                group: group.clone(),
                state: PlaybackState::Paused,
            });
        }
        Ok(())
    }

    fn next(&self, group: &GroupId) -> Result<(), WireError> {
        self.skip(group)
    }

    fn previous(&self, group: &GroupId) -> Result<(), WireError> {
        self.skip(group)
    }

    fn set_volume(&self, speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
        let mut guard = lock!(self);
        if let Some(err) = guard.command_errors.get(speaker) {
            return Err(err.clone());
        }
        let entry = guard
            .speakers
            .get_mut(speaker)
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))?;
        entry.volume = Some(volume);
        // Auto-emit. Mirrors real Sonos: SOAP success → device NOTIFY.
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::Volume {
                speaker: speaker.clone(),
                volume,
            });
        }
        Ok(())
    }

    fn set_mute(&self, speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
        let mut guard = lock!(self);
        if let Some(err) = guard.command_errors.get(speaker) {
            return Err(err.clone());
        }
        let entry = guard
            .speakers
            .get_mut(speaker)
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))?;
        entry.muted = Some(muted);
        // Auto-emit. Mirrors real Sonos: SOAP success → device NOTIFY.
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::Mute {
                speaker: speaker.clone(),
                muted,
            });
        }
        Ok(())
    }

    fn set_group_volume(&self, group: &GroupId, volume: Volume) -> Result<(), WireError> {
        let guard = lock!(self);
        // Group volume is coordinator-routed (like play/pause): resolve
        // group → coordinator. Unknown group → NotFound; honor a forced
        // command error on the coordinator (models an unreachable device).
        let coord = guard
            .cache
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        if let Some(err) = guard.command_errors.get(&coord) {
            return Err(err.clone());
        }
        // Auto-emit a per-group GroupVolume event (mirrors real Sonos:
        // SetGroupVolume SOAP success → group_volume NOTIFY). Group volume is
        // event-fed only - there is no `Model` field to round-trip (unlike the
        // per-speaker `set_volume`); the emitted event is the read path.
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::GroupVolume {
                group: group.clone(),
                volume,
            });
        }
        Ok(())
    }

    fn set_group_mute(&self, group: &GroupId, muted: bool) -> Result<(), WireError> {
        let guard = lock!(self);
        let coord = guard
            .cache
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        if let Some(err) = guard.command_errors.get(&coord) {
            return Err(err.clone());
        }
        if let Some(tx) = &guard.tx {
            let _ = tx.send(ChangeEvent::GroupMute {
                group: group.clone(),
                muted,
            });
        }
        Ok(())
    }

    fn join_group(&self, speaker: &SpeakerId, coordinator: &SpeakerId) -> Result<(), WireError> {
        let mut guard = lock!(self);
        // Both ids must be known (mirrors SonosWire resolving both → IP).
        if !guard.speakers.contains_key(speaker) {
            return Err(WireError::NotFound(speaker.to_string()));
        }
        if !guard.speakers.contains_key(coordinator) {
            return Err(WireError::NotFound(coordinator.to_string()));
        }
        if let Some(err) = guard.command_errors.get(speaker) {
            return Err(err.clone());
        }
        // Fold `speaker` into `coordinator`'s group in the DEVICE grouping only
        // (not the routing cache) - like SonosWire, the regroup doesn't change
        // routing until a `refresh_topology()`/`discover()` re-pull. If `speaker`
        // had been coordinating a group, re-home the members it leaves behind
        // (and drop its now-stale group) so they don't end up pointing at a
        // coordinator that itself follows another group.
        guard
            .grouping
            .member_to_coord
            .insert(speaker.clone(), coordinator.clone());
        guard.grouping.reelect_orphans(speaker);
        emit_topology_changed(&guard);
        Ok(())
    }

    fn leave_group(&self, speaker: &SpeakerId) -> Result<(), WireError> {
        let mut guard = lock!(self);
        if !guard.speakers.contains_key(speaker) {
            return Err(WireError::NotFound(speaker.to_string()));
        }
        if let Some(err) = guard.command_errors.get(speaker) {
            return Err(err.clone());
        }
        // Mutate the DEVICE grouping only (not the routing cache - deferred like
        // SonosWire). Uniform - no branch on whether `speaker` coordinated a
        // group. First re-home any members it was coordinating (the firmware
        // delegates the old group to a remaining member); this also drops
        // `speaker`'s stale old group. THEN `speaker` becomes its own standalone
        // group with a fresh solo GroupId. Order matters: re-election must run
        // before the standalone insert, since it prunes every group `speaker`
        // coordinates.
        guard.grouping.reelect_orphans(speaker);
        guard
            .grouping
            .member_to_coord
            .insert(speaker.clone(), speaker.clone());
        guard.grouping.coords.insert(
            GroupId::new(format!("{}:0", speaker.as_str())),
            speaker.clone(),
        );
        emit_topology_changed(&guard);
        Ok(())
    }

    fn speaker_state(&self, speaker: &SpeakerId) -> Result<SpeakerState, WireError> {
        let guard = lock!(self);
        let own = guard
            .speakers
            .get(speaker)
            .cloned()
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))?;
        // D2: transport comes from the speaker's group coordinator
        // (solo speaker = its own coordinator → own transport). Resolved through
        // the routing cache, so a not-yet-refreshed regroup reads the old group.
        let coord = guard.cache.member_to_coord.get(speaker).cloned();
        let transport = match coord {
            Some(c) => guard.speakers.get(&c).and_then(|s| s.transport.clone()),
            None => own.transport.clone(),
        };
        Ok(SpeakerState {
            volume: own.volume,
            muted: own.muted,
            transport,
        })
    }

    fn track_position(&self, group: &GroupId) -> Result<TrackPosition, WireError> {
        let guard = lock!(self);
        let coord = guard
            .cache
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        let transport = guard.speakers.get(&coord).and_then(|s| s.transport.clone());
        Ok(TrackPosition {
            position: transport.as_ref().and_then(|t| t.position),
            duration: transport
                .as_ref()
                .and_then(|t| t.current_track.as_ref())
                .and_then(|tr| tr.duration),
        })
    }

    fn subscribe_speakers(&self) -> Result<(), WireError> {
        // Match the real-wire contract: subscription requires a prior
        // successful `discover()`. The pre-seeded fixture in
        // `MockWire::default()` doesn't count as discovery - the caller
        // must actually call `discover()` first (per /codex review on
        // PR #43, finding P2 #4).
        if !self.discovered.load(Ordering::SeqCst) {
            return Err(WireError::NoSpeakersDiscovered);
        }
        let mut guard = lock!(self);
        if guard.tx.is_some() {
            return Err(WireError::AlreadySubscribed);
        }
        let (tx, rx) = mpsc::channel();
        // ── Seed events ──────────────────────────────────────────────────
        //
        // Real Sonos sends a cold-start NOTIFY per subscribed service
        // when a new subscription opens. The mock mirrors that:
        //   - per-speaker Volume (one event per cached speaker.volume)
        //   - per-speaker Mute   (one event per cached speaker.muted)
        //   - per-group   Playback (one event per group, state from
        //     the coordinator's cached transport - defaults to
        //     PlaybackState::Stopped from the seeded fixture)
        //
        // Track is intentionally NOT seeded: `oto_core::Track` carries
        // optional metadata fields and the fixture has no media
        // loaded (`transport.current_track` is None on every cached
        // speaker), so emitting a Track seed would require either
        // (a) inventing fake metadata that drifts from the rest of
        // the fixture, or (b) adding a Track::default impl that
        // pollutes the type system with "all None" sentinels for
        // tests' sake. Tests that need a track use
        // `MockWire::push_event` (or the dev_push seam in api.rs).
        let mut seeds: Vec<ChangeEvent> = Vec::with_capacity(
            // 2 per speaker (Volume + Mute) + 1 per group (Playback);
            // 8 events total for the 3-speaker / 2-group fixture.
            // Capacity is a hint; re-allocation is fine.
            guard.speakers.len() * 2 + guard.cache.coords.len(),
        );
        for (sid, st) in &guard.speakers {
            if let Some(v) = st.volume {
                seeds.push(ChangeEvent::Volume {
                    speaker: sid.clone(),
                    volume: v,
                });
            }
            if let Some(m) = st.muted {
                seeds.push(ChangeEvent::Mute {
                    speaker: sid.clone(),
                    muted: m,
                });
            }
        }
        for (gid, coord) in &guard.cache.coords {
            // Read the coordinator's cached transport state. The
            // seeded fixture always populates this with
            // PlaybackState::Stopped, so on an unmodified MockWire
            // every group emits one Playback { Stopped } seed.
            let state = guard
                .speakers
                .get(coord)
                .and_then(|s| s.transport.as_ref().map(|t| t.state))
                .unwrap_or(PlaybackState::Stopped);
            seeds.push(ChangeEvent::Playback {
                group: gid.clone(),
                state,
            });
        }
        for ev in seeds {
            // Pre-pump send - receiver is buffered, so this can't fail.
            let _ = tx.send(ev);
        }
        guard.tx = Some(tx);
        guard.rx = Some(rx);
        Ok(())
    }

    fn subscribe_topology(&self) -> Result<(), WireError> {
        if !self.discovered.load(Ordering::SeqCst) {
            return Err(WireError::NoSpeakersDiscovered);
        }
        let mut guard = lock!(self);
        // Mirror the SonosWire contract: must be called before the pump
        // (here, `subscribe_speakers` sets `tx`). Idempotent before the
        // pump; once the pump is running, `Ok` only if topology was already
        // requested, else `AlreadySubscribed` (fail fast - the watch can no
        // longer be registered).
        if guard.tx.is_some() && !guard.topology_subscribed {
            return Err(WireError::AlreadySubscribed);
        }
        guard.topology_subscribed = true;
        Ok(())
    }

    fn refresh_topology(&self) -> Result<DiscoverySnapshot, WireError> {
        // Re-pull authoritative topology reflecting any join/leave mutations
        // since the last commit - mirrors SonosWire's GetZoneGroupState re-pull.
        // Commits the device grouping into the routing cache and synthesizes the
        // snapshot from it (identity from the configured outcome). Shared with
        // `discover()` so the two can't drift.
        self.resnapshot()
    }

    fn take_event_stream(&self) -> Option<Receiver<ChangeEvent>> {
        lock!(self).rx.take()
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── Existing tests (unchanged) ───────────────────────────────────────────

    #[test]
    fn default_returns_fixture() {
        let snap = MockWire::default().discover().unwrap();
        assert_eq!(snap.speakers.len(), 3);
        assert_eq!(snap.groups.len(), 2);
        // Anchor specific fixture values so downstream integration tests
        // (and this fixture) fail loudly if the data is silently edited.
        assert_eq!(snap.speakers[0].room_name, "Kitchen");
        assert_eq!(snap.speakers[2].model, None);
        assert_eq!(snap.groups[0].id.as_str(), "RINCON_KITCHEN:1");
        assert_eq!(snap.groups[0].members.len(), 2);
        assert_eq!(snap.groups[0].members[0], snap.groups[0].coordinator);
        assert_eq!(snap.groups[1].members.len(), 1);
    }

    #[test]
    fn failing_returns_error() {
        let err = MockWire::failing(WireError::NoDevicesFound).discover();
        assert_eq!(err, Err(WireError::NoDevicesFound));
    }

    // ── Stateful round-trip tests ────────────────────────────────────────────

    #[test]
    fn set_volume_then_read_round_trips() {
        let w = MockWire::default();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        w.set_volume(&kitchen, Volume::new(70).unwrap()).unwrap();
        assert_eq!(
            w.speaker_state(&kitchen).unwrap().volume,
            Some(Volume::new(70).unwrap())
        );
    }

    #[test]
    fn pause_sets_transport_paused() {
        let w = MockWire::default();
        w.pause(&GroupId::new("RINCON_KITCHEN:1")).unwrap();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        assert_eq!(
            w.speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Paused
        );
    }

    #[test]
    fn unknown_id_is_not_found() {
        let w = MockWire::default();
        assert_eq!(
            w.set_mute(&SpeakerId::new("RINCON_NOPE"), true),
            Err(WireError::NotFound("RINCON_NOPE".into()))
        );
    }

    // ── Additional coverage ──────────────────────────────────────────────────

    #[test]
    fn play_sets_transport_playing() {
        let w = MockWire::default();
        w.play(&GroupId::new("RINCON_KITCHEN:1")).unwrap();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        assert_eq!(
            w.speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Playing
        );
    }

    #[test]
    fn set_mute_then_read_round_trips() {
        let w = MockWire::default();
        let office = SpeakerId::new("RINCON_OFFICE");
        w.set_mute(&office, true).unwrap();
        assert_eq!(w.speaker_state(&office).unwrap().muted, Some(true));
    }

    #[test]
    fn next_and_previous_ok_for_known_group() {
        let w = MockWire::default();
        let g = GroupId::new("RINCON_OFFICE:0");
        assert_eq!(w.next(&g), Ok(()));
        assert_eq!(w.previous(&g), Ok(()));
    }

    #[test]
    fn next_unknown_group_is_not_found() {
        let w = MockWire::default();
        assert_eq!(
            w.next(&GroupId::new("RINCON_GHOST:0")),
            Err(WireError::NotFound("RINCON_GHOST:0".into()))
        );
    }

    #[test]
    fn failing_mock_commands_return_not_found() {
        let w = MockWire::failing(WireError::NoDevicesFound);
        let speaker = SpeakerId::new("RINCON_KITCHEN");
        assert!(matches!(
            w.set_volume(&speaker, Volume::new(50).unwrap()),
            Err(WireError::NotFound(_))
        ));
        assert!(matches!(
            w.speaker_state(&speaker),
            Err(WireError::NotFound(_))
        ));
    }

    #[test]
    fn seeded_state_initial_values() {
        let w = MockWire::default();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let state = w.speaker_state(&kitchen).unwrap();
        assert_eq!(state.volume, Some(Volume::new(SEED_VOLUME).unwrap()));
        assert_eq!(state.muted, Some(false));
        assert_eq!(state.transport.unwrap().state, PlaybackState::Stopped);
    }

    #[test]
    fn non_coordinator_speaker_state_reflects_coordinator_transport() {
        let w = MockWire::default();
        let dining = SpeakerId::new("RINCON_DINING"); // member of Kitchen group, NOT coordinator
        w.set_volume(&dining, Volume::new(55).unwrap()).unwrap();
        w.play(&GroupId::new("RINCON_KITCHEN:1")).unwrap();
        let st = w.speaker_state(&dining).unwrap();
        assert_eq!(
            st.transport.unwrap().state,
            PlaybackState::Playing,
            "D2: non-coordinator transport must reflect the coordinator (Kitchen)"
        );
        assert_eq!(
            st.volume,
            Some(Volume::new(55).unwrap()),
            "own volume, independent of the coordinator"
        );
    }

    // ── v0.4 event surface ────────────────────────────────────────────────

    /// Failed-discovery path: `failing()` never flips `discovered`, so
    /// `subscribe_speakers` must reject. Covers the "discover errored"
    /// branch of the lifecycle gate.
    #[test]
    fn subscribe_speakers_errors_without_successful_discovery() {
        let w = MockWire::failing(WireError::NoDevicesFound);
        assert_eq!(w.subscribe_speakers(), Err(WireError::NoSpeakersDiscovered));
    }

    /// Default-but-no-discover path: `MockWire::default()` pre-seeds the
    /// model so commands work, but `discover()` hasn't been called, so
    /// `subscribe_speakers` must STILL reject. This is the regression
    /// fix for /codex review P2 #4 - the previous `speakers.is_empty()`
    /// check let pre-seeded mocks bypass the discover-first contract.
    #[test]
    fn subscribe_speakers_errors_on_default_without_discover() {
        let w = MockWire::default();
        assert_eq!(w.subscribe_speakers(), Err(WireError::NoSpeakersDiscovered));
    }

    /// After a successful `discover()`, `subscribe_speakers` works.
    /// Idempotency: repeat `discover()` keeps `discovered` true.
    #[test]
    fn discover_then_subscribe_speakers_ok() {
        let w = MockWire::default();
        w.discover().unwrap();
        assert!(w.subscribe_speakers().is_ok());
    }

    #[test]
    fn subscribe_speakers_twice_errors() {
        let w = MockWire::default();
        w.discover().unwrap();
        assert!(w.subscribe_speakers().is_ok());
        assert_eq!(w.subscribe_speakers(), Err(WireError::AlreadySubscribed));
    }

    /// Collect every event the mock's pump has queued, with a short
    /// per-recv timeout. Used by tests to drain the seed phase
    /// without hardcoding a count.
    fn drain_seeds(rx: &Receiver<ChangeEvent>) -> Vec<ChangeEvent> {
        let mut out = Vec::new();
        while let Ok(ev) = rx.recv_timeout(std::time::Duration::from_millis(50)) {
            out.push(ev);
        }
        out
    }

    #[test]
    fn subscribe_emits_volume_mute_playback_seeds() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().expect("first take returns Some");

        let seeds = drain_seeds(&rx);

        // Fixture: 3 speakers + 2 groups. Expect:
        //   3 Volume   (one per speaker, all SEED_VOLUME)
        //   3 Mute     (one per speaker, all false)
        //   2 Playback (one per group, all Stopped)
        let mut volume_speakers = std::collections::HashSet::new();
        let mut mute_speakers = std::collections::HashSet::new();
        let mut playback_groups = std::collections::HashSet::new();
        for ev in &seeds {
            match ev {
                ChangeEvent::Volume { speaker, .. } => {
                    volume_speakers.insert(speaker.clone());
                }
                ChangeEvent::Mute { speaker, muted } => {
                    assert!(!muted, "seed mute starts unmuted");
                    mute_speakers.insert(speaker.clone());
                }
                ChangeEvent::Playback { group, state } => {
                    assert_eq!(*state, PlaybackState::Stopped, "seed playback is Stopped");
                    playback_groups.insert(group.clone());
                }
                other => panic!("unexpected seed event: {other:?}"),
            }
        }
        assert_eq!(volume_speakers.len(), 3, "one Volume seed per speaker");
        assert_eq!(mute_speakers.len(), 3, "one Mute seed per speaker");
        assert_eq!(playback_groups.len(), 2, "one Playback seed per group");
        assert_eq!(
            seeds.len(),
            3 + 3 + 2,
            "no extra (e.g. Track) seeds emitted by default"
        );
    }

    #[test]
    fn set_volume_auto_emits_volume_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        // Drain the seeds (now 8 events: 3 Volume + 3 Mute + 2 Playback)
        // without hardcoding the count.
        let _ = drain_seeds(&rx);
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        w.set_volume(&kitchen, Volume::new(70).unwrap()).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::Volume { speaker, volume } => {
                assert_eq!(speaker, kitchen);
                assert_eq!(volume, Volume::new(70).unwrap());
            }
            other => panic!("expected Volume event from set_volume, got {other:?}"),
        }
    }

    #[test]
    fn set_mute_auto_emits_mute_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let office = SpeakerId::new("RINCON_OFFICE");
        w.set_mute(&office, true).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::Mute { speaker, muted } => {
                assert_eq!(speaker, office);
                assert!(muted);
            }
            other => panic!("expected Mute event from set_mute, got {other:?}"),
        }
    }

    #[test]
    fn play_auto_emits_playback_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let g = GroupId::new("RINCON_KITCHEN:1");
        w.play(&g).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::Playback { group, state } => {
                assert_eq!(group, g);
                assert_eq!(state, PlaybackState::Playing);
            }
            other => panic!("expected Playback event from play, got {other:?}"),
        }
    }

    #[test]
    fn pause_auto_emits_playback_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let g = GroupId::new("RINCON_OFFICE:0");
        w.pause(&g).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::Playback { group, state } => {
                assert_eq!(group, g);
                assert_eq!(state, PlaybackState::Paused);
            }
            other => panic!("expected Playback event from pause, got {other:?}"),
        }
    }

    #[test]
    fn next_emits_playback_event() {
        // v0.4 review follow-up: a skip must be observable on the event
        // stream (mirrors the real AVTransport NOTIFY), not a silent no-op.
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let g = GroupId::new("RINCON_KITCHEN:1");
        w.next(&g).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::Playback { group, .. } => assert_eq!(group, g),
            other => panic!("expected Playback event from next, got {other:?}"),
        }
    }

    #[test]
    fn previous_emits_playback_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let g = GroupId::new("RINCON_OFFICE:0");
        w.previous(&g).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::Playback { group, .. } => assert_eq!(group, g),
            other => panic!("expected Playback event from previous, got {other:?}"),
        }
    }

    #[test]
    fn push_event_surfaces_arbitrary_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        w.push_event(ChangeEvent::SubscriptionError {
            speaker: SpeakerId::new("RINCON_GHOST"),
            message: "synthesized for test".into(),
        });
        assert!(matches!(
            rx.recv_timeout(std::time::Duration::from_millis(100))
                .unwrap(),
            ChangeEvent::SubscriptionError { .. }
        ));
    }

    #[test]
    fn take_event_stream_is_one_shot() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        assert!(w.take_event_stream().is_some());
        assert!(w.take_event_stream().is_none(), "second take returns None");
    }

    // ── v0.5 topology surface ─────────────────────────────────────────────

    #[test]
    fn subscribe_topology_errors_without_discover() {
        let w = MockWire::default();
        assert_eq!(w.subscribe_topology(), Err(WireError::NoSpeakersDiscovered));
    }

    #[test]
    fn subscribe_topology_ok_after_discover() {
        let w = MockWire::default();
        w.discover().unwrap();
        assert!(w.subscribe_topology().is_ok());
        assert!(w.topology_subscribed(), "flag set after subscribe");
    }

    #[test]
    fn subscribe_topology_is_idempotent() {
        let w = MockWire::default();
        w.discover().unwrap();
        assert!(w.subscribe_topology().is_ok());
        assert!(w.subscribe_topology().is_ok(), "second call must not error");
    }

    #[test]
    fn subscribe_topology_after_speakers_without_prior_request_errors() {
        // Misuse: subscribe_speakers ran first (pump active), topology was
        // never requested → the watch can't start, so fail fast.
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        assert_eq!(w.subscribe_topology(), Err(WireError::AlreadySubscribed));
    }

    #[test]
    fn subscribe_topology_then_speakers_then_repeat_is_ok() {
        // Correct order: topology requested before the pump. A redundant
        // post-pump call is idempotent Ok (the watch is already active).
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_topology().unwrap();
        w.subscribe_speakers().unwrap();
        assert!(
            w.subscribe_topology().is_ok(),
            "repeat after pump is Ok when topology was already requested"
        );
    }

    #[test]
    fn refresh_topology_returns_fixture_snapshot() {
        let w = MockWire::default();
        w.discover().unwrap();
        let snap = w.refresh_topology().unwrap();
        assert_eq!(snap.speakers.len(), 3);
        assert_eq!(snap.groups.len(), 2);
    }

    #[test]
    fn refresh_topology_errors_on_failing_mock() {
        let w = MockWire::failing(WireError::NoDevicesFound);
        assert_eq!(w.refresh_topology(), Err(WireError::NoDevicesFound));
    }

    /// refresh_topology must reflect a post-discover regroup (mirrors
    /// SonosWire's GetZoneGroupState re-pull), not return the stale fixture.
    #[test]
    fn refresh_topology_reflects_join_mutation() {
        let w = MockWire::default();
        w.discover().unwrap();
        let office = SpeakerId::new("RINCON_OFFICE");
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        w.join_group(&office, &kitchen).unwrap();

        let snap = w.refresh_topology().unwrap();
        assert_eq!(
            snap.speakers.len(),
            3,
            "identity set is unchanged by a regroup"
        );
        assert!(
            !snap
                .groups
                .iter()
                .any(|g| g.id == GroupId::new("RINCON_OFFICE:0")),
            "joiner's former solo group must not appear in the refreshed snapshot"
        );
        let kitchen_grp = snap
            .groups
            .iter()
            .find(|g| g.coordinator == kitchen)
            .expect("Kitchen group present");
        assert!(
            kitchen_grp.members.contains(&office),
            "refreshed snapshot must show Office folded into Kitchen's group"
        );
    }

    /// A regroup surfaces as `TopologyChanged` on the stream - the real wire's
    /// GroupMembership NOTIFY equivalent, which drives the Dart re-discover.
    #[test]
    fn join_group_emits_topology_changed_when_subscribed() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_topology().unwrap(); // required before the pump for the emit
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        w.join_group(
            &SpeakerId::new("RINCON_OFFICE"),
            &SpeakerId::new("RINCON_KITCHEN"),
        )
        .unwrap();
        assert!(matches!(
            rx.recv_timeout(std::time::Duration::from_millis(100))
                .unwrap(),
            ChangeEvent::TopologyChanged
        ));
    }

    #[test]
    fn leave_group_emits_topology_changed_when_subscribed() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_topology().unwrap(); // required before the pump for the emit
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        w.leave_group(&SpeakerId::new("RINCON_DINING")).unwrap();
        assert!(matches!(
            rx.recv_timeout(std::time::Duration::from_millis(100))
                .unwrap(),
            ChangeEvent::TopologyChanged
        ));
    }

    #[test]
    fn push_topology_change_delivers_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_topology().unwrap(); // required before the pump for the emit
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        w.push_topology_change();
        assert!(matches!(
            rx.recv_timeout(std::time::Duration::from_millis(100))
                .unwrap(),
            ChangeEvent::TopologyChanged
        ));
    }

    // ── v0.5.1 group form/break ───────────────────────────────────────────

    /// join_group updates `speaker`'s coordinator mapping so its
    /// `speaker_state` transport now reflects the target coordinator (D2).
    #[test]
    fn join_group_updates_membership() {
        let w = MockWire::default();
        let office = SpeakerId::new("RINCON_OFFICE"); // solo group coordinator
        let kitchen = SpeakerId::new("RINCON_KITCHEN"); // another group's coordinator

        // Office joins Kitchen's group; a refresh commits the regroup to the
        // routing cache (deferred like SonosWire); then play Kitchen and confirm
        // Office's transport now follows the Kitchen coordinator (D2 routing).
        w.join_group(&office, &kitchen).unwrap();
        w.refresh_topology().unwrap();
        w.play(&GroupId::new("RINCON_KITCHEN:1")).unwrap();
        let st = w.speaker_state(&office).unwrap();
        assert_eq!(
            st.transport.unwrap().state,
            PlaybackState::Playing,
            "after join, Office's transport must follow the Kitchen coordinator (D2)"
        );
    }

    /// join_group dissolves the joiner's former solo group from `coords`.
    #[test]
    fn join_group_dissolves_empty_source_group() {
        let w = MockWire::default();
        let office = SpeakerId::new("RINCON_OFFICE");
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        w.join_group(&office, &kitchen).unwrap();
        w.refresh_topology().unwrap(); // commit the regroup to the routing cache
        // The old solo group (RINCON_OFFICE:0) must no longer route, while
        // the Kitchen group is unaffected.
        assert_eq!(
            w.play(&GroupId::new("RINCON_OFFICE:0")),
            Err(WireError::NotFound("RINCON_OFFICE:0".into())),
            "joiner's former solo group must dissolve"
        );
        assert!(w.play(&GroupId::new("RINCON_KITCHEN:1")).is_ok());
    }

    /// leave_group makes `speaker` its own standalone coordinator.
    #[test]
    fn leave_group_makes_standalone() {
        let w = MockWire::default();
        let dining = SpeakerId::new("RINCON_DINING"); // member of Kitchen group, not coordinator
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        // Before: Dining follows Kitchen. Play Kitchen → Dining shows Playing.
        w.play(&GroupId::new("RINCON_KITCHEN:1")).unwrap();
        assert_eq!(
            w.speaker_state(&dining).unwrap().transport.unwrap().state,
            PlaybackState::Playing
        );

        // Dining leaves → its own standalone group; its transport now comes
        // from itself (Stopped seed), independent of Kitchen. A refresh commits
        // the regroup to the routing cache (deferred like SonosWire).
        w.leave_group(&dining).unwrap();
        w.refresh_topology().unwrap();
        assert_eq!(
            w.speaker_state(&dining).unwrap().transport.unwrap().state,
            PlaybackState::Stopped,
            "after leave, Dining's transport is its own (no longer Kitchen's)"
        );
        // The fresh solo group routes.
        assert!(
            w.play(&GroupId::new("RINCON_DINING:0")).is_ok(),
            "leave creates a routable standalone group for the leaver"
        );
        // Kitchen's own group still works for its coordinator.
        let _ = kitchen;
        assert!(w.play(&GroupId::new("RINCON_KITCHEN:1")).is_ok());
    }

    // ── v0.6.3 fidelity: deferred grouping + gated TopologyChanged ─────────

    /// #1: a regroup does NOT change command routing until a
    /// `refresh_topology()`/`discover()` re-pull commits it (mirrors SonosWire's
    /// caches only updating on a `GetZoneGroupState` re-pull). Before the
    /// refresh the joiner's old solo group still routes; after it, the new
    /// grouping takes effect.
    #[test]
    fn regroup_routing_is_deferred_until_refresh() {
        let w = MockWire::default();
        w.discover().unwrap();
        let office = SpeakerId::new("RINCON_OFFICE");
        let kitchen = SpeakerId::new("RINCON_KITCHEN");

        w.join_group(&office, &kitchen).unwrap();
        assert!(
            w.play(&GroupId::new("RINCON_OFFICE:0")).is_ok(),
            "before refresh, the joiner's old group still routes (deferred like SonosWire)"
        );

        w.refresh_topology().unwrap();
        assert_eq!(
            w.play(&GroupId::new("RINCON_OFFICE:0")),
            Err(WireError::NotFound("RINCON_OFFICE:0".into())),
            "after refresh, the joiner's old group no longer routes"
        );
    }

    /// #3: `discover()` and `refresh_topology()` agree after a regroup - both
    /// re-pull the CURRENT grouping (discover() no longer returns the stale
    /// original fixture).
    #[test]
    fn discover_reflects_regroup_like_refresh() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.join_group(
            &SpeakerId::new("RINCON_OFFICE"),
            &SpeakerId::new("RINCON_KITCHEN"),
        )
        .unwrap();

        let via_discover = w.discover().unwrap();
        let via_refresh = w.refresh_topology().unwrap();
        assert_eq!(
            via_discover.groups, via_refresh.groups,
            "discover() and refresh_topology() must agree on the current grouping"
        );
        assert!(
            !via_discover
                .groups
                .iter()
                .any(|g| g.id == GroupId::new("RINCON_OFFICE:0")),
            "discover() reflects the regroup (Office folded into Kitchen), not the stale fixture"
        );
    }

    /// #4: without `subscribe_topology`, a regroup must NOT emit
    /// `TopologyChanged` (the real `GroupMembership` watch was never
    /// registered, so the NOTIFY never arrives).
    #[test]
    fn regroup_does_not_emit_topology_changed_without_subscription() {
        let w = MockWire::default();
        w.discover().unwrap();
        // subscribe_speakers WITHOUT subscribe_topology → no topology watch.
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);

        w.join_group(
            &SpeakerId::new("RINCON_OFFICE"),
            &SpeakerId::new("RINCON_KITCHEN"),
        )
        .unwrap();

        assert!(
            rx.recv_timeout(std::time::Duration::from_millis(50))
                .is_err(),
            "no TopologyChanged without a topology subscription"
        );
    }

    // ── v0.5.1 group volume/mute ──────────────────────────────────────────

    #[test]
    fn set_group_volume_auto_emits() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let g = GroupId::new("RINCON_KITCHEN:1");
        w.set_group_volume(&g, Volume::new(65).unwrap()).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::GroupVolume { group, volume } => {
                assert_eq!(group, g);
                assert_eq!(volume, Volume::new(65).unwrap());
            }
            other => panic!("expected GroupVolume from set_group_volume, got {other:?}"),
        }
    }

    #[test]
    fn set_group_mute_auto_emits() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        let _ = drain_seeds(&rx);
        let g = GroupId::new("RINCON_OFFICE:0");
        w.set_group_mute(&g, true).unwrap();
        match rx
            .recv_timeout(std::time::Duration::from_millis(100))
            .unwrap()
        {
            ChangeEvent::GroupMute { group, muted } => {
                assert_eq!(group, g);
                assert!(muted);
            }
            other => panic!("expected GroupMute from set_group_mute, got {other:?}"),
        }
    }

    #[test]
    fn set_group_volume_unknown_group_not_found() {
        let w = MockWire::default();
        assert_eq!(
            w.set_group_volume(&GroupId::new("RINCON_GHOST:0"), Volume::new(50).unwrap()),
            Err(WireError::NotFound("RINCON_GHOST:0".into()))
        );
        assert_eq!(
            w.set_group_mute(&GroupId::new("RINCON_GHOST:0"), true),
            Err(WireError::NotFound("RINCON_GHOST:0".into()))
        );
    }

    #[test]
    fn set_group_volume_honors_command_error_on_coordinator() {
        let w = MockWire::default();
        let kitchen = SpeakerId::new("RINCON_KITCHEN"); // coordinator of RINCON_KITCHEN:1
        w.set_command_error(&kitchen, WireError::Network("unreachable".into()));
        assert_eq!(
            w.set_group_volume(&GroupId::new("RINCON_KITCHEN:1"), Volume::new(50).unwrap()),
            Err(WireError::Network("unreachable".into()))
        );
        // set_group_mute routes to the same coordinator → same forced error.
        assert_eq!(
            w.set_group_mute(&GroupId::new("RINCON_KITCHEN:1"), true),
            Err(WireError::Network("unreachable".into()))
        );
    }

    #[test]
    fn join_group_unknown_speaker_is_not_found() {
        let w = MockWire::default();
        assert_eq!(
            w.join_group(
                &SpeakerId::new("RINCON_NOPE"),
                &SpeakerId::new("RINCON_KITCHEN")
            ),
            Err(WireError::NotFound("RINCON_NOPE".into()))
        );
    }

    #[test]
    fn join_group_unknown_coordinator_is_not_found() {
        let w = MockWire::default();
        assert_eq!(
            w.join_group(
                &SpeakerId::new("RINCON_OFFICE"),
                &SpeakerId::new("RINCON_NOPE")
            ),
            Err(WireError::NotFound("RINCON_NOPE".into()))
        );
    }

    #[test]
    fn leave_group_unknown_speaker_is_not_found() {
        let w = MockWire::default();
        assert_eq!(
            w.leave_group(&SpeakerId::new("RINCON_NOPE")),
            Err(WireError::NotFound("RINCON_NOPE".into()))
        );
    }

    #[test]
    fn join_group_honors_command_error() {
        let w = MockWire::default();
        let office = SpeakerId::new("RINCON_OFFICE");
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        w.set_command_error(&office, WireError::Network("unreachable".into()));
        assert_eq!(
            w.join_group(&office, &kitchen),
            Err(WireError::Network("unreachable".into()))
        );
    }

    #[test]
    fn leave_group_honors_command_error() {
        let w = MockWire::default();
        let dining = SpeakerId::new("RINCON_DINING");
        w.set_command_error(&dining, WireError::Network("unreachable".into()));
        assert_eq!(
            w.leave_group(&dining),
            Err(WireError::Network("unreachable".into()))
        );
    }

    #[test]
    fn leave_group_reelects_members_left_behind() {
        // Kitchen COORDINATES [Kitchen, Dining]. When the coordinator leaves,
        // the remaining member must be re-homed (off Kitchen) - never left
        // pointing at the departed coordinator (an impossible topology).
        let w = MockWire::default();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let dining = SpeakerId::new("RINCON_DINING");

        // Kitchen playing → Dining (follower) reflects it via D2.
        w.play(&GroupId::new("RINCON_KITCHEN:1")).unwrap();
        assert_eq!(
            w.speaker_state(&dining).unwrap().transport.unwrap().state,
            PlaybackState::Playing
        );

        // The coordinator leaves. Dining must now read its OWN state (Stopped
        // seed), proving it was re-homed off Kitchen rather than orphaned
        // still pointing at the now-departed Kitchen.
        w.leave_group(&kitchen).unwrap();
        w.refresh_topology().unwrap(); // commit the regroup to the routing cache
        assert_eq!(
            w.speaker_state(&dining).unwrap().transport.unwrap().state,
            PlaybackState::Stopped,
            "a left-behind member must be re-homed off the departed coordinator"
        );
    }

    #[test]
    fn join_group_reelects_old_group_when_coordinator_moves() {
        // Kitchen COORDINATES [Kitchen, Dining]. When Kitchen joins Office's
        // group, the left-behind Dining must be re-homed - not left pointing
        // at Kitchen, which now follows Office.
        let w = MockWire::default();
        let kitchen = SpeakerId::new("RINCON_KITCHEN");
        let dining = SpeakerId::new("RINCON_DINING");
        let office = SpeakerId::new("RINCON_OFFICE");

        w.play(&GroupId::new("RINCON_KITCHEN:1")).unwrap(); // Kitchen playing, Dining follows
        w.join_group(&kitchen, &office).unwrap(); // Kitchen now follows Office
        w.refresh_topology().unwrap(); // commit the regroup to the routing cache

        // Dining is re-homed off Kitchen → independent → its own Stopped seed.
        assert_eq!(
            w.speaker_state(&dining).unwrap().transport.unwrap().state,
            PlaybackState::Stopped,
            "left-behind member must be re-homed when its coordinator joins elsewhere"
        );
        // Kitchen now follows Office (D2): playing Office's group makes Kitchen Playing.
        w.play(&GroupId::new("RINCON_OFFICE:0")).unwrap();
        assert_eq!(
            w.speaker_state(&kitchen).unwrap().transport.unwrap().state,
            PlaybackState::Playing,
            "the moved coordinator now follows its new group (Office)"
        );
    }

    // ── v0.6.1 track_position ─────────────────────────────────────────────

    #[test]
    fn track_position_unknown_group_is_not_found() {
        let wire = MockWire::default();
        let r = wire.track_position(&GroupId::new("nope"));
        assert!(matches!(r, Err(WireError::NotFound(_))));
    }

    #[test]
    fn track_position_reads_coordinator_position_and_duration() {
        use std::time::Duration;

        use oto_core::Track;

        let wire = MockWire::default();
        // Seed the Kitchen coordinator's transport with a known position and a
        // current_track carrying a known duration - directly via the private
        // model (test-internal access, same module).
        {
            let mut guard = lock!(wire);
            let kitchen = SpeakerId::new("RINCON_KITCHEN");
            let entry = guard.speakers.get_mut(&kitchen).unwrap();
            entry.transport = Some(TransportState {
                state: PlaybackState::Playing,
                current_track: Some(Track {
                    id: None,
                    title: None,
                    artist: None,
                    album: None,
                    track_number: None,
                    duration: Some(Duration::from_secs(200)),
                    art_uri: None,
                    uri: None,
                }),
                position: Some(Duration::from_secs(42)),
            });
        }
        let pos = wire
            .track_position(&GroupId::new("RINCON_KITCHEN:1"))
            .unwrap();
        assert_eq!(
            pos.position,
            Some(Duration::from_secs(42)),
            "position must come from coordinator's transport.position"
        );
        assert_eq!(
            pos.duration,
            Some(Duration::from_secs(200)),
            "duration must come from coordinator's transport.current_track.duration"
        );
    }
}
