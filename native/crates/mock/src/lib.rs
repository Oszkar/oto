#![deny(unsafe_code)]

//! Deterministic in-memory `Wire` for tests — no network. Integration
//! tests drive these fixtures so v0.1 discovery is provable without a LAN.
//!
//! `MockWire::default()` seeds a stateful per-speaker model (volume, mute,
//! transport) from the fixture topology. Commands (`set_volume`, `pause`, …)
//! mutate that model; `speaker_state` reads it back — no real Sonos required.

use std::{
    collections::HashMap,
    net::{IpAddr, Ipv4Addr},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
        Mutex,
    },
};

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, GroupIdentity, PlaybackState, SpeakerId,
    SpeakerIdentity, SpeakerState, TransportState, Volume, Wire, WireError,
};

// ── Internal model ───────────────────────────────────────────────────────────

/// Per-speaker mutable state held inside the `Mutex`.
struct Model {
    speakers: HashMap<SpeakerId, SpeakerState>,
    /// group coordinator lookup: `GroupId` → coordinator `SpeakerId`.
    coords: HashMap<GroupId, SpeakerId>,
    /// member → coordinator lookup: every speaker maps to its group coordinator
    /// (solo speaker maps to itself). Used by `speaker_state` to implement D2
    /// semantics: own volume/mute + coordinator's transport.
    member_to_coord: HashMap<SpeakerId, SpeakerId>,
    /// Sender half of the v0.4 unified event channel. Lazy-init: only
    /// populated by `subscribe_speakers`. `None` ↔ "no pump active".
    tx: Option<Sender<ChangeEvent>>,
    /// Receiver half — taken once via `take_event_stream`.
    rx: Option<Receiver<ChangeEvent>>,
}

/// Volume every speaker is seeded at. Shared by `Model::seeded` and the
/// `seeded_state_initial_values` test so the invariant can't silently drift.
const SEED_VOLUME: u8 = 30;

impl Model {
    fn empty() -> Self {
        Self {
            speakers: HashMap::new(),
            coords: HashMap::new(),
            member_to_coord: HashMap::new(),
            tx: None,
            rx: None,
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
        let mut coords = HashMap::new();
        for g in &snap.groups {
            coords.insert(g.id.clone(), g.coordinator.clone());
        }
        let mut member_to_coord = HashMap::new();
        for g in &snap.groups {
            for m in &g.members {
                member_to_coord.insert(m.clone(), g.coordinator.clone());
            }
        }
        Self {
            speakers,
            coords,
            member_to_coord,
            tx: None,
            rx: None,
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
/// acknowledged by the caller — per /codex review on PR #43, finding P2 #4.
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
}

impl Wire for MockWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        let result = self.outcome.clone();
        if result.is_ok() {
            // Flip the lifecycle gate so `subscribe_speakers` can succeed.
            // Idempotent: repeat discovers stay `true`. Failed discoveries
            // (the `failing()` constructor) leave it `false`.
            self.discovered.store(true, Ordering::SeqCst);
        }
        result
    }

    fn play(&self, group: &GroupId) -> Result<(), WireError> {
        let mut guard = lock!(self);
        let coord = guard
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        let entry = guard
            .speakers
            .get_mut(&coord)
            .ok_or_else(|| WireError::NotFound(coord.to_string()))?;
        // Keep the loaded track (Sonos retains it across pause/stop); clear
        // position — the mock has no playhead, and the Task 6 e2e asserts
        // transport.state, not position.
        let prev_track = entry.transport.take().and_then(|t| t.current_track);
        entry.transport = Some(TransportState {
            state: PlaybackState::Playing,
            current_track: prev_track,
            position: None,
        });
        Ok(())
    }

    fn pause(&self, group: &GroupId) -> Result<(), WireError> {
        let mut guard = lock!(self);
        let coord = guard
            .coords
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
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
        Ok(())
    }

    fn next(&self, group: &GroupId) -> Result<(), WireError> {
        let guard = lock!(self);
        guard
            .coords
            .get(group)
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        Ok(())
    }

    fn previous(&self, group: &GroupId) -> Result<(), WireError> {
        let guard = lock!(self);
        guard
            .coords
            .get(group)
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        Ok(())
    }

    fn set_volume(&self, speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
        let mut guard = lock!(self);
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
        let entry = guard
            .speakers
            .get_mut(speaker)
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))?;
        entry.muted = Some(muted);
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
        // (solo speaker = its own coordinator → own transport).
        let coord = guard.member_to_coord.get(speaker).cloned();
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

    fn subscribe_speakers(&self) -> Result<(), WireError> {
        // Match the real-wire contract: subscription requires a prior
        // successful `discover()`. The pre-seeded fixture in
        // `MockWire::default()` doesn't count as discovery — the caller
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
        // Seed: one Volume event per known speaker carrying its
        // current cached volume (mirrors the real cold-start NOTIFY).
        let seeds: Vec<ChangeEvent> = guard
            .speakers
            .iter()
            .filter_map(|(sid, st)| {
                st.volume.map(|v| ChangeEvent::Volume {
                    speaker: sid.clone(),
                    volume: v,
                })
            })
            .collect();
        for ev in seeds {
            // Pre-pump send — receiver is buffered, so this can't fail.
            let _ = tx.send(ev);
        }
        guard.tx = Some(tx);
        guard.rx = Some(rx);
        Ok(())
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
    /// fix for /codex review P2 #4 — the previous `speakers.is_empty()`
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

    #[test]
    fn subscribe_emits_seed_volume_per_speaker() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().expect("first take returns Some");
        // Fixture has 3 speakers → 3 seed Volume events.
        let mut seen = std::collections::HashSet::new();
        for _ in 0..3 {
            match rx.recv_timeout(std::time::Duration::from_millis(100)) {
                Ok(ChangeEvent::Volume { speaker, .. }) => {
                    seen.insert(speaker);
                }
                other => panic!("expected Volume seed, got {other:?}"),
            }
        }
        assert_eq!(seen.len(), 3, "one Volume seed per speaker");
    }

    #[test]
    fn set_volume_auto_emits_volume_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        // Drain the 3 seed events.
        for _ in 0..3 {
            rx.recv().unwrap();
        }
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
    fn push_event_surfaces_arbitrary_event() {
        let w = MockWire::default();
        w.discover().unwrap();
        w.subscribe_speakers().unwrap();
        let rx = w.take_event_stream().unwrap();
        for _ in 0..3 {
            rx.recv().unwrap();
        } // drain seeds
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
}
