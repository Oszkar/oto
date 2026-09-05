//! Event pipeline: wraps `sonos-sdk-state` + `sonos-sdk-event-manager`
//! into one OS pump thread that maps upstream property events to
//! `oto_core::ChangeEvent` and pushes them onto an unbounded
//! `std::sync::mpsc::Sender<ChangeEvent>`. The matching `Receiver` is
//! handed out via `SonosWire::take_event_stream`.
//!
//! Design (see `docs/ARCHITECTURE.md` § Live events + `docs/sonos-notes.md`
//! § Event model):
//!   - One thread total (not per-speaker).
//!   - AVTransport NOTIFYs filtered to coordinator-only; emitted with
//!     `GroupId` addressing via the wire's discover-built map.
//!   - `Position` is NOT watched (spike finding #7 - polling-derived).
//!
//! Per `docs/sonos-notes.md` § Event model (spike finding "Bare
//! `StateManager::new()` is an ergonomic footgun") - we use
//! `watch_property_with_subscription::<P>(&sid)` only after attaching a
//! `SonosEventManager` via the builder. The bare `::new()` path
//! registers watches silently with no UPnP SUBSCRIBE.

use std::{
    collections::HashMap,
    net::IpAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

use oto_core::{ChangeEvent, GroupId, SpeakerId, WireError};

/// How often the pump thread checks the `stop` flag while waiting for an
/// upstream event. Doubles as the worst-case latency for `EventPump::Drop`
/// to join the pump thread. 250 ms is well under any human-perceptible
/// shutdown wait and well over typical event arrival cadence - the timeout
/// rarely fires on a busy LAN.
const POLL_INTERVAL: Duration = Duration::from_millis(250);

/// How long `TopologyFilter` stays `dirty` (dropping group-addressed events)
/// with no self-heal. Normally a real regroup's `dirty` window is brief: the
/// Dart `TopologyController` debounces and re-pulls, which spawns a fresh
/// pump (and a fresh, non-dirty `TopologyFilter`) within a couple of
/// seconds. But if BOTH the fast re-pull (`refresh_topology`) and the full
/// re-discover fallback fail (e.g. the household is genuinely unreachable),
/// no fresh pump is ever built, and without this timeout the installed
/// wire would drop every `Playback`/`Track`/`GroupVolume`/`GroupMute` event
/// for the rest of its life - silently and with no way to recover short of
/// a manual re-discover. 60s gives normal regroup recovery generous margin
/// (it should never fire in the common case) while still bounding the
/// worst case. Self-healing here trades a bounded window of possibly-stale
/// routing for never going permanently silent; a fresh, correctly-routed
/// pump supersedes this filter the moment any re-discover does succeed.
const DIRTY_TIMEOUT: Duration = Duration::from_secs(60);

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
    /// v0.5: when `true`, also register a per-speaker
    /// `GroupMembership` watch so regroups surface as
    /// `ChangeEvent::TopologyChanged`. Set from
    /// `SonosWire::topology_requested` (i.e. whether `subscribe_topology`
    /// ran before the pump was built).
    pub(crate) watch_topology: bool,
}

/// Owns the pump thread + the shared stop flag.
///
/// Constructed inside `SonosWire::subscribe_speakers`. Dropped when the
/// wire is replaced (next `discover()`); `Drop` signals the thread to
/// exit via `stop`, then joins. Worst-case join latency is one
/// `POLL_INTERVAL` (~250 ms).
///
/// **Shutdown design:** we do NOT rely on dropping a `StateManager`
/// "keepalive" to close the SDK's event channel. SDK 0.8 manager clones
/// share the event fanout; the pump thread's manager keeps it alive.
/// Waiting for channel-close from that thread would therefore deadlock.
/// The poll-loop + atomic-stop pattern avoids that trap.
pub(crate) struct EventPump {
    /// Set only while the thread is live. Cleared in `Drop` before join.
    handle: Option<JoinHandle<()>>,
    /// Tells the pump thread to exit at its next poll boundary.
    stop: Arc<AtomicBool>,
    /// Retained so `Drop` can call `.shutdown()` explicitly. Without this,
    /// nothing ever breaks the SDK's internal self-referential Arc cycle
    /// (its own state-event-worker thread holds a clone and only releases
    /// it once `Command::Shutdown` has been processed) - see `Drop` below.
    em: Arc<sonos_event_manager::SonosEventManager>,
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
        // `sonos_discovery::Device` records (string IP + port) - we
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
        // can't route subscriptions to coordinators - the watch is
        // registered but no UPnP SUBSCRIBE is sent, no NOTIFYs
        // arrive, no `PlaybackState` / `CurrentTrack` events ever
        // fire (RenderingControl works without topology because it's
        // a per-speaker subscription). The first v0.4 hardware-test
        // failure (PR #45 follow-up): operator play/pause produced
        // zero `ChangeEvent::Playback` because the SDK never subscribed
        // to AVTransport on the coordinator. sonos-notes § Event model
        // documents the required `manager.initialize(topology)` call
        // as part of the canonical builder pattern.
        let topology = build_sdk_topology(&inputs);
        manager.initialize(topology);

