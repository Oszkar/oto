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
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
        Arc,
    },
    thread::JoinHandle,
    time::Duration,
};

use oto_core::{ChangeEvent, GroupId, SpeakerId, WireError};

/// How often the pump thread checks the `stop` flag while waiting for an
/// upstream event. Doubles as the worst-case latency for `EventPump::Drop`
/// to join the pump thread. 250 ms is well under any human-perceptible
/// shutdown wait and well over typical event arrival cadence — the timeout
/// rarely fires on a busy LAN.
const POLL_INTERVAL: Duration = Duration::from_millis(250);

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

/// Owns the pump thread + the shared stop flag.
///
/// Constructed inside `SonosWire::subscribe_speakers`. Dropped when the
/// wire is replaced (next `discover()`); `Drop` signals the thread to
/// exit via `stop`, then joins. Worst-case join latency is one
/// `POLL_INTERVAL` (~250 ms).
///
/// **Shutdown design:** we do NOT rely on dropping a `StateManager`
/// "keepalive" to close the SDK's event channel. `StateManager::Clone`
/// fans out independent `mpsc::Sender`s (see
/// `sonos-sdk-state-0.5.2/src/state.rs:855`); the pump thread also
/// holds its own clone (via the `move` closure on the manager argument)
/// and would block forever on its own sender otherwise (Slice 3 review
/// finding C1). The poll-loop + atomic-stop pattern avoids the fan-out
/// trap entirely.
pub(crate) struct EventPump {
    /// Set only while the thread is live. Cleared in `Drop` before join.
    handle: Option<JoinHandle<()>>,
    /// Tells the pump thread to exit at its next poll boundary.
    stop: Arc<AtomicBool>,
}

impl EventPump {
    /// Spawn the pump thread + start watching `Volume` + `Mute` per
    /// speaker, `PlaybackState` + `CurrentTrack` per coordinator.
    ///
    /// Returns the pump (which owns the `JoinHandle` + stop flag) and
    /// the `Receiver` to be handed out via `take_event_stream`.
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

        // Install topology BEFORE registering watches. Without this,
        // the SDK's `resolve_subscription_target` for AVTransport
        // can't route subscriptions to coordinators — the watch is
        // registered but no UPnP SUBSCRIBE is sent, no NOTIFYs
        // arrive, no `PlaybackState` / `CurrentTrack` events ever
        // fire (RenderingControl works without topology because it's
        // a per-speaker subscription). This was Slice 3's first
        // hardware-test failure (PR #45 follow-up): operator
        // play/pause produced zero `ChangeEvent::Playback` on real
        // hardware because the SDK never subscribed to AVTransport
        // on the coordinator. sonos-notes § Event model documents
        // the required `manager.initialize(topology)` call as part
        // of the canonical builder pattern; the original Slice 3
        // build missed it.
        let topology = build_sdk_topology(&inputs);
        manager.initialize(topology);

        // Register per-(speaker × property) watches. The SDK's first
        // NOTIFY per subscription seeds the cache (sonos-notes § "the
        // initial SUBSCRIBE NOTIFY *is* the seed probe").
        //
        // We do NOT attempt to surface per-speaker subscription
        // failures here. The SDK at `=0.5.2` does not expose the
        // information — see `register_watches` for the full citation.
        // This is a known shortfall of the spec's "in-band per-speaker
        // failure surfacing" contract; tracked as v0.5 follow-up.
        register_watches(&manager, &inputs);

        // Move `manager` into the pump thread. The thread owns the
        // manager for its entire lifetime; when the thread exits, the
        // manager drops, which decrements the internal
        // `Arc<SonosEventManager>` refcount, and the SDK's event
        // worker shuts down naturally via its own `Drop` impl. The
        // local `em` Arc above also goes out of scope at the end of
        // this function — that's fine; the manager kept its own clone
        // via `with_event_manager`.
        let coord_to_group = inputs.coord_to_group.clone();
        let speaker_to_coord = inputs.speaker_to_coord.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let stop_for_thread = Arc::clone(&stop);
        let handle = std::thread::Builder::new()
            .name("oto-wire-event-pump".into())
            .spawn(move || {
                pump_loop(
                    manager,
                    coord_to_group,
                    speaker_to_coord,
                    tx,
                    stop_for_thread,
                );
            })
            .map_err(|e| WireError::Backend(format!("event pump thread spawn failed: {e}")))?;

