//! Path A event pipeline: wraps `sonos-sdk-state` + `sonos-sdk-event-manager`
//! into one OS pump thread that maps upstream property events to
//! `oto_core::ChangeEvent` and pushes them onto an unbounded
//! `std::sync::mpsc::Sender<ChangeEvent>`. The matching `Receiver` is
//! handed out via `SonosWire::take_event_stream`.
//!
//! Per `docs/superpowers/specs/2026-05-21-v0.4-live-property-events-design.md`
//! § 4 "Concrete shapes" + § 7 "Threading and locking":
//!   - One thread total (not per-speaker).
//!   - AVTransport NOTIFYs filtered to coordinator-only; emitted with
//!     `GroupId` addressing via the wire's discover-built map.
//!   - `Position` is NOT watched (spike finding #7 — polling-derived).
//!
//! Per `docs/sonos-notes.md` § Event model (spike finding "Bare
//! `StateManager::new()` is an ergonomic footgun") — we use
//! `watch_property_with_subscription::<P>(&sid)` only after attaching a
//! `SonosEventManager` via the builder. The bare `::new()` path
//! registers watches silently with no UPnP SUBSCRIBE.

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::{
        mpsc::{self, Receiver, Sender},
        Arc,
    },
    thread::JoinHandle,
};

use oto_core::{ChangeEvent, GroupId, SpeakerId, WireError};

/// Inputs the pump needs from the wire's discover-built caches.
///
/// Built by `SonosWire::snapshot_for_pump` from the wire's
/// interior-mutable cache state. Passed by value into `EventPump::spawn`.
pub(crate) struct PumpInputs {
    /// All speakers to watch (from the discover snapshot). IP is needed
    /// so the SDK can SUBSCRIBE the right device.
    pub(crate) speaker_ips: HashMap<SpeakerId, IpAddr>,
    /// Group coordinator id → group id, used to emit per-group
    /// `Playback`/`Track` events with the right `GroupId`.
    pub(crate) coord_to_group: HashMap<SpeakerId, GroupId>,
    /// Speaker → coordinator map (every speaker maps to its group's
    /// coordinator; a coordinator maps to itself). Used to drop
    /// AVTransport events from non-coordinators.
    pub(crate) speaker_to_coord: HashMap<SpeakerId, SpeakerId>,
    /// Friendly room names per speaker, used only to build the
    /// `sonos_discovery::Device` records the SDK needs in `add_devices`.
    pub(crate) speaker_names: HashMap<SpeakerId, String>,
}

/// Owns the pump thread + the upstream `StateManager` keepalive.
///
/// Constructed inside `SonosWire::subscribe_speakers`. Dropped when
/// the wire is replaced (next `discover_with`) — `Drop` releases the
/// manager (closing the SDK's event channel) and then joins the pump
/// thread.
pub(crate) struct EventPump {
    /// Set only while the thread is live. Cleared in `Drop` before join.
    handle: Option<JoinHandle<()>>,
    /// Keepalive for the SDK's `StateManager`. Holding it keeps the
    /// SDK's event worker alive; dropping it closes the worker's event
    /// channel, which causes `ChangeIterator::recv()` to return `None`
    /// and the pump thread to exit.
    ///
    /// Wrapped in `Option` so `Drop` can take ownership and release it
    /// BEFORE joining the pump thread (the pump thread holds its own
    /// clone of the manager; both must drop before the channel closes,
    /// but releasing ours first is necessary on the lock-step path).
    keepalive: Option<sonos_state::StateManager>,
}