        // SDK 0.8 iterators subscribe without replay. Install our receiver
        // before any watch can emit its initial NOTIFY, then move that same
        // queue into the pump thread so startup scheduling cannot lose seeds.
        let iter = manager.iter();

        // Register per-(speaker × property) watches. The SDK's first
        // NOTIFY per subscription seeds the cache (sonos-notes § "the
        // initial SUBSCRIBE NOTIFY *is* the seed probe").
        //
        // We do NOT attempt to surface per-speaker subscription
        // failures here. The SDK at `=0.8.0` still does not expose the
        // information - see `register_watches` for the full citation.
        // This is a known shortfall of the spec's "in-band per-speaker
        // failure surfacing" contract; tracked as v0.5 follow-up.
        register_watches(&manager, &inputs);

        // Move `manager` into the pump thread. The thread owns the
        // manager for its entire lifetime; when the thread exits, the
        // manager drops, releasing its `Arc<SonosEventManager>` clone.
        // That alone does NOT tear down the SDK's event stack - see
        // `Drop for EventPump` for why `em` is retained below instead of
        // being allowed to go out of scope here.
        let coord_to_group = inputs.coord_to_group.clone();
        let speaker_to_coord = inputs.speaker_to_coord.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let stop_for_thread = Arc::clone(&stop);
        let handle = std::thread::Builder::new()
            .name("oto-wire-event-pump".into())
            .spawn(move || {
                pump_loop(
                    manager,
                    iter,
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
            em,
        };
        Ok((pump, rx))
    }

    /// Test-only accessor so the leak regression can observe the SDK
    /// manager's strong-ref count from outside the pump. Not needed by
    /// production code - `Drop` uses `self.em` directly.
    #[cfg(test)]
    pub(crate) fn event_manager(&self) -> &Arc<sonos_event_manager::SonosEventManager> {
        &self.em
    }
}

impl Drop for EventPump {
    fn drop(&mut self) {
        // Explicitly shut down the SDK's event stack. This is required,
        // not an optimisation: the SDK's own state-event-worker thread
        // holds its own `Arc<SonosEventManager>` clone and blocks forever
        // in a loop over it; that clone is only released once the loop
        // observes the channel closing, which only happens after
        // `Command::Shutdown` is processed. Nothing else ever sends that
        // command, so refcount-only teardown (dropping `manager` at the
        // end of `pump_loop`) can never reach zero - a self-referential
        // cycle that otherwise leaks the worker thread, its tokio runtime,
        // its bound callback-server port, and every live GENA subscription
        // (which keeps renewing) forever. `.shutdown()` is a non-blocking
        // `&self` call (just a channel send), so this adds no latency here.
        self.em.shutdown();

        // Signal the pump thread to exit at its next poll boundary
        // (≤ POLL_INTERVAL). Then join.
        //
        // Why this works where an earlier design didn't:
        // SDK 0.8 manager clones share the event fanout (0.5.2 used
        // independent senders). The previous design held a "keepalive"
        // manager clone in this struct AND moved another clone into
        // the pump thread, on the (mistaken) assumption that the SDK's
        // event channel would close when the keepalive dropped. It
        // wouldn't: the pump thread's own clone kept the channel
        // open, and the thread would block on `iter.recv()` forever,
        // self-deadlocking on its own sender clone. The atomic-stop +
        // recv_timeout polling avoids the trap entirely - the pump
        // thread is no longer waiting on its own sender.
        self.stop.store(true, Ordering::Release);
        if let Some(handle) = self.handle.take()
            && let Err(panic) = handle.join()
        {
            // A panicking pump thread would otherwise degrade silently to
            // "events just stop" - nothing else observes pump-thread
            // liveness. Surface it so an SDK-side panic is diagnosable.
            let msg = panic
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| panic.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "<non-string panic payload>".to_string());
            tracing::error!("oto-wire-event-pump thread panicked: {msg}");
        }
    }
}