        let pump = EventPump {
            handle: Some(handle),
            stop,
        };
        Ok((pump, rx))
    }
}

impl Drop for EventPump {
    fn drop(&mut self) {
        // Signal the pump thread to exit at its next poll boundary
        // (≤ POLL_INTERVAL). Then join.
        //
        // We do NOT try to wake the pump faster by calling
        // `event_manager().shutdown()` — the EventManager is owned by
        // the StateManager, which is owned by the pump thread. The
        // 250 ms worst-case join is well within any acceptable
        // shutdown latency for a desktop discover() cycle, and not
        // chasing the wake-up keeps the shutdown sequence simple and
        // failure-mode-free (no double-shutdown races).
        //
        // Why this works where the v0.4 Slice 3 original didn't:
        // `StateManager::Clone` fans out independent `mpsc::Sender`s
        // (state.rs:855). The previous design held a "keepalive"
        // manager clone in this struct AND moved another clone into
        // the pump thread, on the (mistaken) assumption that the SDK's
        // event channel would close when the keepalive dropped. It
        // wouldn't: the pump thread's own clone kept the channel
        // open, and the thread would block on `iter.recv()` forever,
        // self-deadlocking on its own sender clone. The atomic-stop +
        // recv_timeout polling avoids the trap entirely — the pump
        // thread is no longer waiting on its own sender.
        self.stop.store(true, Ordering::Release);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

/// Build the `sonos_state::Topology` payload required by
/// `manager.initialize(...)`. The SDK uses this to populate its
/// internal speaker + group store; `resolve_subscription_target`
/// then routes AVTransport subscriptions to coordinators correctly.
///
/// We reconstruct from `PumpInputs` rather than threading the raw
/// `DiscoverySnapshot` into events.rs — that would couple this module
/// to the wire's discovery internals. The maps in `PumpInputs` carry
/// everything needed: `speaker_ips` (id + ip), `speaker_names`
/// (display name; falls back to id), `coord_to_group` (groups), and
/// `speaker_to_coord` (inverted below to compute members per group).
///
/// Defaults for fields not exposed via `PumpInputs`: `port = 1400`
/// (Sonos's hardcoded UPnP port), `model_name = ""` (unknown
/// pre-discovery — Sonos ZGT doesn't carry it; `oto-core` has the
/// same gap, tracked as v0.5 model-repopulate work), `software_version
/// = "unknown"` (mirrors the SDK's own default in event_worker.rs:437),
/// `boot_seq = 0` (group-management seqs are v0.5 territory),
/// `satellites = vec![]` (bonded-satellite handling is v0.5).
fn build_sdk_topology(inputs: &PumpInputs) -> sonos_state::Topology {
    use sonos_state::model::{Speaker as SdkSpeaker, SpeakerInfo};
    use sonos_state::property::{GroupInfo, Topology};

    let speakers: Vec<SpeakerInfo> = inputs
        .speaker_ips
        .iter()
        .map(|(sid, ip)| {
            let name = inputs
                .speaker_names
                .get(sid)
                .cloned()
                .unwrap_or_else(|| sid.as_str().to_string());
            SdkSpeaker {
                id: sonos_state::SpeakerId::new(sid.as_str()),
                name: name.clone(),
                room_name: name,
                ip_address: *ip,
                port: 1400,
                model_name: String::new(),
                software_version: "unknown".to_string(),
                boot_seq: 0,
                satellites: vec![],
            }
        })
        .collect();

    // Invert speaker_to_coord to get members per group. For solo
    // speakers this trivially yields one-member groups; for grouped
    // speakers it yields the full membership list (load-bearing for
    // multi-speaker setups where the SDK needs to know every group
    // member, not just the coordinator).
    let mut members_by_group: HashMap<GroupId, Vec<sonos_state::SpeakerId>> = HashMap::new();
    for (speaker, coord) in &inputs.speaker_to_coord {
        if let Some(gid) = inputs.coord_to_group.get(coord) {
            members_by_group
                .entry(gid.clone())
                .or_default()
                .push(sonos_state::SpeakerId::new(speaker.as_str()));
        }
    }

    let groups: Vec<GroupInfo> = inputs
        .coord_to_group
        .iter()
        .map(|(coord, gid)| GroupInfo {
            id: sonos_state::GroupId::new(gid.as_str()),
            coordinator_id: sonos_state::SpeakerId::new(coord.as_str()),
            member_ids: members_by_group.get(gid).cloned().unwrap_or_default(),
        })
        .collect();

    Topology::new(speakers, groups)
}

/// Register every per-(speaker × property) watch via the SDK's
/// `watch_property_with_subscription` (the safe path per spike finding
/// "ergonomic footgun").
///
/// **No per-speaker error reporting (Slice 3 review finding I1).** The
/// SDK at `=0.5.2` does not expose per-speaker subscription failures:
///
///   - `watch_property_with_subscription::<P>` swallows
///     `ensure_service_subscribed` errors with `tracing::warn!` and
///     returns `Ok(...)`. See
///     `sonos-sdk-state-0.5.2/src/state.rs:610-633`.
///   - `ensure_service_subscribed` itself only fails if the broker's
///     command channel is closed; it returns `Ok` and queues a
///     `Subscribe` command for an async worker even when the target
///     device is unreachable. See
///     `sonos-sdk-event-manager-0.5.2/src/manager.rs:381-410`.
///   - `is_service_subscribed` is a ref-count check (true iff a
///     `Subscribe` command was *queued*), not a "device responded to
///     SUBSCRIBE" probe. See
///     `sonos-sdk-event-manager-0.5.2/src/manager.rs:497-502`.
///
/// The previous version of this fn carried `if let Err(e) = manager
/// .watch_property_with_subscription::<P>(...)` branches emitting
/// `ChangeEvent::SubscriptionError`; those branches were essentially
/// unreachable. They're gone. Honoring the spec's "in-band per-speaker
/// failure surfacing" contract requires either (a) an SDK feature we
/// don't have, or (b) a wire-side timeout-driven sweep we haven't
/// designed yet — tracked as v0.5 follow-up; until then a silent
/// failure manifests as the speaker's Volume/Mute/Playback events
/// simply never arriving (and the UI shows the last-known value).
fn register_watches(manager: &sonos_state::StateManager, inputs: &PumpInputs) {
    use sonos_state::{CurrentTrack, Mute, PlaybackState, Volume};

    let sdk_id = |sid: &SpeakerId| sonos_state::SpeakerId::new(sid.as_str());

    for sid in inputs.speaker_ips.keys() {
        let sdk_sid = sdk_id(sid);

        // RenderingControl-scoped: Volume + Mute. Both share one UPnP
        // subscription — registering both watches keeps the SDK
        // dispatch wired for each property key.
        let _ = manager.watch_property_with_subscription::<Volume>(&sdk_sid);
        let _ = manager.watch_property_with_subscription::<Mute>(&sdk_sid);

        // AVTransport-scoped properties live on the coordinator only.
        // Registering on coordinators (not every speaker) keeps the
        // watched-set minimal; the SDK's PerCoordinator routing
        // (`resolve_subscription_target`) would coalesce anyway, but
        // the explicit gate is cheap and clearer.
        if inputs.coord_to_group.contains_key(sid) {
            let _ = manager.watch_property_with_subscription::<PlaybackState>(&sdk_sid);
            let _ = manager.watch_property_with_subscription::<CurrentTrack>(&sdk_sid);
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
/// Exits when **either**:
///   - `EventPump::Drop` sets `stop` (worst-case `POLL_INTERVAL` later), or
///   - the downstream consumer drops `rx`, so our `tx.send` returns Err.
///
/// We deliberately do NOT rely on `iter.recv()` returning `None` to
/// drive shutdown — `StateManager::Clone` fans out independent
/// `mpsc::Sender`s and this thread holds one transitively (via its
/// `manager` argument). Blocking-recv would self-deadlock on our own
/// sender clone. See `EventPump::drop` for the longer explanation.
fn pump_loop(
    manager: sonos_state::StateManager,
    coord_to_group: HashMap<SpeakerId, GroupId>,
    speaker_to_coord: HashMap<SpeakerId, SpeakerId>,
    tx: Sender<ChangeEvent>,
    stop: Arc<AtomicBool>,
) {
    let iter = manager.iter();
    while !stop.load(Ordering::Acquire) {
        let Some(upstream) = iter.recv_timeout(POLL_INTERVAL) else {
            // Timeout fired — no event this poll cycle. The
            // "disconnect" case (all SDK senders dropped → channel
            // closed → recv_timeout returns None) is structurally
            // unreachable from inside this loop: the pump thread owns
            // the `manager` argument, which keeps the SDK event
            // channel's senders alive for the entire thread lifetime.
            // The only way out of the loop is `stop` flipping in
            // `EventPump::Drop`. Continue and re-check the flag.
            continue;
        };
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

    // ── EventPump construct/drop deadlock regression ──────────────────
    //
    // C1 regression coverage (Slice 3 review): the previous design
    // self-deadlocked in `EventPump::Drop` because the pump thread held
    // its own `StateManager::Clone` (= its own SDK event sender) and
    // blocked on `iter.recv()`, which only returns `None` when the
    // LAST sender drops. The thread couldn't drop its own sender until
    // it exited; it couldn't exit until the sender dropped. The fix
    // converts the loop to `recv_timeout` + an atomic stop flag.
    //
    // These tests use the REAL SDK with fake IPs. SUBSCRIBE attempts
    // will fail in the SDK's async worker (no real Sonos at the IP);
    // that's fine — we only assert that construct + drop terminates
    // promptly, NOT that any events arrive. No network is required;
    // the SDK only binds its local callback-server port (default range
    // 3400-3500).

    fn fake_inputs_one_speaker() -> PumpInputs {
        let kitchen = sid("RINCON_FAKE_KITCHEN");
        let mut speaker_ips = HashMap::new();
        speaker_ips.insert(
            kitchen.clone(),
            // Documentation range (RFC 5737); will never resolve.
            "192.0.2.10".parse().expect("parse fake ip"),
        );
        let mut coord_to_group = HashMap::new();
        coord_to_group.insert(kitchen.clone(), gid("RINCON_FAKE_KITCHEN:1"));
        let mut speaker_to_coord = HashMap::new();
        speaker_to_coord.insert(kitchen.clone(), kitchen.clone());
        let mut speaker_names = HashMap::new();
        speaker_names.insert(kitchen, "Fake Kitchen".to_string());
        PumpInputs {
            speaker_ips,
            coord_to_group,
            speaker_to_coord,
            speaker_names,
        }
    }

    /// Run `op` on a worker thread and assert it finishes within
    /// `budget`. On timeout, panic with a clear "hung" message — that
    /// would have been the symptom of the C1 deadlock under the
    /// previous design.
    fn run_with_deadline<F>(label: &str, budget: std::time::Duration, op: F)
    where
        F: FnOnce() + Send + 'static,
    {
        let (done_tx, done_rx) = std::sync::mpsc::channel::<()>();
        std::thread::spawn(move || {
            op();
            let _ = done_tx.send(());
        });
        done_rx
            .recv_timeout(budget)
            .unwrap_or_else(|_| panic!("'{label}' did not finish within {budget:?} (hang)"));
    }

    #[test]
    fn pump_construct_and_drop_does_not_hang() {
        // 5 s is ~20× the POLL_INTERVAL, plenty of headroom for SDK
        // construction + the async worker setup + the join cycle. Was
        // never returning under the old design.
        run_with_deadline(
            "EventPump::spawn + drop",
            std::time::Duration::from_secs(5),
            || {
                let (pump, _rx) = EventPump::spawn(fake_inputs_one_speaker()).expect("spawn ok");
                drop(pump);
            },
        );
    }

    #[test]
    fn pump_can_be_spawned_and_dropped_twice_in_sequence() {
        // Models the "rediscover" path: discover() builds a new wire,
        // which drops the previous EventPump and constructs a fresh
        // one. Under the C1 deadlock, the first drop would hang and
        // the second spawn never run. Under the fix, both cycles
        // complete promptly.
        run_with_deadline(
            "spawn/drop twice",
            std::time::Duration::from_secs(10),
            || {
                {
                    let (pump1, _rx1) =
                        EventPump::spawn(fake_inputs_one_speaker()).expect("first spawn ok");
                    drop(pump1);
                }
                {
                    let (pump2, _rx2) =
                        EventPump::spawn(fake_inputs_one_speaker()).expect("second spawn ok");
                    drop(pump2);
                }
            },
        );
    }
}
