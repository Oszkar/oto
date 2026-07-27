//! Production `Wire`: own SSDP + direct `sonos-api` SOAP.

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Receiver;
use std::time::Duration;

use oto_core::{
    ChangeEvent, DiscoverySnapshot, GroupId, GroupIdentity, SpeakerId, SpeakerIdentity,
    SpeakerState, TrackPosition, Volume, Wire, WireError,
};
use sonos_api::SonosClient;
use sonos_api::services::zone_group_topology::ZoneGroupInfo;

use crate::events::{EventPump, PumpInputs};
use crate::{control, grouping, ssdp};

const SSDP_TIMEOUT: Duration = Duration::from_secs(3);

/// Total budget for `refresh_topology`'s per-IP `GetZoneGroupState` retry
/// loop. Each attempt can itself take up to ~15s (`sonos-sdk-soap-client`'s
/// fixed 5s connect + 10s read timeout, outside oto's control) and the loop
/// runs under `oto_app`'s global SLOT mutex - unbounded, a household with N
/// cached-but-now-unreachable IPs would stall every other command for up to
/// N x 15s. 30s (~2 full worst-case attempts) preserves the loop's purpose
/// (fall through a sleeping speaker to a reachable one) while capping the
/// pathological "whole household unreachable" case instead of letting it
/// scale with household size.
const TOPOLOGY_REFRESH_DEADLINE: Duration = Duration::from_secs(30);

/// The wire's interior-mutable resolution caches, populated together by
/// `discover()` / `refresh_topology()` and read by the command/read paths.
///
/// Held behind ONE `Mutex` (not four) so a snapshot install is a single atomic
/// swap and every multi-field read (e.g. group -> coordinator -> addr) resolves
/// under one lock. With separate mutexes a command racing an in-flight
/// re-populate could observe one map already updated and another not yet,
/// yielding a transient, spurious `NotFound`.
#[derive(Default)]
struct Caches {
    /// Maps `SpeakerId` -> `SocketAddr(ip, 1400)` for rendering-control calls.
    id_to_addr: HashMap<SpeakerId, SocketAddr>,
    /// Maps `GroupId` -> coordinator `SpeakerId` for transport-control calls.
    group_to_coordinator: HashMap<GroupId, SpeakerId>,
    /// Maps each member `SpeakerId` -> its group coordinator `SpeakerId`
    /// (oto-core D2). Coordinator maps to itself.
    speaker_to_coordinator: HashMap<SpeakerId, SpeakerId>,
    /// Maps `SpeakerId` -> its `room_name`. Used only by the v0.4 event pump to
    /// populate the SDK's `sonos_discovery::Device` records.
    id_to_name: HashMap<SpeakerId, String>,
}

/// Production wire implementation backed by `sonos_api` direct SOAP calls.
///
/// The interior-mutable [`Caches`] are populated by `discover()` and used by
/// the playback/read methods + the v0.4 event pump. All methods return
/// `Err(WireError::NotFound)` if called before a successful `discover()` has
/// populated the relevant entry.
pub struct SonosWire {
    /// Shared `sonos_api` SOAP client. Held on the wire so each command
    /// reuses it instead of paying `SonosClient::new()` per call.
    client: SonosClient,
    /// Resolution caches behind a single lock (see [`Caches`]).
    caches: Mutex<Caches>,
    /// v0.4 event pump + the still-takeable `Receiver`. `None` until
    /// `subscribe_speakers` is called; `Some` thereafter for the
    /// lifetime of the wire. The `Receiver` is taken once via
    /// `take_event_stream` and then is `None` inside the option.
    events_state: Mutex<Option<EventsState>>,
    /// v0.5: `true` once `subscribe_topology` has been called.
    /// Read by `subscribe_speakers` when it builds the pump - when set,
    /// the pump also registers a per-speaker `GroupMembership` watch so
    /// regroups surface as `ChangeEvent::TopologyChanged`. MUST be set
    /// before `subscribe_speakers` builds the pump (the SDK manager is
    /// moved into the pump thread and can't take new watches after);
    /// `discover_with` enforces this ordering.
    topology_requested: AtomicBool,
    /// v0.5.1: seed responder IPs for an SSDP-skipped discover.
    /// Empty for `new()` → `discover()` runs the full multi-NIC SSDP sweep.
    /// Non-empty for `new_seeded()` → `discover()` skips SSDP and uses these
    /// as the `GetZoneGroupState` responder candidates (PerNetwork: any
    /// reachable one answers for the whole household). This makes a regroup
    /// re-discover fast (~50 ms vs ~3 s) while still flowing through the
    /// proven wire-replacement lifecycle (fresh pump, clean TopologyFilter).
    seed_ips: Vec<IpAddr>,
}

struct EventsState {
    /// Owns the pump thread + the stop flag. Dropped when the wire is
    /// dropped (or on `discover_with` replacement); `EventPump::Drop`
    /// signals the pump to exit at the next poll boundary (~250 ms)
    /// and joins. The SDK manager / event worker shut down naturally
    /// once the pump thread releases its `StateManager` ownership.
    _pump: EventPump,
    /// One-shot: taken on first `take_event_stream`, then `None`.
    rx: Option<Receiver<ChangeEvent>>,
}

impl SonosWire {
    pub fn new() -> Self {
        Self::with_seed_ips(Vec::new())
    }

