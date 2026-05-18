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
    sync::Mutex,
};

use oto_core::{
    DiscoverySnapshot, GroupId, GroupIdentity, PlaybackState, SpeakerId, SpeakerIdentity,
    SpeakerState, TransportState, Volume, Wire, WireError,
};

// ── Internal model ───────────────────────────────────────────────────────────

/// Per-speaker mutable state held inside the `Mutex`.
struct Model {
    speakers: HashMap<SpeakerId, SpeakerState>,
    /// group coordinator lookup: `GroupId` → coordinator `SpeakerId`.
    coords: HashMap<GroupId, SpeakerId>,
}

impl Model {
    fn empty() -> Self {
        Self {
            speakers: HashMap::new(),
            coords: HashMap::new(),
        }
    }

    fn seeded(snap: &DiscoverySnapshot) -> Self {
        let mut speakers = HashMap::new();
        for s in &snap.speakers {
            speakers.insert(
                s.id.clone(),
                SpeakerState {
                    volume: Some(Volume::new(30).expect("30 is valid")),
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
        Self { speakers, coords }
    }
}

// ── MockWire ─────────────────────────────────────────────────────────────────

/// A `Wire` that yields a fixed topology (or a fixed error) and maintains
/// per-speaker state so command→state round-trips are testable without a LAN.
pub struct MockWire {
    outcome: Result<DiscoverySnapshot, WireError>,
    state: Mutex<Model>,
}

impl MockWire {
    /// A `Wire` that fails discovery with `err`; commands return `NotFound`
    /// because the model is empty (nothing was seeded).
    pub fn failing(err: WireError) -> Self {
        Self {
            outcome: Err(err),
            state: Mutex::new(Model::empty()),
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
        Self {
            outcome: Ok(snap),
            state: Mutex::new(model),
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

impl Wire for MockWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        self.outcome.clone()
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
        guard
            .speakers
            .get(speaker)
            .cloned()
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))
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
        assert_eq!(state.volume, Some(Volume::new(30).unwrap()));
        assert_eq!(state.muted, Some(false));
        assert_eq!(state.transport.unwrap().state, PlaybackState::Stopped);
    }
}