impl EventPump {
    /// Spawn the pump thread + start watching `Volume` + `Mute` per
    /// speaker, `PlaybackState` + `CurrentTrack` per coordinator.
    ///
    /// Returns the pump (which owns the keepalive + JoinHandle) and the
    /// `Receiver` to be handed out via `take_event_stream`.
    ///
    /// `NoSpeakersDiscovered` if `inputs.speaker_ips` is empty.
    /// `Backend` if the SDK fails to construct.
    pub(crate) fn spawn(inputs: PumpInputs) -> Result<(Self, Receiver<ChangeEvent>), WireError> {
        if inputs.speaker_ips.is_empty() {
            return Err(WireError::NoSpeakersDiscovered);
        }

        let (tx, rx) = mpsc::channel::<ChangeEvent>();

        // Build the upstream manager with the event manager attached.
        // Per spike finding "ergonomic footgun": MUST use the builder
        // path. Bare `StateManager::new()` registers watches silently
        // with no UPnP SUBSCRIBE.
        let em =
            Arc::new(sonos_event_manager::SonosEventManager::new().map_err(|e| {
                WireError::Backend(format!("sonos-event-manager init failed: {e}"))
            })?);
        let manager = sonos_state::StateManager::builder()
            .with_event_manager(Arc::clone(&em))
            .build()
            .map_err(|e| WireError::Backend(format!("StateManager build failed: {e}")))?;

        // Register every discovered speaker with the SDK. The SDK uses
        // `sonos_discovery::Device` records (string IP + port) — we
        // reconstruct from our own discover snapshot rather than running
        // the SDK's own broken-on-multi-NIC SSDP (sonos-notes § "own SSDP"
        // + tatimblin/sonos-sdk#76).
        let devices: Vec<sonos_event_manager::Device> = inputs
            .speaker_ips
            .iter()
            .map(|(sid, ip)| sonos_event_manager::Device {
                id: sid.as_str().to_string(),
                name: inputs
                    .speaker_names
                    .get(sid)
                    .cloned()
                    .unwrap_or_else(|| sid.as_str().to_string()),
                room_name: inputs
                    .speaker_names
                    .get(sid)
                    .cloned()
                    .unwrap_or_else(|| sid.as_str().to_string()),
                ip_address: ip.to_string(),
                port: 1400,
                model_name: String::new(),
            })
            .collect();

        manager
            .add_devices(devices)
            .map_err(|e| WireError::Backend(format!("StateManager add_devices failed: {e}")))?;

        // Register per-(speaker × property) watches. The SDK's first
        // NOTIFY per subscription seeds the cache (sonos-notes § "the
        // initial SUBSCRIBE NOTIFY *is* the seed probe"). Per-speaker
        // failures emit `SubscriptionError` and don't abort.
        register_watches(&manager, &inputs, &tx);

        // Clone the manager for the pump thread. `StateManager: Clone`
        // is internally Arc-backed (see sonos-sdk-state source) — the
        // thread + the keepalive both observe the same SDK worker.
        let manager_for_thread = manager.clone();
        let coord_to_group = inputs.coord_to_group.clone();
        let speaker_to_coord = inputs.speaker_to_coord.clone();
        let tx_for_thread = tx.clone();
        let handle = std::thread::Builder::new()
            .name("oto-wire-event-pump".into())
            .spawn(move || {
                pump_loop(
                    manager_for_thread,
                    coord_to_group,
                    speaker_to_coord,
                    tx_for_thread,
                );
            })
            .map_err(|e| WireError::Backend(format!("event pump thread spawn failed: {e}")))?;

        // Drop the original `tx`. The pump thread owns its own clone;
        // when the thread exits (because the iterator returns None),
        // all senders are gone and the receiver wakes.
        drop(tx);

        let pump = EventPump {
            handle: Some(handle),
            keepalive: Some(manager),
        };
        Ok((pump, rx))
    }
}