    /// v0.5.1: construct a wire whose `discover()` skips the SSDP
    /// sweep and instead uses `seed_ips` as the `GetZoneGroupState` responder
    /// candidates. Used by `oto-app::refresh_topology` to install a FRESH wire
    /// (fresh pump, gen bump → Dart re-subscribes) seeded from the speaker IPs
    /// the current wire already knows - a "discover() minus SSDP" fast path.
    /// `new()` keeps `seed_ips` empty, so the full-SSDP behavior is unchanged.
    pub fn new_seeded(seed_ips: Vec<IpAddr>) -> Self {
        Self::with_seed_ips(seed_ips)
    }

    fn with_seed_ips(seed_ips: Vec<IpAddr>) -> Self {
        Self {
            client: SonosClient::new(),
            caches: Mutex::new(Caches::default()),
            events_state: Mutex::new(None),
            topology_requested: AtomicBool::new(false),
            seed_ips,
        }
    }

    /// Lock the resolution caches, recovering from a poisoned lock (a panic in
    /// another thread). Every cache access goes through here.
    fn caches(&self) -> std::sync::MutexGuard<'_, Caches> {
        self.caches.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Snapshot the wire's interior-mutable caches into a `PumpInputs`
    /// for `EventPump::spawn`. Returns `NoSpeakersDiscovered` if the
    /// caches are empty (called before discover()).
    fn snapshot_for_pump(&self) -> Result<PumpInputs, WireError> {
        let caches = self.caches();
        if caches.id_to_addr.is_empty() {
            return Err(WireError::NoSpeakersDiscovered);
        }
        // Build coord_to_group by inverting group_to_coordinator.
        let coord_to_group = caches
            .group_to_coordinator
            .iter()
            .map(|(g, coord)| (coord.clone(), g.clone()))
            .collect();
        let speaker_ips = caches
            .id_to_addr
            .iter()
            .map(|(sid, addr)| (sid.clone(), addr.ip()))
            .collect();
        Ok(PumpInputs {
            speaker_ips,
            coord_to_group,
            speaker_to_coord: caches.speaker_to_coordinator.clone(),
            speaker_names: caches.id_to_name.clone(),
            watch_topology: self.topology_requested.load(Ordering::SeqCst),
        })
    }

    /// Resolve a `SpeakerId` to its cached `SocketAddr`.
    ///
    /// Returns `Err(WireError::NotFound)` if unknown or pre-discovery.
    fn resolve_speaker(&self, speaker: &SpeakerId) -> Result<SocketAddr, WireError> {
        self.caches()
            .id_to_addr
            .get(speaker)
            .copied()
            .ok_or_else(|| WireError::NotFound(speaker.to_string()))
    }

    /// Resolve a `GroupId` -> coordinator `SpeakerId` -> `SocketAddr`, under a
    /// single lock so the group and address maps are read as one consistent
    /// snapshot (a re-populate can't interleave between the two reads).
    ///
    /// Returns `Err(WireError::NotFound)` if the group or its coordinator
    /// address is unknown (pre-discovery or stale cache).
    fn resolve_group(&self, group: &GroupId) -> Result<SocketAddr, WireError> {
        let caches = self.caches();
        let coordinator = caches
            .group_to_coordinator
            .get(group)
            .cloned()
            .ok_or_else(|| WireError::NotFound(group.to_string()))?;
        caches
            .id_to_addr
            .get(&coordinator)
            .copied()
            .ok_or_else(|| WireError::NotFound(coordinator.to_string()))
    }

    /// Populate the interior-mutable caches from a discovery snapshot.
    /// Shared by `discover()` and the cache unit test so the test drives
    /// the real cache-population path, not a hand-duplicated copy (a
    /// duplicate would still pass if `discover()`'s update were removed).
    fn populate_caches(&self, snapshot: &DiscoverySnapshot) {
        // One lock: a racing command sees either the whole old topology or the
        // whole new one, never a half-updated mix. Clear each map in place
        // (retaining its allocation) rather than replacing the struct, so a
        // same-sized re-populate doesn't churn allocations.
        let mut caches = self.caches();
        caches.id_to_addr.clear();
        caches.group_to_coordinator.clear();
        caches.speaker_to_coordinator.clear();
        caches.id_to_name.clear();
        for speaker in &snapshot.speakers {
            caches
                .id_to_addr
                .insert(speaker.id.clone(), SocketAddr::new(speaker.ip, 1400));
            caches
                .id_to_name
                .insert(speaker.id.clone(), speaker.room_name.clone());
        }
        for group in &snapshot.groups {
            caches
                .group_to_coordinator
                .insert(group.id.clone(), group.coordinator.clone());
            for m in &group.members {
                caches
                    .speaker_to_coordinator
                    .insert(m.clone(), group.coordinator.clone());
            }
        }
    }

    /// Transport lives on the coordinator (oto-core D2): resolve the
    /// speaker's group coordinator's addr. With no coordinator mapping
    /// (solo speaker, or empty/stale cache) fall back to the speaker's
    /// own addr - correct for a solo speaker, and otherwise yields the
    /// same `NotFound` as v0.2 until `discover()` has populated the caches.
    fn resolve_transport_addr(&self, speaker: &SpeakerId) -> Result<SocketAddr, WireError> {
        // Single lock: coordinator lookup + address lookup read one consistent
        // snapshot. Falls back to the speaker's own addr when it has no
        // coordinator mapping (solo speaker, or empty/stale cache).
        let caches = self.caches();
        let target = caches
            .speaker_to_coordinator
            .get(speaker)
            .unwrap_or(speaker);
        caches
            .id_to_addr
            .get(target)
            .copied()
            .ok_or_else(|| WireError::NotFound(target.to_string()))
    }
}