/// Build the `sonos_state::Topology` payload required by
/// `manager.initialize(...)`. The SDK uses this to populate its
/// internal speaker + group store; `resolve_subscription_target`
/// then routes AVTransport subscriptions to coordinators correctly.
///
/// We reconstruct from `PumpInputs` rather than threading the raw
/// `DiscoverySnapshot` into events.rs - that would couple this module
/// to the wire's discovery internals. The maps in `PumpInputs` carry
/// everything needed: `speaker_ips` (id + ip), `speaker_names`
/// (display name; falls back to id), `coord_to_group` (groups), and
/// `speaker_to_coord` (inverted below to compute members per group).
///
/// Defaults for fields not exposed via `PumpInputs`: `port = 1400`
/// (Sonos's hardcoded UPnP port), `model_name = ""` (unknown
/// pre-discovery - Sonos ZGT doesn't carry it; `oto-core` has the
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
/// **No per-speaker error reporting.** The
/// SDK at `=0.8.0` still does not expose per-speaker subscription failures:
///
///   - `watch_property_with_subscription::<P>` swallows
///     `ensure_service_subscribed` errors with `tracing::warn!` and
///     returns `Ok(...)`. See
///     `sonos-sdk-state-0.8.0/src/state.rs::watch_property_with_subscription`.
///   - `ensure_service_subscribed` itself only fails if the broker's
///     command channel is closed; it returns `Ok` and queues a
///     `Subscribe` command for an async worker even when the target
///     device is unreachable. See
///     `sonos-sdk-event-manager-0.8.0/src/manager.rs::ensure_service_subscribed`.
///   - `is_service_subscribed` is a ref-count check (true iff a
///     `Subscribe` command was *queued*), not a "device responded to
///     SUBSCRIBE" probe. See
///     `sonos-sdk-event-manager-0.8.0/src/manager.rs::is_service_subscribed`.
///
/// The previous version of this fn carried `if let Err(e) = manager
/// .watch_property_with_subscription::<P>(...)` branches emitting
/// `ChangeEvent::SubscriptionError`; those branches were essentially
/// unreachable. They're gone. Honoring the spec's "in-band per-speaker
/// failure surfacing" contract requires either (a) an SDK feature we
/// don't have, or (b) a wire-side timeout-driven sweep we haven't
/// designed yet - tracked as v0.5 follow-up; until then a silent
/// failure manifests as the speaker's Volume/Mute/Playback events
/// simply never arriving (and the UI shows the last-known value).
fn register_watches(manager: &sonos_state::StateManager, inputs: &PumpInputs) {
    use sonos_state::{
        CurrentTrack, GroupMembership, GroupMute, GroupVolume, Mute, PlaybackState, Volume,
    };

    let sdk_id = |sid: &SpeakerId| sonos_state::SpeakerId::new(sid.as_str());

    for sid in inputs.speaker_ips.keys() {
        let sdk_sid = sdk_id(sid);

        // RenderingControl-scoped: Volume + Mute. Both share one UPnP
        // subscription - registering both watches keeps the SDK
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
            // v0.5.1: GroupRenderingControl group master volume/mute are
            // `Scope::Group`, coordinator-routed (sonos-notes § Group
            // operations) - watch on coordinators only, same gate as
            // AVTransport above.
            let _ = manager.watch_property_with_subscription::<GroupVolume>(&sdk_sid);
            let _ = manager.watch_property_with_subscription::<GroupMute>(&sdk_sid);
        }

        // v0.5: ZoneGroupTopology / GroupMembership is `Scope::Speaker`
        // (sonos-notes § "Topology change events") - watch it on EVERY
        // speaker, not just coordinators. A single regroup fires
        // `group_membership` on each affected speaker; the downstream
        // Dart `TopologyController` debounces + re-pulls once.
        if inputs.watch_topology {
            let _ = manager.watch_property_with_subscription::<GroupMembership>(&sdk_sid);
        }
    }

    // NOTE: We deliberately do NOT watch `Position`. The spike found
    // position is polling-derived ~2 s cadence; the UI
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
/// drive shutdown - this thread's manager keeps the SDK event fanout
/// alive. Blocking-recv would self-deadlock waiting for that fanout to
/// close. See `EventPump::drop` for the longer explanation.
fn pump_loop(
    _manager: sonos_state::StateManager,
    iter: sonos_state::ChangeIterator,
    coord_to_group: HashMap<SpeakerId, GroupId>,
    speaker_to_coord: HashMap<SpeakerId, SpeakerId>,
    tx: Sender<ChangeEvent>,
    stop: Arc<AtomicBool>,
) {
    let mut topology = TopologyFilter::new();
    while !stop.load(Ordering::Acquire) {
        let Some(upstream) = iter.recv_timeout(POLL_INTERVAL) else {
            // Timeout fired - no event this poll cycle. The
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
        let Some(event) =
            map_upstream_event(&upstream, &speaker, &coord_to_group, &speaker_to_coord)
        else {
            continue;
        };
        // Apply the topology filter (seed suppression + post-regroup
        // group-event drop) before forwarding. See `TopologyFilter`.
        let Some(event) = topology.admit(&speaker, event) else {
            continue;
        };
        if tx.send(event).is_err() {
            // Receiver gone - wire was dropped before us. Bail.
            return;
        }
    }
}

/// Pump-loop-local filter for the v0.5 topology-event path. Stateful, owned
/// by `pump_loop` (one per pump). Two jobs, both cross-PR review fixes
/// (codex cumulative review of the v0.5 series):
///
/// 1. **Seed suppression.** `map_upstream_event` compares membership with
///    the discovered group and coordinator role. Unchanged seeds are ignored
///    regardless of arrival time; genuine changes are forwarded immediately.
///
/// 2. **Post-regroup group-event drop (#4).** The pump's `coord_to_group` /
///    `speaker_to_coord` maps are captured by value at spawn and frozen.
///    After a real regroup they're stale, so a `Playback`/`Track` event
///    would carry an obsolete `GroupId`. Once a real topology change is
///    seen we mark the pump `dirty` and drop group-addressed events until
///    the pump is rebuilt (re-discover). Per-speaker `Volume`/`Mute` are
///    unaffected by grouping and keep flowing.
struct TopologyFilter {
    /// Set once a real (post-seed) topology change is observed. While set,
    /// group-addressed events are dropped (stale routing).
    dirty: bool,
    /// When `dirty` was set. `None` while not dirty. Used to self-heal past
    /// [`DIRTY_TIMEOUT`] if no pump rebuild ever clears `dirty` the normal
    /// way (see [`DIRTY_TIMEOUT`]'s doc for why this is needed).
    dirty_since: Option<Instant>,
    /// How long `dirty` may stay set with no self-heal. `new()` uses
    /// [`DIRTY_TIMEOUT`]; tests inject a short window to drive the self-heal
    /// path deterministically.
    dirty_timeout: Duration,
}

impl TopologyFilter {
    fn new() -> Self {
        Self::with_dirty_timeout(DIRTY_TIMEOUT)
    }

    fn with_dirty_timeout(dirty_timeout: Duration) -> Self {
        Self {
            dirty: false,
            dirty_since: None,
            dirty_timeout,
        }
    }

    /// Decide whether to forward `event` (which originated from `speaker`).
    /// `None` = drop. Mutates dirty state.
    fn admit(&mut self, _speaker: &SpeakerId, event: ChangeEvent) -> Option<ChangeEvent> {
        // Self-heal: if dirty has outlived DIRTY_TIMEOUT with no pump rebuild
        // (both re-pull paths failed), stop dropping group-addressed events -
        // see DIRTY_TIMEOUT's doc for why. Checked lazily on the next event
        // rather than via a background timer, consistent with the rest of
        // this poll-driven pipeline.
        if let Some(since) = self.dirty_since
            && since.elapsed() >= self.dirty_timeout
        {
            self.dirty = false;
            self.dirty_since = None;
        }
        match &event {
            ChangeEvent::TopologyChanged => {
                // A real regroup: routing is now stale until pump rebuild
                // (or DIRTY_TIMEOUT self-heals it - see that constant's doc).
                self.dirty = true;
                self.dirty_since = Some(Instant::now());
                Some(event)
            }
            // Group-addressed events carry a GroupId routed via the frozen
            // maps; after a regroup that routing is stale - drop until rebuild.
            // GroupVolume/GroupMute (v0.5.1) are group-addressed too - same drop.
            ChangeEvent::Playback { .. }
            | ChangeEvent::Track { .. }
            | ChangeEvent::GroupVolume { .. }
            | ChangeEvent::GroupMute { .. }
                if self.dirty =>
            {
                None
            }
            // Volume/Mute (per-speaker) and the surface events are
            // grouping-independent - always forward.
            _ => Some(event),
        }
    }
}

/// Pure mapping: upstream `sonos_state::ChangeEvent` → optional
/// `oto_core::ChangeEvent`. Returns `None` if:
///   - the typed property is outside oto's watched surface
///   - a group-addressed event comes from a non-coordinator (coordinator-only
///     filter - see `av_transport_group_id`)
fn map_upstream_event(
    upstream: &sonos_state::ChangeEvent,
    speaker: &SpeakerId,
    coord_to_group: &HashMap<SpeakerId, GroupId>,
    speaker_to_coord: &HashMap<SpeakerId, SpeakerId>,
) -> Option<ChangeEvent> {
    use sonos_state::PropertyChange;

    // SDK 0.8 carries the value observed for this event. Reading its mutable
    // cache instead could replace queued transitions with a later value.
    match &upstream.change {
        PropertyChange::Volume(v) => Some(volume_event(speaker.clone(), v.clone())),
        PropertyChange::Mute(m) => Some(mute_event(speaker.clone(), m.clone())),
        PropertyChange::PlaybackState(state) => Some(ChangeEvent::Playback {
            group: av_transport_group_id(speaker, speaker_to_coord, coord_to_group)?,
            state: map_playback_state(state.clone()),
        }),
        PropertyChange::CurrentTrack(track) => Some(ChangeEvent::Track {
            group: av_transport_group_id(speaker, speaker_to_coord, coord_to_group)?,
            track: map_current_track(track.clone()),
        }),
        PropertyChange::GroupVolume(v) => Some(group_volume_event(
            av_transport_group_id(speaker, speaker_to_coord, coord_to_group)?,
            v.clone(),
        )),
        PropertyChange::GroupMute(m) => Some(group_mute_event(
            av_transport_group_id(speaker, speaker_to_coord, coord_to_group)?,
            m.clone(),
        )),
        PropertyChange::GroupMembership(membership) => {
            // Initial NOTIFYs can arrive tens of seconds after SUBSCRIBE.
            // Compare with discovery instead of guessing from arrival time:
            // rebuilding on a delayed seed restarts subscriptions and loses
            // group events while the old pump is marked dirty.
            let unchanged = speaker_to_coord.get(speaker).is_some_and(|coord| {
                coord_to_group.get(coord).is_some_and(|group| {
                    group.as_str() == membership.group_id.as_str()
                        && (speaker == coord) == membership.is_coordinator
                })
            });
            (!unchanged).then_some(ChangeEvent::TopologyChanged)
        }
        // Properties outside oto's watched surface are intentionally ignored.
        _ => None,
    }
}

/// AVTransport coordinator-only filter - drop the event if `speaker`
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
        // Not a coordinator - drop the AVTransport event.
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
/// property - leave them `None`; the UI tolerates partial Tracks.
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

/// SDK `GroupVolume`(u16) → `oto_core::ChangeEvent::GroupVolume` for `group`.
/// The SDK's `GroupVolume::new` clamps at 100; `Volume::clamped` here is
/// belt-and-braces against any future shape drift (mirrors `volume_event`).
fn group_volume_event(group: GroupId, v: sonos_state::GroupVolume) -> ChangeEvent {
    ChangeEvent::GroupVolume {
        group,
        volume: oto_core::Volume::clamped(i32::from(v.value())),
    }
}

/// SDK `GroupMute` → `oto_core::ChangeEvent::GroupMute` for `group`.
fn group_mute_event(group: GroupId, m: sonos_state::GroupMute) -> ChangeEvent {
    ChangeEvent::GroupMute {
        group,
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

    #[test]
    fn unchanged_membership_does_not_restart_subscriptions() {
        use sonos_state::{ChangeSource, PropertyChange, WriteStamp};
        let speaker = sid("RINCON_K");
        let c2g = HashMap::from([(speaker.clone(), gid("G:1"))]);
        let s2c = HashMap::from([(speaker.clone(), speaker.clone())]);
        let upstream = sonos_state::ChangeEvent::new(
            sonos_state::SpeakerId::new(speaker.as_str()),
            PropertyChange::GroupMembership(sonos_state::GroupMembership::new(
                sonos_state::GroupId::new("G:1"),
                true,
            )),
            WriteStamp::now(ChangeSource::Event),
        );
        // Delayed NOTIFY and polling seeds must be compared to discovery,
        // not interpreted as regrouping simply because five seconds elapsed.
        assert!(map_upstream_event(&upstream, &speaker, &c2g, &s2c).is_none());
    }

    #[test]
    fn membership_mapping_detects_group_and_role_changes_for_all_rooms() {
        use sonos_state::{ChangeSource, PropertyChange, WriteStamp};
        let coord = sid("RINCON_K");
        let follower = sid("RINCON_L");
        let c2g = HashMap::from([(coord.clone(), gid("G:1"))]);
        let s2c = HashMap::from([
            (coord.clone(), coord.clone()),
            (follower.clone(), coord.clone()),
        ]);
        for (speaker, group, is_coord, changed) in [
            (coord.clone(), "G:1", true, false),
            (follower.clone(), "G:1", false, false),
            (coord.clone(), "G:2", true, true),
            (follower.clone(), "G:2", false, true),
            (coord, "G:1", false, true),
            (follower, "G:1", true, true),
            (sid("RINCON_NEW"), "G:1", false, true),
        ] {
            let upstream = sonos_state::ChangeEvent::new(
                sonos_state::SpeakerId::new(speaker.as_str()),
                PropertyChange::GroupMembership(sonos_state::GroupMembership::new(
                    sonos_state::GroupId::new(group),
                    is_coord,
                )),
                WriteStamp::now(ChangeSource::Event),
            );
            assert_eq!(
                map_upstream_event(&upstream, &speaker, &c2g, &s2c),
                changed.then_some(ChangeEvent::TopologyChanged),
                "membership for {speaker:?} in {group}, coordinator={is_coord}",
            );
        }
    }

    #[test]
    fn seed_queued_before_pump_thread_starts_is_delivered() {
        let inputs = fake_inputs_one_speaker();
        // No event manager: exercise the real SDK fanout without networking.
        let manager = sonos_state::StateManager::new().expect("cache-only manager");
        manager.initialize(build_sdk_topology(&inputs));
        let iter = manager.iter();
        register_watches(&manager, &inputs);
        let speaker = inputs.speaker_ips.keys().next().unwrap().clone();
        manager.set_property(
            &sonos_state::SpeakerId::new(speaker.as_str()),
            sonos_state::Volume::new(23),
        );
        let (tx, rx) = mpsc::channel();
        let stop = Arc::new(AtomicBool::new(false));
        let thread_stop = Arc::clone(&stop);
        let handle = std::thread::spawn(move || {
            pump_loop(
                manager,
                iter,
                inputs.coord_to_group,
                inputs.speaker_to_coord,
                tx,
                thread_stop,
            );
        });
        let received = rx.recv_timeout(Duration::from_secs(2));
        // Always stop/join before asserting, including on a regression.
        stop.store(true, Ordering::Release);
        handle.join().expect("pump exits");
        assert_eq!(
            received.unwrap(),
            ChangeEvent::Volume {
                speaker,
                volume: oto_core::Volume::new(23).unwrap(),
            }
        );
    }

    #[test]
    fn queued_payloads_preserve_observed_values_and_group_routing() {
        use sonos_state::{ChangeSource, PropertyChange, WriteStamp};
        let coordinator = sid("RINCON_C");
        let follower = sid("RINCON_F");
        let group = gid("RINCON_C:1");
        let s2c = HashMap::from([
            (coordinator.clone(), coordinator.clone()),
            (follower.clone(), coordinator.clone()),
        ]);
        let c2g = HashMap::from([(coordinator.clone(), group.clone())]);
        let changes = [
            PropertyChange::PlaybackState(sonos_state::PlaybackState::Playing),
            PropertyChange::PlaybackState(sonos_state::PlaybackState::Transitioning),
            PropertyChange::PlaybackState(sonos_state::PlaybackState::Playing),
            PropertyChange::GroupVolume(sonos_state::GroupVolume::new(23)),
            PropertyChange::GroupMute(sonos_state::GroupMute::new(true)),
        ];
        // Queue observations before mapping: a later cache value must not
        // replace an earlier transition. Group values need no store lookup.
        let queued: Vec<_> = changes
            .into_iter()
            .map(|change| {
                sonos_state::ChangeEvent::new(
                    sonos_state::SpeakerId::new(coordinator.as_str()),
                    change,
                    WriteStamp::now(ChangeSource::Event),
                )
            })
            .collect();
        let mapped: Vec<_> = queued
            .iter()
            .filter_map(|event| map_upstream_event(event, &coordinator, &c2g, &s2c))
            .collect();
        assert_eq!(
            mapped,
            vec![
                ChangeEvent::Playback {
                    group: group.clone(),
                    state: oto_core::PlaybackState::Playing
                },
                ChangeEvent::Playback {
                    group: group.clone(),
                    state: oto_core::PlaybackState::Transitioning
                },
                ChangeEvent::Playback {
                    group: group.clone(),
                    state: oto_core::PlaybackState::Playing
                },
                ChangeEvent::GroupVolume {
                    group: group.clone(),
                    volume: oto_core::Volume::new(23).unwrap()
                },
                ChangeEvent::GroupMute { group, muted: true },
            ]
        );
        for mut event in queued {
            event.speaker_id = sonos_state::SpeakerId::new(follower.as_str());
            assert!(map_upstream_event(&event, &follower, &c2g, &s2c).is_none());
        }
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
        // the GroupId we can't address the event - drop it. Can happen
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

    // ── TopologyFilter (seed suppression #1 + dirty-drop #4) ──────────────

    fn track_ev(g: &str) -> ChangeEvent {
        ChangeEvent::Track {
            group: gid(g),
            track: oto_core::Track {
                id: None,
                title: None,
                artist: None,
                album: None,
                track_number: None,
                duration: None,
                art_uri: None,
                uri: None,
            },
        }
    }
    fn playback_ev(g: &str) -> ChangeEvent {
        ChangeEvent::Playback {
            group: gid(g),
            state: oto_core::PlaybackState::Playing,
        }
    }
    fn volume_ev(s: &str) -> ChangeEvent {
        ChangeEvent::Volume {
            speaker: sid(s),
            volume: oto_core::Volume::new(40).unwrap(),
        }
    }
    fn group_volume_ev(g: &str) -> ChangeEvent {
        ChangeEvent::GroupVolume {
            group: gid(g),
            volume: oto_core::Volume::new(40).unwrap(),
        }
    }

    #[test]
    fn genuine_topology_change_is_admitted_even_at_startup() {
        let mut f = TopologyFilter::new();
        assert!(matches!(
            f.admit(&sid("RINCON_K"), ChangeEvent::TopologyChanged),
            Some(ChangeEvent::TopologyChanged)
        ));
        assert!(f.admit(&sid("RINCON_K"), playback_ev("G:1")).is_none());
    }

    #[test]
    fn group_events_pass_before_a_regroup() {
        let mut f = TopologyFilter::new();
        // Before any real topology change, group-addressed events flow.
        assert!(f.admit(&sid("RINCON_K"), playback_ev("G:1")).is_some());
        assert!(f.admit(&sid("RINCON_K"), track_ev("G:1")).is_some());
    }

    #[test]
    fn group_events_dropped_while_dirty_but_volume_mute_pass() {
        let mut f = TopologyFilter::new();
        let _ = f.admit(&sid("RINCON_K"), ChangeEvent::TopologyChanged); // real → dirty
        // Group-addressed events now carry stale routing → dropped.
        assert!(f.admit(&sid("RINCON_K"), playback_ev("G:stale")).is_none());
        assert!(f.admit(&sid("RINCON_K"), track_ev("G:stale")).is_none());
        // Per-speaker events are grouping-independent → still flow.
        assert!(f.admit(&sid("RINCON_K"), volume_ev("RINCON_K")).is_some());
        assert!(
            f.admit(
                &sid("RINCON_K"),
                ChangeEvent::Mute {
                    speaker: sid("RINCON_K"),
                    muted: true
                }
            )
            .is_some()
        );
    }

    #[test]
    fn group_volume_and_mute_dropped_while_dirty_but_volume_passes() {
        // v0.5.1: GroupVolume/GroupMute are group-addressed via the frozen
        // maps - they must be dropped after a regroup (stale routing), like
        // Playback/Track. Per-speaker Volume/Mute keep flowing.
        let mut f = TopologyFilter::new();
        let _ = f.admit(&sid("RINCON_K"), ChangeEvent::TopologyChanged); // real → dirty
        assert!(
            f.admit(&sid("RINCON_K"), group_volume_ev("G:stale"))
                .is_none(),
            "GroupVolume must be dropped while dirty (stale group routing)"
        );
        assert!(
            f.admit(
                &sid("RINCON_K"),
                ChangeEvent::GroupMute {
                    group: gid("G:stale"),
                    muted: true
                }
            )
            .is_none(),
            "GroupMute must be dropped while dirty (stale group routing)"
        );
        // Per-speaker Volume/Mute are grouping-independent → still flow.
        assert!(f.admit(&sid("RINCON_K"), volume_ev("RINCON_K")).is_some());
        assert!(
            f.admit(
                &sid("RINCON_K"),
                ChangeEvent::Mute {
                    speaker: sid("RINCON_K"),
                    muted: false
                }
            )
            .is_some()
        );
    }

    #[test]
    fn group_volume_passes_before_a_regroup() {
        let mut f = TopologyFilter::new();
        assert!(f.admit(&sid("RINCON_K"), group_volume_ev("G:1")).is_some());
        assert!(
            f.admit(
                &sid("RINCON_K"),
                ChangeEvent::GroupMute {
                    group: gid("G:1"),
                    muted: true
                }
            )
            .is_some()
        );
    }

    /// If both re-pull paths (fast `refresh_topology` + full re-discover
    /// fallback) fail after a real regroup, no fresh pump is ever built to
    /// clear `dirty` the normal way - without a self-heal, the installed
    /// wire would drop every group-addressed event for the rest of its
    /// life. `dirty` must clear once DIRTY_TIMEOUT elapses.
    #[test]
    fn dirty_flag_self_heals_after_timeout_with_no_pump_rebuild() {
        let mut f = TopologyFilter::with_dirty_timeout(Duration::from_millis(50));
        // Mapping already established that membership differs from discovery.
        let _ = f.admit(&sid("RINCON_K"), ChangeEvent::TopologyChanged);
        assert!(
            f.admit(&sid("RINCON_K"), playback_ev("G:1")).is_none(),
            "group-addressed events must be dropped immediately after a real \
             regroup (stale routing) - precondition for this test"
        );

        std::thread::sleep(Duration::from_millis(60));

        assert!(
            f.admit(&sid("RINCON_K"), playback_ev("G:1")).is_some(),
            "dirty must self-heal once DIRTY_TIMEOUT elapses - otherwise a \
             household where both re-pull paths keep failing stays \
             permanently mute for group-addressed events"
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
        // SDK doesn't carry these on CurrentTrack - must stay None.
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

    // ── group volume / mute event constructors (v0.5.1) ───────────────

    #[test]
    fn group_volume_event_clamps_and_carries_group_id() {
        let g = gid("RINCON_K:1");
        let ev = group_volume_event(g.clone(), sonos_state::GroupVolume::new(73));
        match ev {
            ChangeEvent::GroupVolume { group, volume } => {
                assert_eq!(group, g);
                assert_eq!(volume.get(), 73);
            }
            other => panic!("expected GroupVolume, got {other:?}"),
        }
    }

    #[test]
    fn group_volume_event_clamps_out_of_range_value() {
        // Bypass GroupVolume::new (which itself clamps) via the public tuple
        // field, so the value reaching group_volume_event is genuinely > 100 -
        // this exercises oto's belt-and-braces Volume::clamped guard, not the
        // SDK's own clamp.
        let g = gid("RINCON_K:1");
        let ev = group_volume_event(g, sonos_state::GroupVolume(200));
        let ChangeEvent::GroupVolume { volume, .. } = ev else {
            panic!("expected GroupVolume")
        };
        assert_eq!(
            volume.get(),
            100,
            "Volume::clamped must cap an out-of-range group volume at 100"
        );
    }

    #[test]
    fn group_mute_event_round_trips_both_bool_states() {
        let g = gid("RINCON_K:1");
        match group_mute_event(g.clone(), sonos_state::GroupMute::new(true)) {
            ChangeEvent::GroupMute { group, muted } => {
                assert_eq!(group, g);
                assert!(muted);
            }
            other => panic!("expected GroupMute, got {other:?}"),
        }
        match group_mute_event(g.clone(), sonos_state::GroupMute::new(false)) {
            ChangeEvent::GroupMute { group, muted } => {
                assert_eq!(group, g);
                assert!(!muted);
            }
            other => panic!("expected GroupMute, got {other:?}"),
        }
    }

    #[test]
    fn spawn_returns_no_speakers_error_when_inputs_empty() {
        let inputs = PumpInputs {
            speaker_ips: HashMap::new(),
            coord_to_group: HashMap::new(),
            speaker_to_coord: HashMap::new(),
            speaker_names: HashMap::new(),
            watch_topology: false,
        };
        let err = EventPump::spawn(inputs).err().expect("must error");
        assert!(matches!(err, WireError::NoSpeakersDiscovered));
    }

    // ── EventPump construct/drop deadlock regression ──────────────────
    //
    // Deadlock regression coverage: the previous design self-deadlocked
    // in `EventPump::Drop` because the pump thread held its own
    // `StateManager::Clone` (= its own SDK event sender) and blocked on
    // `iter.recv()`, which only returns `None` when the LAST sender
    // drops. The thread couldn't drop its own sender until it exited;
    // it couldn't exit until the sender dropped. The fix converts the
    // loop to `recv_timeout` + an atomic stop flag.
    //
    // These tests use the REAL SDK with fake IPs. SUBSCRIBE attempts
    // will fail in the SDK's async worker (no real Sonos at the IP);
    // that's fine - we only assert that construct + drop terminates
    // promptly, NOT that any events arrive. No network is required;
    // the SDK only binds its local callback-server port (default range
    // 3400-3500).

    /// Drop must release every strong ref to the SDK's `SonosEventManager`
    /// so its own `Drop` (which sends `Command::Shutdown`) can eventually
    /// fire - otherwise the SDK's internal worker thread, its bound
    /// callback-server port, and its GENA subscriptions all leak forever.
    /// Root cause: the SDK's own state-event-worker thread holds its own
    /// `Arc<SonosEventManager>` clone and blocks in a loop over it, only
    /// releasing that clone once the loop ends - which only happens after
    /// `Command::Shutdown` is processed. Nothing sends that command unless
    /// something calls `.shutdown()` explicitly; refcount alone can never
    /// reach zero (a self-referential cycle). `event_manager()` below is a
    /// test-only accessor (see the `#[cfg(test)]` gate) added purely to
    /// observe this from outside the pump.
    #[test]
    fn drop_releases_all_strong_refs_to_event_manager() {
        let (pump, _rx) = EventPump::spawn(fake_inputs_one_speaker()).expect("spawn ok");
        let em = std::sync::Arc::clone(pump.event_manager());
        let count_before_drop = std::sync::Arc::strong_count(&em);
        assert!(
            count_before_drop >= 2,
            "sanity: the manager must have at least one internal owner \
             (StateManager and/or the SDK's own worker thread) while the \
             pump is alive, plus this test's own clone; got {count_before_drop}"
        );

        drop(pump);

        // Teardown crosses two SDK-internal threads (the manager's own async
        // broker processing Shutdown, then the state-event-worker's blocking
        // loop observing the closed channel) - not synchronous with
        // EventPump::drop returning, so poll rather than assert immediately.
        // Empirically ~15s against this unreachable fake IP: the broker's
        // `command_rx` is FIFO behind the Subscribe backlog `register_watches`
        // already queued, and (per `sonos-stream/src/config.rs`'s
        // `enable_proactive_firewall_detection` + `firewall_event_wait_timeout:
        // 15s`) it waits to see whether a callback NOTIFY ever arrives before
        // falling back - it never does, against a documentation-range IP. 30s
        // gives 2x margin over the observed convergence for CI variance; this
        // is real SDK-internal latency against an unreachable device, not
        // anything oto's own code controls.
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
        loop {
            let count = std::sync::Arc::strong_count(&em);
            if count == 1 {
                break;
            }
            assert!(
                std::time::Instant::now() < deadline,
                "manager still has {count} strong ref(s) 30s after EventPump::drop \
                 (want 1 - only this test's own clone) - the SDK event stack is leaking"
            );
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
    }

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
            watch_topology: false,
        }
    }

    /// Run `op` on a worker thread and assert it finishes within
    /// `budget`. On timeout, panic with a clear "hung" message - that
    /// would have been the symptom of a deadlock in the
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
    fn pump_with_topology_watch_constructs_and_drops() {
        // v0.5: when watch_topology is set, the pump also registers a
        // per-speaker GroupMembership watch. Verify that path constructs +
        // tears down cleanly (no hardware; the SDK only binds its local
        // callback port). Guards against a regression where the extra watch
        // registration deadlocks or panics on spawn/drop.
        let mut inputs = fake_inputs_one_speaker();
        inputs.watch_topology = true;
        run_with_deadline(
            "EventPump::spawn(topology) + drop",
            std::time::Duration::from_secs(5),
            move || {
                let (pump, _rx) = EventPump::spawn(inputs).expect("spawn ok");
                drop(pump);
            },
        );
    }

    #[test]
    fn pump_can_be_spawned_and_dropped_twice_in_sequence() {
        // Models the "rediscover" path: discover() builds a new wire,
        // which drops the previous EventPump and constructs a fresh
        // one. Under the prior deadlock design, the first drop would hang
        // and the second spawn never run. Both cycles now
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