impl Drop for EventPump {
    fn drop(&mut self) {
        // Release our keepalive on the SDK manager BEFORE joining the
        // pump thread. The pump thread also holds a manager clone; the
        // SDK's event channel closes only when the LAST clone is
        // dropped. If we joined first while still holding our clone,
        // the channel would stay open and the pump thread would block
        // forever on `iter.recv()`.
        //
        // Drop order: release keepalive (one clone gone) → join pump
        // (thread's own clone goes out of scope at thread-exit, which
        // happens once `iter.recv()` returns None, which happens once
        // the LAST clone — ours, just released — is gone).
        let _ = self.keepalive.take();
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

/// Register every per-(speaker × property) watch via the SDK's
/// `watch_property_with_subscription` (the safe path per spike finding
/// "ergonomic footgun"). Per-speaker failures surface as
/// `ChangeEvent::SubscriptionError` and don't abort the registration
/// loop — the spec's contract is "stream stays alive across
/// recoverable upstream blips".
fn register_watches(
    manager: &sonos_state::StateManager,
    inputs: &PumpInputs,
    tx: &Sender<ChangeEvent>,
) {
    use sonos_state::{CurrentTrack, Mute, PlaybackState, Volume};

    let sdk_id = |sid: &SpeakerId| sonos_state::SpeakerId::new(sid.as_str());

    for sid in inputs.speaker_ips.keys() {
        let sdk_sid = sdk_id(sid);

        if let Err(e) = manager.watch_property_with_subscription::<Volume>(&sdk_sid) {
            let _ = tx.send(ChangeEvent::SubscriptionError {
                speaker: sid.clone(),
                message: format!("watch Volume: {e}"),
            });
        }
        if let Err(e) = manager.watch_property_with_subscription::<Mute>(&sdk_sid) {
            let _ = tx.send(ChangeEvent::SubscriptionError {
                speaker: sid.clone(),
                message: format!("watch Mute: {e}"),
            });
        }

        // AVTransport-scoped properties live on the coordinator only.
        // Registering on coordinators (not every speaker) keeps the
        // watched-set minimal; the SDK's PerCoordinator routing
        // (`resolve_subscription_target`) would coalesce anyway, but
        // the explicit gate is cheap and clearer.
        if inputs.coord_to_group.contains_key(sid) {
            if let Err(e) = manager.watch_property_with_subscription::<PlaybackState>(&sdk_sid) {
                let _ = tx.send(ChangeEvent::SubscriptionError {
                    speaker: sid.clone(),
                    message: format!("watch PlaybackState: {e}"),
                });
            }
            if let Err(e) = manager.watch_property_with_subscription::<CurrentTrack>(&sdk_sid) {
                let _ = tx.send(ChangeEvent::SubscriptionError {
                    speaker: sid.clone(),
                    message: format!("watch CurrentTrack: {e}"),
                });
            }
        }
    }

    // NOTE: We deliberately do NOT watch `Position`. The spike found
    // Path A surfaces position as polling-derived ~2 s cadence; the UI
    // derives position locally from the last transport event +
    // wall-clock. See spike findings #7 / sonos-notes § Event model.
}

/// Map upstream `ChangeEvent`s to `oto_core::ChangeEvent`s and push to
/// the channel. Runs on the pump thread.
///
/// Exits when the SDK's `ChangeIterator::recv()` returns `None` — that
/// happens once the LAST `StateManager` clone is dropped (us + the
/// `EventPump`'s keepalive).
fn pump_loop(
    manager: sonos_state::StateManager,
    coord_to_group: HashMap<SpeakerId, GroupId>,
    speaker_to_coord: HashMap<SpeakerId, SpeakerId>,
    tx: Sender<ChangeEvent>,
) {
    let iter = manager.iter();
    while let Some(upstream) = iter.recv() {
        let speaker = SpeakerId::new(upstream.speaker_id.as_str());
        if let Some(event) = map_upstream_event(
            &manager,
            &upstream,
            &speaker,
            &coord_to_group,
            &speaker_to_coord,
        ) {
            if tx.send(event).is_err() {
                // Receiver gone — wire was dropped before us. Bail.
                return;
            }
        }
    }
}

/// Pure mapping: upstream `sonos_state::ChangeEvent` → optional
/// `oto_core::ChangeEvent`. Returns `None` if:
///   - the property key is unknown (we only handle 4)
///   - the property value isn't in the cache yet (cold-start race;
///     next NOTIFY will resend)
///   - AVTransport event from a non-coordinator (coordinator-only
///     filter — see `av_transport_group_id`)
fn map_upstream_event(
    manager: &sonos_state::StateManager,
    upstream: &sonos_state::ChangeEvent,
    speaker: &SpeakerId,
    coord_to_group: &HashMap<SpeakerId, GroupId>,
    speaker_to_coord: &HashMap<SpeakerId, SpeakerId>,
) -> Option<ChangeEvent> {
    use sonos_state::{CurrentTrack, Mute, PlaybackState as SdkPlaybackState, Volume};

    let sdk_sid = sonos_state::SpeakerId::new(speaker.as_str());

    match upstream.property_key {
        "volume" => {
            let v: Volume = manager.get_property::<Volume>(&sdk_sid)?;
            Some(volume_event(speaker.clone(), v))
        }
        "mute" => {
            let m: Mute = manager.get_property::<Mute>(&sdk_sid)?;
            Some(mute_event(speaker.clone(), m))
        }
        "playback_state" => {
            let group = av_transport_group_id(speaker, speaker_to_coord, coord_to_group)?;
            let s: SdkPlaybackState = manager.get_property::<SdkPlaybackState>(&sdk_sid)?;
            Some(ChangeEvent::Playback {
                group,
                state: map_playback_state(s),
            })
        }
        "current_track" => {
            let group = av_transport_group_id(speaker, speaker_to_coord, coord_to_group)?;
            let t: CurrentTrack = manager.get_property::<CurrentTrack>(&sdk_sid)?;
            Some(ChangeEvent::Track {
                group,
                track: map_current_track(t),
            })
        }
        // Any other property key (e.g. "position" if some future code
        // path registers it; topology keys in v0.5) is silently
        // dropped here. Document explicitly so the silence is intentional.
        _ => None,
    }
}

/// AVTransport coordinator-only filter — drop the event if `speaker`
/// is not its group's coordinator. Returns the `GroupId` to use as
/// the event's address when the event passes the filter.
///
/// Pure helper: no SDK touchpoint. Followers' AVTransport mirrors
/// their coordinator's; emitting from both would duplicate every
/// transport change per group member.
fn av_transport_group_id(
    speaker: &SpeakerId,
    speaker_to_coord: &HashMap<SpeakerId, SpeakerId>,
    coord_to_group: &HashMap<SpeakerId, GroupId>,
) -> Option<GroupId> {
    let coord = speaker_to_coord.get(speaker)?;
    if coord != speaker {
        // Not a coordinator — drop the AVTransport event.
        return None;
    }
    coord_to_group.get(coord).cloned()
}

/// SDK `PlaybackState` → `oto_core::PlaybackState`. One-to-one mapping;
/// kept as a fn for clarity and to localize any future shape drift.
fn map_playback_state(s: sonos_state::PlaybackState) -> oto_core::PlaybackState {
    match s {
        sonos_state::PlaybackState::Playing => oto_core::PlaybackState::Playing,
        sonos_state::PlaybackState::Paused => oto_core::PlaybackState::Paused,
        sonos_state::PlaybackState::Stopped => oto_core::PlaybackState::Stopped,
        sonos_state::PlaybackState::Transitioning => oto_core::PlaybackState::Transitioning,
    }
}

/// SDK `CurrentTrack` → `oto_core::Track`. The SDK shape is a strict
/// subset of ours: title/artist/album/album_art_uri/uri. The rest
/// (`id`, `track_number`, `duration`) the SDK doesn't carry on this
/// property — leave them `None`; the UI tolerates partial Tracks.
fn map_current_track(t: sonos_state::CurrentTrack) -> oto_core::Track {
    oto_core::Track {
        id: None,
        title: t.title,
        artist: t.artist,
        album: t.album,
        track_number: None,
        duration: None,
        art_uri: t.album_art_uri,
        uri: t.uri,
    }
}

/// SDK `Volume` → `oto_core::ChangeEvent::Volume` for `speaker`. The
/// SDK's `Volume::new` clamps at 100; `Volume::clamped` here is
/// belt-and-braces against any future shape drift.
fn volume_event(speaker: SpeakerId, v: sonos_state::Volume) -> ChangeEvent {
    ChangeEvent::Volume {
        speaker,
        volume: oto_core::Volume::clamped(i32::from(v.value())),
    }
}

/// SDK `Mute` → `oto_core::ChangeEvent::Mute` for `speaker`.
fn mute_event(speaker: SpeakerId, m: sonos_state::Mute) -> ChangeEvent {
    ChangeEvent::Mute {
        speaker,
        muted: m.is_muted(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sid(s: &str) -> SpeakerId {
        SpeakerId::new(s)
    }
    fn gid(s: &str) -> GroupId {
        GroupId::new(s)
    }

    // ── av_transport_group_id ─────────────────────────────────────────

    #[test]
    fn coordinator_passes_filter() {
        let kitchen = sid("RINCON_K");
        let mut s2c = HashMap::new();
        s2c.insert(kitchen.clone(), kitchen.clone());
        let mut c2g = HashMap::new();
        c2g.insert(kitchen.clone(), gid("RINCON_K:1"));
        assert_eq!(
            av_transport_group_id(&kitchen, &s2c, &c2g),
            Some(gid("RINCON_K:1")),
            "coordinator's AVTransport event must carry its group id",
        );
    }

    #[test]
    fn follower_dropped_by_filter() {
        let kitchen = sid("RINCON_K");
        let dining = sid("RINCON_D");
        let mut s2c = HashMap::new();
        s2c.insert(kitchen.clone(), kitchen.clone());
        s2c.insert(dining.clone(), kitchen.clone());
        let mut c2g = HashMap::new();
        c2g.insert(kitchen, gid("RINCON_K:1"));
        assert!(
            av_transport_group_id(&dining, &s2c, &c2g).is_none(),
            "non-coordinator AVTransport NOTIFY must be dropped (would \
             otherwise duplicate every transport change per group member)",
        );
    }

    #[test]
    fn unknown_speaker_dropped() {
        let s2c = HashMap::new();
        let c2g = HashMap::new();
        assert!(
            av_transport_group_id(&sid("RINCON_GHOST"), &s2c, &c2g).is_none(),
            "speaker absent from speaker_to_coord must drop the event",
        );
    }

    #[test]
    fn coordinator_with_no_group_mapping_dropped() {
        // Edge case: speaker_to_coord says "you are your own
        // coordinator" but coord_to_group is missing the entry. Without
        // the GroupId we can't address the event — drop it. Can happen
        // if discover() raced with a topology change.
        let solo = sid("RINCON_SOLO");
        let mut s2c = HashMap::new();
        s2c.insert(solo.clone(), solo.clone());
        let c2g: HashMap<SpeakerId, GroupId> = HashMap::new();
        assert!(
            av_transport_group_id(&solo, &s2c, &c2g).is_none(),
            "coordinator missing from coord_to_group must drop the event",
        );
    }

    // ── map_playback_state ────────────────────────────────────────────

    #[test]
    fn map_playback_state_round_trips_all_variants() {
        use sonos_state::PlaybackState as Sdk;
        assert_eq!(
            map_playback_state(Sdk::Playing),
            oto_core::PlaybackState::Playing,
        );
        assert_eq!(
            map_playback_state(Sdk::Paused),
            oto_core::PlaybackState::Paused,
        );
        assert_eq!(
            map_playback_state(Sdk::Stopped),
            oto_core::PlaybackState::Stopped,
        );
        assert_eq!(
            map_playback_state(Sdk::Transitioning),
            oto_core::PlaybackState::Transitioning,
        );
    }

    // ── map_current_track ─────────────────────────────────────────────

    #[test]
    fn map_current_track_carries_known_fields_and_leaves_unknowns_none() {
        let t = sonos_state::CurrentTrack {
            title: Some("Halcyon".into()),
            artist: Some("Orbital".into()),
            album: Some("Snivilisation".into()),
            album_art_uri: Some("http://example/art.jpg".into()),
            uri: Some("x-file-cifs://nas/halcyon.flac".into()),
        };
        let m = map_current_track(t);
        assert_eq!(m.title.as_deref(), Some("Halcyon"));
        assert_eq!(m.artist.as_deref(), Some("Orbital"));
        assert_eq!(m.album.as_deref(), Some("Snivilisation"));
        assert_eq!(m.art_uri.as_deref(), Some("http://example/art.jpg"));
        assert_eq!(m.uri.as_deref(), Some("x-file-cifs://nas/halcyon.flac"));
        // SDK doesn't carry these on CurrentTrack — must stay None.
        assert!(m.id.is_none());
        assert!(m.track_number.is_none());
        assert!(m.duration.is_none());
    }

    #[test]
    fn map_current_track_passes_through_radio_stream_partial() {
        // Radio streams typically arrive with only `uri` set; verify
        // the mapper doesn't fabricate metadata.
        let t = sonos_state::CurrentTrack {
            title: None,
            artist: None,
            album: None,
            album_art_uri: None,
            uri: Some("x-rincon-mp3radio://stream.example/live".into()),
        };
        let m = map_current_track(t);
        assert!(m.title.is_none());
        assert!(m.artist.is_none());
        assert!(m.album.is_none());
        assert!(m.art_uri.is_none());
        assert_eq!(
            m.uri.as_deref(),
            Some("x-rincon-mp3radio://stream.example/live"),
        );
    }

    // ── volume / mute event constructors ──────────────────────────────

    #[test]
    fn volume_event_clamps_and_carries_speaker_id() {
        let s = sid("RINCON_K");
        let ev = volume_event(s.clone(), sonos_state::Volume::new(73));
        match ev {
            ChangeEvent::Volume { speaker, volume } => {
                assert_eq!(speaker, s);
                assert_eq!(volume.get(), 73);
            }
            other => panic!("expected Volume, got {other:?}"),
        }
    }

    #[test]
    fn volume_event_clamps_at_100() {
        // sonos_state::Volume::new already clamps at 100, but verify
        // the boundary survives the round-trip.
        let s = sid("RINCON_K");
        let ev = volume_event(s, sonos_state::Volume::new(255));
        let ChangeEvent::Volume { volume, .. } = ev else {
            panic!("expected Volume")
        };
        assert_eq!(volume.get(), 100);
    }

    #[test]
    fn mute_event_round_trips_both_bool_states() {
        let s = sid("RINCON_K");
        match mute_event(s.clone(), sonos_state::Mute::new(true)) {
            ChangeEvent::Mute { speaker, muted } => {
                assert_eq!(speaker, s);
                assert!(muted);
            }
            other => panic!("expected Mute, got {other:?}"),
        }
        match mute_event(s.clone(), sonos_state::Mute::new(false)) {
            ChangeEvent::Mute { speaker, muted } => {
                assert_eq!(speaker, s);
                assert!(!muted);
            }
            other => panic!("expected Mute, got {other:?}"),
        }
    }

    #[test]
    fn spawn_returns_no_speakers_error_when_inputs_empty() {
        let inputs = PumpInputs {
            speaker_ips: HashMap::new(),
            coord_to_group: HashMap::new(),
            speaker_to_coord: HashMap::new(),
            speaker_names: HashMap::new(),
        };
        let err = EventPump::spawn(inputs).err().expect("must error");
        assert!(matches!(err, WireError::NoSpeakersDiscovered));
    }
}