impl Default for SonosWire {
    fn default() -> Self {
        Self::new()
    }
}

/// Strip `http://host:port/…` → bare IP string for `sonos_api` calls.
fn extract_ip(url: &str) -> Option<String> {
    url.strip_prefix("http://")?
        .split('/')
        .next()?
        .split(':')
        .next()
        .map(str::to_string)
}

/// Build a real `DiscoverySnapshot` from parsed ZoneGroupTopology.
///
/// Speakers = top-level members (satellites are folded into their
/// primary, never surfaced - oto-core D5). Each group's members are
/// reordered coordinator-first (oto-core D3; the parser does not
/// guarantee order). Vanished devices are already dropped by
/// `parse_zone_group_state_xml`.
fn to_snapshot(groups: Vec<ZoneGroupInfo>) -> DiscoverySnapshot {
    let mut speakers = Vec::new();
    let mut out_groups = Vec::new();

    for zg in groups {
        let coord = SpeakerId::new(zg.coordinator.clone());

        // Accumulate this group's speakers locally so that a skipped group
        // (coordinator absent from members - anomalous) does not leave orphan
        // speakers in the snapshot that belong to no group.
        let mut group_speakers: Vec<SpeakerIdentity> = Vec::with_capacity(zg.members.len());
        let mut members: Vec<SpeakerId> = Vec::with_capacity(zg.members.len());
        for m in &zg.members {
            let ip: IpAddr = match extract_ip(&m.location).and_then(|s| s.parse().ok()) {
                Some(ip) => ip,
                None => continue, // anomalous; skip (mirrors existing path)
            };
            let sid = SpeakerId::new(m.uuid.clone());
            group_speakers.push(SpeakerIdentity {
                id: sid.clone(),
                room_name: m.zone_name.clone(),
                model: None, // ZoneGroupTopology carries no model (D1)
                ip,
            });
            members.push(sid);
        }

        // D3: coordinator first; skip a group whose coordinator is absent
        // from its own member list (anomalous). On the None path group_speakers
        // is dropped - no orphan speakers enter the snapshot.
        match members.iter().position(|s| *s == coord) {
            Some(i) => members.swap(0, i),
            None => continue,
        }
        speakers.extend(group_speakers);
        out_groups.push(GroupIdentity {
            id: GroupId::new(zg.id),
            coordinator: coord,
            members,
        });
    }

    DiscoverySnapshot {
        speakers,
        groups: out_groups,
    }
}

/// Fill in `SpeakerIdentity.model` from each speaker's
/// `device_description.xml` (ZGT carries no model - D1). Parallel,
/// best-effort: a speaker whose fetch fails simply keeps `model = None`.
/// Shared by `discover()` and `refresh_topology()` so both paths populate
/// it consistently.
fn populate_models(snapshot: &mut DiscoverySnapshot) {
    let targets: Vec<(SpeakerId, IpAddr)> = snapshot
        .speakers
        .iter()
        .map(|s| (s.id.clone(), s.ip))
        .collect();
    let models = crate::device_description::fetch_models_parallel(&targets);
    for speaker in &mut snapshot.speakers {
        if let Some(model) = models.get(&speaker.id) {
            speaker.model = Some(model.clone());
        }
    }
}

/// Try each candidate IP for `GetZoneGroupState` until one succeeds or
/// `deadline` elapses since the first attempt - whichever comes first.
/// Extracted so tests can inject a short deadline instead of waiting out
/// the real `TOPOLOGY_REFRESH_DEADLINE`; production always passes that
/// constant. Bounding by elapsed time (not candidate count) is load-bearing:
/// `refresh_topology` runs under `oto_app`'s global SLOT mutex, so trying
/// every cached IP unconditionally would stall every other command for as
/// long as it takes a dead household to exhaust its full candidate list.
fn fetch_group_state_with_deadline(
    client: &SonosClient,
    ips: &[String],
    deadline: Duration,
) -> Result<Vec<ZoneGroupInfo>, WireError> {
    let started = std::time::Instant::now();
    let mut last_err = WireError::NoDevicesFound;
    for ip in ips {
        if started.elapsed() >= deadline {
            break;
        }
        match crate::control::fetch_zone_group_state(client, ip) {
            Ok(g) => return Ok(g),
            Err(e) => last_err = e,
        }
    }
    Err(last_err)
}

impl Wire for SonosWire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError> {
        // v0.5.1 fast-path: when seeded, skip the SSDP sweep entirely and use
        // the seed IPs as the GetZoneGroupState responder candidates - any
        // reachable speaker answers for the whole household (PerNetwork). This
        // is the "discover() minus SSDP" fast path a regroup re-discover uses.
        // Unseeded (`new()`) runs the full multi-NIC SSDP path as before.
        let candidates: Vec<String> = if self.seed_ips.is_empty() {
            let locations = ssdp::discover_locations(SSDP_TIMEOUT)?;
            if locations.is_empty() {
                return Err(WireError::NoDevicesFound);
            }
            // C2: a LOCATION that doesn't yield a parseable IP is dropped here;
            // if every one drops, `candidates` is empty and the diagnostic
            // below fires (distinct from the empty-LAN NoDevicesFound above).
            locations.iter().filter_map(|loc| extract_ip(loc)).collect()
        } else {
            self.seed_ips.iter().map(IpAddr::to_string).collect()
        };
        if candidates.is_empty() {
            // Only reachable on the SSDP path: responders were found but none
            // had a parseable LOCATION. (Seeded candidates are always valid
            // IPs.) Surface a precise diagnostic, not the misleading
            // NoDevicesFound.
            return Err(WireError::Backend(
                "SSDP found responder(s) but none had a parseable LOCATION; \
                 cannot reach ZoneGroupTopology"
                    .into(),
            ));
        }
        // PerNetwork: any reachable speaker returns the whole household.
        // Try responders until one answers (a vanished/asleep unit fails).
        let mut last_err = WireError::NoDevicesFound;
        let mut groups = None;
        for ip in &candidates {
            match control::fetch_zone_group_state(&self.client, ip) {
                Ok(g) => {
                    groups = Some(g);
                    break;
                }
                Err(e) => last_err = e,
            }
        }
        let groups = groups.ok_or(last_err)?;
        let mut snapshot = to_snapshot(groups);
        if snapshot.speakers.is_empty() {
            return Err(WireError::Backend(
                "ZoneGroupTopology yielded 0 usable speakers (all locations unparseable - anomalous)"
                    .into(),
            ));
        }
        self.populate_caches(&snapshot);
        // Repopulate `model` (absent from ZGT - D1) via parallel
        // device_description.xml fetches. Best-effort: failures leave
        // `model = None` and don't fail discovery.
        populate_models(&mut snapshot);
        Ok(snapshot)
    }

    fn play(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_play(&self.client, addr)
    }

    fn pause(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_pause(&self.client, addr)
    }

    fn next(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_next(&self.client, addr)
    }

    fn previous(&self, group: &GroupId) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        control::soap_previous(&self.client, addr)
    }

    fn set_volume(&self, speaker: &SpeakerId, volume: Volume) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_set_volume(&self.client, addr, volume)
    }

    fn set_mute(&self, speaker: &SpeakerId, muted: bool) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        control::soap_set_mute(&self.client, addr, muted)
    }

    fn set_group_volume(&self, group: &GroupId, volume: Volume) -> Result<(), WireError> {
        // Group volume is coordinator-routed (like play/pause): resolve
        // group → coordinator → IP. Unknown/stale group → NotFound.
        let addr = self.resolve_group(group)?;
        grouping::set_group_volume(&self.client, addr, volume)
    }

    fn set_group_mute(&self, group: &GroupId, muted: bool) -> Result<(), WireError> {
        let addr = self.resolve_group(group)?;
        grouping::set_group_mute(&self.client, addr, muted)
    }

    fn join_group(&self, speaker: &SpeakerId, coordinator: &SpeakerId) -> Result<(), WireError> {
        // The join SOAP is sent to the JOINER's IP; confirm the coordinator
        // is a known speaker first (unknown → NotFound) so a bad coordinator
        // id fails as a precondition error, not a confusing device fault.
        let joiner_addr = self.resolve_speaker(speaker)?;
        self.resolve_speaker(coordinator)?;
        grouping::join(&self.client, joiner_addr, coordinator.as_str())
    }

    fn leave_group(&self, speaker: &SpeakerId) -> Result<(), WireError> {
        let addr = self.resolve_speaker(speaker)?;
        grouping::leave(&self.client, addr)
    }

    fn speaker_state(&self, speaker: &SpeakerId) -> Result<SpeakerState, WireError> {
        let speaker_addr = self.resolve_speaker(speaker)?;
        let transport_addr = self.resolve_transport_addr(speaker)?;
        control::soap_speaker_state(&self.client, speaker_addr, transport_addr)
    }

    fn track_position(&self, group: &GroupId) -> Result<TrackPosition, WireError> {
        // Group-addressed: resolve to the coordinator (same path play/pause
        // use); GetPositionInfo is a coordinator query. Unknown group ->
        // NotFound from resolve_group.
        let addr = self.resolve_group(group)?;
        control::soap_track_position(&self.client, addr)
    }

    fn subscribe_topology(&self) -> Result<(), WireError> {
        // Record intent to watch ZoneGroupTopology. The actual SDK
        // `GroupMembership` watch is registered when `subscribe_speakers`
        // builds the pump (the SDK manager lives on the pump thread, so
        // all watches must be registered at spawn time). MUST therefore be
        // called BEFORE `subscribe_speakers` - `discover_with` enforces the
        // ordering. Requires discover() to have populated the caches.
        if self
            .caches
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .id_to_addr
            .is_empty()
        {
            return Err(WireError::NoSpeakersDiscovered);
        }
        // Hold `events_state` across the pump-running check AND the flag
        // store. `subscribe_speakers` reads `topology_requested` (via
        // `snapshot_for_pump`) while holding this same lock as it spawns the
        // pump, so taking it here serialises the two: either we set the flag
        // before the pump reads it (pump gets the watch), or the pump has
        // already spawned and we observe it. Without the shared hold the
        // store could land between the pump-running check and the spawn,
        // leaving a pump with no topology watch yet both calls returning Ok
        // (codex review #67-followup #5; MockWire already did this correctly).
        //
        // If the pump is already running: a repeat call after the flag was
        // already set is a harmless idempotent `Ok`; but if the pump spawned
        // WITHOUT the flag, topology events can never start - fail fast
        // rather than returning a misleading `Ok`.
        let pump_guard = self.events_state.lock().unwrap_or_else(|p| p.into_inner());
        if pump_guard.is_some() && !self.topology_requested.load(Ordering::SeqCst) {
            return Err(WireError::AlreadySubscribed);
        }
        self.topology_requested.store(true, Ordering::SeqCst);
        drop(pump_guard);
        Ok(())
    }

    fn refresh_topology(&self) -> Result<DiscoverySnapshot, WireError> {
        // Re-pull authoritative topology via GetZoneGroupState SOAP - no
        // SSDP. Any reachable speaker returns the whole household
        // (PerNetwork), so try cached IPs until one answers; this handles
        // the case where the first cached speaker has gone to sleep.
        let ips: Vec<String> = {
            let caches = self.caches();
            caches
                .id_to_addr
                .values()
                .map(|addr| addr.ip().to_string())
                .collect()
        };
        if ips.is_empty() {
            return Err(WireError::NoSpeakersDiscovered);
        }
        // Bounded by TOPOLOGY_REFRESH_DEADLINE, not by candidate count - this
        // runs under oto_app's global SLOT mutex (see the constant's doc).
        // On total failure, leave every cache untouched and surface the
        // last error - the caller keeps its previous topology view.
        let groups =
            fetch_group_state_with_deadline(&self.client, &ips, TOPOLOGY_REFRESH_DEADLINE)?;
        let mut snapshot = to_snapshot(groups);
        if snapshot.speakers.is_empty() {
            return Err(WireError::Backend(
                "refresh_topology: ZoneGroupTopology yielded 0 usable speakers".into(),
            ));
        }
        // Deliberately do NOT call `self.populate_caches(&snapshot)` here.
        // The only production caller (`oto_app::refresh_topology`) treats
        // this as a read-only stage-one probe: it uses the returned
        // snapshot's IPs to seed a brand-new `SonosWire`, installed via the
        // atomic `discover_with` wire-replacement path. If that second
        // stage fails, `discover_with` leaves "the previously held wire -
        // if any - intact" - but that previously-held wire is `self`. A
        // self-mutation here would have already overwritten `self`'s
        // resolve_speaker/resolve_group caches with the NEW topology before
        // stage two is known to succeed, so a stage-two failure would leave
        // the OLD wire installed but routing on NEW-topology caches while
        // Dart still shows the OLD topology - installed wire and UI
        // silently disagree. Mutation happens naturally, atomically with
        // the generation bump, when/if stage two succeeds and installs a
        // freshly-discovered wire instead.
        populate_models(&mut snapshot);
        Ok(snapshot)
    }

    fn subscribe_speakers(&self) -> Result<(), WireError> {
        // Wire up the sonos-sdk-state pump thread (v0.4). One
        // shot per wire - repeated calls error with `AlreadySubscribed`.
        //
        // Per-speaker subscription failures do NOT currently surface
        // in-band. The SDK at `=0.5.2` swallows
        // `watch_property_with_subscription` failures internally
        // (state.rs:610-633 - tracing::warn + Ok(option)) and
        // `is_service_subscribed` only reports queue state, not
        // device reachability. A silent subscription failure
        // manifests as the speaker's events simply never arriving
        // (the UI keeps showing the last-known value).
        //
        // Detecting this honestly requires either an SDK feature we
        // don't have at this pin or a wire-side timeout-driven probe
        // (e.g. expected-seed-NOTIFY watchdog). Tracked as v0.5
        // follow-up; see `events::register_watches` for the full SDK
        // source citations.
        let mut guard = self.events_state.lock().unwrap_or_else(|p| p.into_inner());
        if guard.is_some() {
            return Err(WireError::AlreadySubscribed);
        }
        let inputs = self.snapshot_for_pump()?;
        let (pump, rx) = EventPump::spawn(inputs)?;
        *guard = Some(EventsState {
            _pump: pump,
            rx: Some(rx),
        });
        Ok(())
    }

    fn take_event_stream(&self) -> Option<Receiver<ChangeEvent>> {
        // One-shot per wire. Returns the Receiver the first time after
        // `subscribe_speakers`; returns `None` thereafter (or if no
        // subscribe call has happened yet).
        let mut guard = self.events_state.lock().unwrap_or_else(|p| p.into_inner());
        guard.as_mut().and_then(|s| s.rx.take())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_ip_from_location() {
        assert_eq!(
            extract_ip("http://10.83.0.10:1400/xml/device_description.xml"),
            Some("10.83.0.10".to_string())
        );
    }

    /// `new()` leaves `seed_ips` empty → `discover()` takes the full-SSDP
    /// branch; `new_seeded()` stores the IPs → `discover()` skips SSDP and
    /// uses them as responder candidates. Pin the field wiring without a
    /// network call (the SSDP-skip behavior itself is hardware-gated in
    /// `tests/live_grouping.rs::live_seeded_fast_rediscover`).
    #[test]
    fn new_seeded_stores_ips_new_is_empty() {
        assert!(
            SonosWire::new().seed_ips.is_empty(),
            "new() must not seed any IPs (full-SSDP behavior unchanged)"
        );
        let ips = vec![
            "10.0.0.1".parse::<IpAddr>().unwrap(),
            "10.0.0.2".parse::<IpAddr>().unwrap(),
        ];
        let wire = SonosWire::new_seeded(ips.clone());
        assert_eq!(
            wire.seed_ips, ips,
            "new_seeded() must store the seed IPs for the SSDP-skip path"
        );
    }

    /// `refresh_topology` before any `discover()` has populated a cached IP
    /// must fail fast with `NoSpeakersDiscovered` - it has no speaker to
    /// issue `GetZoneGroupState` against. (The "network error leaves caches
    /// unchanged" property is structural: `populate_caches` runs only after
    /// a successful `fetch_zone_group_state`, behind the `?`.)
    #[test]
    fn refresh_topology_before_discover_errors() {
        let wire = SonosWire::new();
        assert_eq!(
            wire.refresh_topology(),
            Err(WireError::NoSpeakersDiscovered)
        );
    }

    /// `refresh_topology` runs under `oto_app`'s global SLOT mutex, so an
    /// unbounded per-IP retry loop stalls every other command for as long as
    /// it takes to try every candidate. Drive the extracted retry helper
    /// directly with a short injected deadline (rather than waiting out the
    /// real `TOPOLOGY_REFRESH_DEADLINE`) against many unreachable candidates:
    /// the FIRST attempt necessarily eats its own real connect-timeout cost
    /// (an in-flight network call can't be interrupted early), but the loop
    /// must check the deadline BEFORE starting each subsequent attempt and
    /// stop - so total time stays close to one attempt's cost, not N.
    #[test]
    fn fetch_group_state_with_deadline_stops_at_deadline_not_candidate_count() {
        // RFC 5737 TEST-NET-1 - guaranteed non-routable, so every attempt
        // genuinely exercises the SOAP client's real connect timeout rather
        // than getting an instant "connection refused". 10 candidates: an
        // unbounded loop trying them all would take ~10x one attempt's cost.
        let ips: Vec<String> = (10..20).map(|n| format!("192.0.2.{n}")).collect();
        let client = SonosClient::new();

        let started = std::time::Instant::now();
        let result = fetch_group_state_with_deadline(&client, &ips, Duration::from_secs(1));
        let elapsed = started.elapsed();

        assert!(result.is_err(), "all candidates are unreachable");
        assert!(
            elapsed < Duration::from_secs(20),
            "took {elapsed:?} against 10 unreachable candidates with a 1s \
             deadline - the loop must stop checking new candidates once the \
             deadline elapses, not try all 10 regardless (that would take \
             roughly 10x a single attempt's real connect-timeout cost)"
        );
    }

    /// `subscribe_topology` before discovery must reject (no cached speakers
    /// to watch); after `populate_caches` it succeeds and is idempotent.
    #[test]
    fn subscribe_topology_gate_and_idempotency() {
        let wire = SonosWire::new();
        assert_eq!(
            wire.subscribe_topology(),
            Err(WireError::NoSpeakersDiscovered),
            "must reject before discovery populates caches"
        );
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                topology_tests::GROUPED_XML,
            )
            .expect("parse"),
        );
        wire.populate_caches(&snap);
        assert!(
            wire.subscribe_topology().is_ok(),
            "ok after caches populated"
        );
        assert!(
            wire.subscribe_topology().is_ok(),
            "idempotent - second call must not error"
        );
        assert!(
            wire.topology_requested.load(Ordering::SeqCst),
            "flag set so the pump registers GroupMembership watches"
        );
    }

    /// Verifies that resolve_group/resolve_speaker return NotFound when the
    /// wire has not been populated yet (simulates pre-discover() state).
    #[test]
    fn resolve_returns_not_found_before_discover() {
        let wire = SonosWire::new();
        let sid = SpeakerId::new("RINCON_UNKNOWN");
        let gid = GroupId::new("RINCON_UNKNOWN:0");

        assert!(matches!(
            wire.resolve_speaker(&sid),
            Err(WireError::NotFound(_))
        ));
        assert!(matches!(
            wire.resolve_group(&gid),
            Err(WireError::NotFound(_))
        ));
        assert!(matches!(
            wire.resolve_transport_addr(&sid),
            Err(WireError::NotFound(_))
        ));
    }

    /// Verifies that `resolve_transport_addr` routes non-coordinator speakers to
    /// their group coordinator (oto-core D2) and coordinators to themselves.
    #[test]
    fn resolve_transport_addr_uses_coordinator() {
        let w = SonosWire::new();
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                super::topology_tests::GROUPED_XML,
            )
            .expect("parse"),
        );
        w.populate_caches(&snap);
        // Living Room is the coordinator; Kitchen is a non-coordinator member.
        let coord = SpeakerId::new("RINCON_542A1B9463A801400");
        let kitchen = SpeakerId::new("RINCON_7828CAE858CA01400");
        let coord_addr = w.resolve_speaker(&coord).expect("coord addr");
        assert_eq!(
            w.resolve_transport_addr(&kitchen)
                .expect("kitchen transport addr"),
            coord_addr,
            "non-coordinator transport must resolve to the coordinator (D2)"
        );
        assert_eq!(
            w.resolve_transport_addr(&coord)
                .expect("coord transport addr"),
            coord_addr,
            "coordinator transport resolves to itself"
        );
    }

    /// A group whose coordinator is absent from its members must be
    /// skipped entirely - zero speakers from that group must leak into the
    /// snapshot. The second, valid group must appear normally.
    #[test]
    fn skipped_group_contributes_no_speakers() {
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                super::topology_tests::GHOST_COORD_XML,
            )
            .expect("parse"),
        );
        // Ghost group skipped → RINCON_REAL must not appear
        assert!(
            !snap.speakers.iter().any(|s| s.id.as_str() == "RINCON_REAL"),
            "RINCON_REAL (member of ghost group) must NOT leak into speakers"
        );
        assert!(
            !snap
                .groups
                .iter()
                .any(|g| g.id.as_str() == "RINCON_GHOST:1"),
            "ghost group must not appear in groups"
        );
        // Valid group is present
        assert_eq!(snap.groups.len(), 1, "exactly one valid group");
        assert_eq!(
            snap.speakers.len(),
            1,
            "exactly one speaker from the valid group"
        );
        assert_eq!(snap.speakers[0].id.as_str(), "RINCON_VALID");
    }

    /// Verifies that the caches are correctly populated via `populate_caches`.
    ///
    /// Uses the real ZoneGroupTopology fixture so the test exercises the same
    /// mapping path that `discover()` uses at runtime. It would fail if the
    /// cache-population step were removed or broken in `discover()`.
    #[test]
    fn caches_populated_after_discover_snapshot() {
        let wire = SonosWire::new();
        let snap = to_snapshot(
            sonos_api::services::zone_group_topology::parse_zone_group_state_xml(
                topology_tests::GROUPED_XML,
            )
            .expect("parse"),
        );
        wire.populate_caches(&snap);

        // Coordinator of the real group
        let sid = SpeakerId::new("RINCON_542A1B9463A801400");
        let gid = GroupId::new("RINCON_542A1B9463A801400:3426502563");

        let addr = wire.resolve_speaker(&sid).expect("should resolve speaker");
        assert_eq!(addr, SocketAddr::new("10.83.0.103".parse().unwrap(), 1400));
        let group_addr = wire.resolve_group(&gid).expect("should resolve group");
        assert_eq!(group_addr, addr);

        // Member (Kitchen speaker)
        let member_sid = SpeakerId::new("RINCON_7828CAE858CA01400");
        let member_addr = wire
            .resolve_speaker(&member_sid)
            .expect("should resolve member");
        assert_eq!(
            member_addr,
            SocketAddr::new("10.83.0.105".parse().unwrap(), 1400)
        );

        // Unknown id → NotFound
        let unknown = SpeakerId::new("RINCON_DOES_NOT_EXIST");
        assert!(matches!(
            wire.resolve_speaker(&unknown),
            Err(WireError::NotFound(_))
        ));
    }
}

#[cfg(test)]
mod topology_tests {
    use super::*;
    use sonos_api::services::zone_group_topology::parse_zone_group_state_xml;

    // Verbatim ZoneGroupState captured 2026-05-19 from the real-hardware
    // `topology_spike` run (PR #21 example / #22 findings). Real Sonos
    // wire format - do not hand-edit; regenerate via the spike if the
    // topology changes. Cited as the regression-fixture authoritative
    // source in `docs/sonos-notes.md` § ZoneGroupState fixture XML.
    // pub(crate): shared with the caches test in mod tests above.
    pub(crate) const GROUPED_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_542A1B9463A801400" ID="RINCON_542A1B9463A801400:3426502563"><ZoneGroupMember UUID="RINCON_542A1B9463A801400" Location="http://10.83.0.103:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="38" TVConfigurationError="0" HdmiCecAvailable="1" WirelessMode="1" ConnectionType="5" ChannelFreq="2417" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="1" SecureRegState="3" VoiceConfigState="2" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" VirtualLineInSource="spotify" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"><Satellite UUID="RINCON_38420B9275BE01400" Location="http://10.83.0.187:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" Invisible="1" SoftwareVersion="94.1-76220" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="108" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="2" ConnectionType="6" ChannelFreq="5660" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="5" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="0" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroupMember><ZoneGroupMember UUID="RINCON_7828CAE858CA01400" Location="http://10.83.0.105:1400/xml/device_description.xml" ZoneName="Kitchen" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="TargetRoomName:Kitchen" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups><VanishedDevices><Device UUID="RINCON_38420B92755401400" ZoneName="Living Room" Reason="UNKNOWN" ModelInfo="S33" Mac="38:42:0B:92:75:54" LastKnownIP="10.83.0.115" LastSeenUTC="2026-05-17T12:38:05Z" MoreInfo="" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" SWGen="2"/></VanishedDevices></ZoneGroupState>"#;

    pub(crate) const COORD_NOT_FIRST_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_542A1B9463A801400" ID="RINCON_542A1B9463A801400:3426502563"><ZoneGroupMember UUID="RINCON_7828CAE858CA01400" Location="http://10.83.0.105:1400/xml/device_description.xml" ZoneName="Kitchen" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="TargetRoomName:Kitchen" SSLPort="1443" HHSSLPort="1843"/><ZoneGroupMember UUID="RINCON_542A1B9463A801400" Location="http://10.83.0.103:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="38" TVConfigurationError="0" HdmiCecAvailable="1" WirelessMode="1" ConnectionType="5" ChannelFreq="2417" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="1" SecureRegState="3" VoiceConfigState="2" MicEnabled="1" HeadphoneSwapActive="0" AirPlayEnabled="1" VirtualLineInSource="spotify" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"><Satellite UUID="RINCON_38420B9275BE01400" Location="http://10.83.0.187:1400/xml/device_description.xml" ZoneName="Living Room" Icon="" Configuration="1" Invisible="1" SoftwareVersion="94.1-76220" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B9275BE01400:RR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" BootSeq="108" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="2" ConnectionType="6" ChannelFreq="5660" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="5" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="0" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroupMember></ZoneGroup></ZoneGroups><VanishedDevices><Device UUID="RINCON_38420B92755401400" ZoneName="Living Room" Reason="UNKNOWN" ModelInfo="S33" Mac="38:42:0B:92:75:54" LastKnownIP="10.83.0.115" LastSeenUTC="2026-05-17T12:38:06Z" MoreInfo="" HTSatChanMapSet="RINCON_542A1B9463A801400:LF,RF;RINCON_38420B92755401400:LR" ActiveZoneID="00745a67-249c-4240-a8c0-4c43b1758510" SWGen="2"/></VanishedDevices></ZoneGroupState>"#;

    // Minimal but parser-valid doc: one group with two members.
    // RINCON_GOOD has a valid IP; RINCON_BAD has "not-an-ip" as host (fails
    // IpAddr::parse) → to_snapshot must skip it.
    // Attribute set copied verbatim from the Kitchen member in GROUPED_XML so
    // parse_zone_group_state_xml accepts the document without modification.
    pub(crate) const BAD_IP_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_GOOD" ID="RINCON_GOOD:1"><ZoneGroupMember UUID="RINCON_GOOD" Location="http://10.83.0.50:1400/xml/device_description.xml" ZoneName="Good Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/><ZoneGroupMember UUID="RINCON_BAD" Location="http://not-an-ip/xml/device_description.xml" ZoneName="Bad Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups></ZoneGroupState>"#;

    // Two groups: the first (RINCON_GHOST) has a coordinator that is NOT among
    // its members (RINCON_REAL is the only member). The second (RINCON_VALID)
    // is a normal solo group. to_snapshot must skip the ghost group entirely -
    // RINCON_REAL must not appear in snapshot.speakers.
    // Member attribute set copied from Kitchen member in GROUPED_XML.
    pub(crate) const GHOST_COORD_XML: &str = r#"<ZoneGroupState><ZoneGroups><ZoneGroup Coordinator="RINCON_GHOST" ID="RINCON_GHOST:1"><ZoneGroupMember UUID="RINCON_REAL" Location="http://10.0.0.9:1400/xml/device_description.xml" ZoneName="Ghost Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup><ZoneGroup Coordinator="RINCON_VALID" ID="RINCON_VALID:2"><ZoneGroupMember UUID="RINCON_VALID" Location="http://10.0.0.10:1400/xml/device_description.xml" ZoneName="Valid Room" Icon="" Configuration="1" SoftwareVersion="94.1-76070" SWGen="2" MinCompatibleVersion="93.0-00000" LegacyCompatibleVersion="58.0-00000" BootSeq="31" TVConfigurationError="0" HdmiCecAvailable="0" WirelessMode="1" ConnectionType="5" ChannelFreq="5220" BehindWifiExtender="0" WifiEnabled="1" EthLink="0" Orientation="0" RoomCalibrationState="4" SecureRegState="3" VoiceConfigState="0" MicEnabled="0" HeadphoneSwapActive="0" AirPlayEnabled="1" IdleState="0" MoreInfo="" SSLPort="1443" HHSSLPort="1843"/></ZoneGroup></ZoneGroups></ZoneGroupState>"#;

    fn snap(xml: &str) -> DiscoverySnapshot {
        to_snapshot(parse_zone_group_state_xml(xml).expect("parse"))
    }

    #[test]
    fn grouped_topology_maps_real_group() {
        let s = snap(GROUPED_XML);
        assert_eq!(s.groups.len(), 1, "one real group");
        let g = &s.groups[0];
        assert_eq!(g.coordinator.as_str(), "RINCON_542A1B9463A801400");
        assert_eq!(g.members.len(), 2, "Living Room + Kitchen");
        assert_eq!(g.members[0], g.coordinator, "coordinator first (D3)");
        assert!(
            !s.speakers
                .iter()
                .any(|sp| sp.id.as_str() == "RINCON_38420B9275BE01400"),
            "Invisible satellite must not be a speaker"
        );
        assert_eq!(s.speakers.len(), 2, "two real speakers, satellite folded");
        let lr = s
            .speakers
            .iter()
            .find(|sp| sp.room_name == "Living Room")
            .expect("Living Room speaker missing in grouped snapshot");
        assert_eq!(lr.model, None, "D1: model is None");
        assert_eq!(
            lr.id.as_str(),
            "RINCON_542A1B9463A801400",
            "no uuid: prefix in ZGS"
        );
    }

    #[test]
    fn coordinator_reordered_first() {
        let s = snap(COORD_NOT_FIRST_XML);
        let g = &s.groups[0];
        assert_eq!(
            g.members[0], g.coordinator,
            "must reorder coordinator to index 0"
        );
    }

    #[test]
    fn skips_member_with_unparseable_ip() {
        let s = snap(BAD_IP_XML);
        assert_eq!(s.speakers.len(), 1, "bad-IP member skipped");
        assert_eq!(s.speakers[0].id.as_str(), "RINCON_GOOD");
        assert_eq!(s.groups.len(), 1);
        assert_eq!(
            s.groups[0].members,
            vec![s.groups[0].coordinator.clone()],
            "skipped member absent from group membership too"
        );
    }
}
