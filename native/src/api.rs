use oto_app::discover as app_discover;

use crate::frb_generated::StreamSink;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub struct Topology {
    pub speakers: Vec<DiscoveredSpeaker>,
    pub groups: Vec<DiscoveredGroup>,
}

pub struct DiscoveredSpeaker {
    pub id: String,
    pub room_name: String,
    pub model: Option<String>,
    pub ip: String,
}

pub struct DiscoveredGroup {
    pub id: String,
    pub coordinator: String,
    pub members: Vec<String>,
}

pub enum DiscoveryError {
    Network(String),
    NoDevicesFound,
    Sdk(String),
}

// ── v0.2 DTOs ────────────────────────────────────────────────────────────────

pub struct SpeakerStateDto {
    pub volume: Option<u32>,
    pub muted: Option<bool>,
    pub transport: Option<TransportDto>,
}

pub struct TransportDto {
    pub state: PlaybackStateDto,
    pub position_secs: Option<u64>,
    pub current_track: Option<TrackDto>,
}

pub enum PlaybackStateDto {
    Stopped,
    Playing,
    Paused,
    Transitioning,
}

pub struct TrackDto {
    pub id: Option<String>,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub track_number: Option<u32>,
    pub duration_secs: Option<u64>,
    pub art_uri: Option<String>,
    pub uri: Option<String>,
}

pub enum CommandError {
    NotFound(String),
    Network(String),
    Sonos(String),
}

// ── v0.4 event DTOs ──────────────────────────────────────────────────────────

/// FRB DTO for `oto_core::ChangeEvent`. Volume + the Subscription*
/// variants landed in Slice 1; Mute / Playback / Track (Slice 2) cover
/// the rest of the v0.4 property surface. Per spec § 4:
///   - Volume / Mute are per-speaker (carry `speaker_id`).
///   - Playback / Track are per-group (carry `group_id`).
pub enum ChangeEventDto {
    Volume {
        speaker_id: String,
        volume: u32,
    },
    Mute {
        speaker_id: String,
        muted: bool,
    },
    Playback {
        group_id: String,
        state: PlaybackStateDto,
    },
    Track {
        group_id: String,
        track: TrackDto,
    },
    SubscriptionError {
        speaker_id: String,
        message: String,
    },
    SubscriptionRecovered {
        speaker_id: String,
    },
    /// Household topology changed (speakers regrouped). Payload-less: the
    /// Dart `TopologyController` debounces then re-pulls topology on
    /// receipt (v0.5 S1: invalidates `discoveryProvider` → full
    /// re-discover; v0.6 may swap in a lighter SOAP refresh).
    TopologyChanged,
}

// ── Discovery ─────────────────────────────────────────────────────────────────

// Android release discovery holds a WifiManager.MulticastLock around this
// SSDP window — acquired/released on the Dart side (discoveryProvider) via
// the `me.oszkar.oto/multicast_lock` MethodChannel (v0.5 S3). Without it
// Android drops the inbound SSDP multicast replies.
/// Deferred warm-up. Blocking ~3–5 s; FRB runs it off the UI isolate.
/// NOT on the #[frb(init)] path. The returned snapshot carries the
/// topology — speaker identities (id / room / model / ip) plus the
/// group identities they belong to, with the coordinator at
/// `members[0]` (D3) — but no live state: volume, mute, and transport
/// are read separately via `speaker_state`. Live state will move to an
/// event-fed cache in v0.4 (ARCHITECTURE.md Open Q7).
pub fn discover() -> Result<Topology, DiscoveryError> {
    // Glue only: delegate inward, then the representational map (tested
    // LAN-free in `native/tests/`; see `crate::map`).
    let snap = app_discover().map_err(crate::map::to_discovery_error)?;
    Ok(crate::map::to_topology(snap))
}

// ── v0.2 commands ─────────────────────────────────────────────────────────────

/// Start playback on `group_id` (routed to its coordinator). Blocking SOAP
/// round-trip; FRB surfaces this as a Dart `Future`.
pub fn play(group_id: String) -> Result<(), CommandError> {
    let id = oto_core::GroupId::new(group_id);
    oto_app::play(&id).map_err(crate::map::to_command_error)
}

/// Pause playback on `group_id`. Blocking SOAP round-trip; Dart `Future`.
pub fn pause(group_id: String) -> Result<(), CommandError> {
    let id = oto_core::GroupId::new(group_id);
    oto_app::pause(&id).map_err(crate::map::to_command_error)
}

/// Skip to the next track on `group_id`. Blocking SOAP round-trip; Dart `Future`.
pub fn next(group_id: String) -> Result<(), CommandError> {
    let id = oto_core::GroupId::new(group_id);
    oto_app::next(&id).map_err(crate::map::to_command_error)
}

/// Skip to the previous track on `group_id`. Blocking SOAP round-trip; Dart `Future`.
pub fn previous(group_id: String) -> Result<(), CommandError> {
    let id = oto_core::GroupId::new(group_id);
    oto_app::previous(&id).map_err(crate::map::to_command_error)
}

/// Set `speaker_id`'s volume, clamped to `0..=100` by `oto_core::Volume`.
/// The param is **signed** so a negative Dart `int` reaches Rust and
/// clamps to 0 (a `u32` param would throw at FRB's encoder before Rust
/// could clamp). A Dart `int` outside `i32` is rejected at the bridge —
/// unreachable for a volume; the v0.6 UI bounds the slider regardless.
/// Blocking SOAP round-trip; Dart `Future`.
pub fn set_volume(speaker_id: String, volume: i32) -> Result<(), CommandError> {
    let id = oto_core::SpeakerId::new(speaker_id);
    // oto_core::Volume::clamped(i32) is the authoritative 0..=100 clamp.
    let vol = oto_core::Volume::clamped(volume);
    oto_app::set_volume(&id, vol).map_err(crate::map::to_command_error)
}

/// Set `speaker_id`'s mute state. Blocking SOAP round-trip; Dart `Future`.
pub fn set_mute(speaker_id: String, muted: bool) -> Result<(), CommandError> {
    let id = oto_core::SpeakerId::new(speaker_id);
    oto_app::set_mute(&id, muted).map_err(crate::map::to_command_error)
}

/// One-shot read of `speaker_id`'s current volume/mute/transport snapshot.
/// Blocking SOAP round-trip; Dart `Future`.
pub fn speaker_state(speaker_id: String) -> Result<SpeakerStateDto, CommandError> {
    let id = oto_core::SpeakerId::new(speaker_id);
    let state = oto_app::speaker_state(&id).map_err(crate::map::to_command_error)?;
    Ok(crate::map::to_speaker_state_dto(state))
}

// ── v0.4 DEV-ONLY: MockWire injection for integration tests ───────────────────
//
// TODO(v0.6): consider removing once the integration test pattern no longer
// needs it. Until then, this is the only FRB-side seam to drive the LAN-free
// end-to-end tests in `app/integration_test/v0_4_events_test.dart` (incl. the
// v0.5 TopologyChanged delivery test).
//
// Trust boundary (per /codex review on PR #43, finding P1 #2): the FRB
// fn symbols (`dev_discover_mock`, `dev_push_subscription_error_on_mock`)
// must exist unconditionally — FRB v2's generated `frb_generated.rs`
// references every exposed `pub fn` and a cfg gate at the symbol level
// breaks the release cdylib link. But the BODIES are `cfg(debug_assertions)`
// gated: in release builds they return an error, so a release-built Dart
// client cannot use them to replace the production wire with a mock or
// inject fake events. All supporting machinery (`MockWireArc`,
// `dev_mock_handle`, `Arc/OnceLock/MockWire` imports) is fully cfg-gated
// out of release builds.

#[cfg(debug_assertions)]
use std::sync::{Arc, OnceLock};

#[cfg(debug_assertions)]
use oto_mock::MockWire;

/// Side-channel handle to the MockWire created by `dev_discover_mock`.
/// `dev_push_subscription_error_on_mock` reaches in here because
/// `MockWire::push_event` is an inherent method (not on the `Wire`
/// trait — adversarial pushes are a test-only affordance), so the
/// regular `oto_app::slot()` path can't surface it.
#[cfg(debug_assertions)]
fn dev_mock_handle() -> &'static std::sync::Mutex<Option<Arc<MockWire>>> {
    static MOCK: OnceLock<std::sync::Mutex<Option<Arc<MockWire>>>> = OnceLock::new();
    MOCK.get_or_init(|| std::sync::Mutex::new(None))
}

/// DEV-ONLY: drive discovery via MockWire (debug builds only). In release
/// builds the body is a no-op that returns `DiscoveryError::Sdk` — the
/// symbol is preserved so FRB-generated bindings still link, but the
/// production wire cannot be replaced from a release-built Dart client.
pub fn dev_discover_mock() -> Result<Topology, DiscoveryError> {
    #[cfg(debug_assertions)]
    {
        let mock = Arc::new(MockWire::default());
        // Keep a side reference so dev_push_subscription_error_on_mock can
        // call push_event on the SAME instance that's in oto_app::slot().
        *dev_mock_handle().lock().unwrap_or_else(|p| p.into_inner()) = Some(Arc::clone(&mock));
        let mock_for_app = Arc::clone(&mock);
        let snap = oto_app::discover_with(move || Box::new(MockWireArc(mock_for_app)))
            .map_err(crate::map::to_discovery_error)?;
        Ok(crate::map::to_topology(snap))
    }
    #[cfg(not(debug_assertions))]
    {
        Err(DiscoveryError::Sdk(
            "dev_discover_mock is debug-only; not available in release builds".into(),
        ))
    }
}

/// DEV-ONLY: push a `SubscriptionError` event into the held MockWire's
/// channel (debug builds only). Returns an error if `dev_discover_mock`
/// hasn't run yet. In release builds the body is a no-op that returns
/// `CommandError::Sonos`.
pub fn dev_push_subscription_error_on_mock(
    speaker_id: String,
    message: String,
) -> Result<(), CommandError> {
    #[cfg(debug_assertions)]
    {
        let guard = dev_mock_handle().lock().unwrap_or_else(|p| p.into_inner());
        let mock = guard
            .as_ref()
            .ok_or_else(|| CommandError::NotFound("dev_discover_mock not called yet".into()))?;
        mock.push_event(oto_core::ChangeEvent::SubscriptionError {
            speaker: oto_core::SpeakerId::new(speaker_id),
            message,
        });
        Ok(())
    }
    #[cfg(not(debug_assertions))]
    {
        // Silence unused-parameter warnings in release builds without
        // changing the FRB-visible signature.
        let _ = (speaker_id, message);
        Err(CommandError::Sonos(
            "dev_push_subscription_error_on_mock is debug-only; not available in release builds"
                .into(),
        ))
    }
}

/// DEV-ONLY: push a `TopologyChanged` event into the held MockWire's
/// channel (debug builds only). Mirrors `dev_push_subscription_error_on_mock`
/// — the integration test uses it to drive the v0.5 topology-event path
/// (FRB stream delivery of `ChangeEventDto::TopologyChanged`) without a LAN.
/// Returns an error if `dev_discover_mock` hasn't run yet. In release builds
/// the body is a no-op that returns `CommandError::Sonos`.
pub fn dev_push_topology_change_on_mock() -> Result<(), CommandError> {
    #[cfg(debug_assertions)]
    {
        let guard = dev_mock_handle().lock().unwrap_or_else(|p| p.into_inner());
        let mock = guard
            .as_ref()
            .ok_or_else(|| CommandError::NotFound("dev_discover_mock not called yet".into()))?;
        mock.push_topology_change();
        Ok(())
    }
    #[cfg(not(debug_assertions))]
    {
        Err(CommandError::Sonos(
            "dev_push_topology_change_on_mock is debug-only; not available in release builds"
                .into(),
        ))
    }
}

/// Newtype wrapping `Arc<MockWire>` so it implements `Wire` and can be
/// boxed into the `oto_app::slot()`. We can't `Box<Arc<MockWire>>`
/// directly because the slot holds `Box<dyn Wire>` and `Arc<T>` itself
/// doesn't impl `Wire` (the impl is on `T`).
#[cfg(debug_assertions)]
struct MockWireArc(Arc<MockWire>);

#[cfg(debug_assertions)]
impl oto_core::Wire for MockWireArc {
    fn discover(&self) -> Result<oto_core::DiscoverySnapshot, oto_core::WireError> {
        self.0.discover()
    }
    fn play(&self, group: &oto_core::GroupId) -> Result<(), oto_core::WireError> {
        self.0.play(group)
    }
    fn pause(&self, group: &oto_core::GroupId) -> Result<(), oto_core::WireError> {
        self.0.pause(group)
    }
    fn next(&self, group: &oto_core::GroupId) -> Result<(), oto_core::WireError> {
        self.0.next(group)
    }
    fn previous(&self, group: &oto_core::GroupId) -> Result<(), oto_core::WireError> {
        self.0.previous(group)
    }
    fn set_volume(
        &self,
        speaker: &oto_core::SpeakerId,
        volume: oto_core::Volume,
    ) -> Result<(), oto_core::WireError> {
        self.0.set_volume(speaker, volume)
    }
    fn set_mute(
        &self,
        speaker: &oto_core::SpeakerId,
        muted: bool,
    ) -> Result<(), oto_core::WireError> {
        self.0.set_mute(speaker, muted)
    }
    fn speaker_state(
        &self,
        speaker: &oto_core::SpeakerId,
    ) -> Result<oto_core::SpeakerState, oto_core::WireError> {
        self.0.speaker_state(speaker)
    }
    fn subscribe_speakers(&self) -> Result<(), oto_core::WireError> {
        self.0.subscribe_speakers()
    }
    fn subscribe_topology(&self) -> Result<(), oto_core::WireError> {
        self.0.subscribe_topology()
    }
    fn refresh_topology(&self) -> Result<oto_core::DiscoverySnapshot, oto_core::WireError> {
        self.0.refresh_topology()
    }
    fn take_event_stream(&self) -> Option<std::sync::mpsc::Receiver<oto_core::ChangeEvent>> {
        self.0.take_event_stream()
    }
}

// ── v0.4 event stream ────────────────────────────────────────────────────────

/// Subscribe to the unified v0.4 change-event stream. One call per app
/// instance; the Dart `changeEventsProvider` is the consumer.
/// Stream completes (`onDone` fires) when `discover()` replaces the
/// wire — the Dart provider depends on `discoveryProvider` and
/// auto-rebuilds. Cancel detection via `sink.add(...).is_err()`
/// (FRB pre-check § 3).
pub fn subscribe_change_events(sink: StreamSink<ChangeEventDto>) {
    // Body runs on the FRB worker thread (pre-check § 2). Blocking
    // `recv()` here is fine — it blocks the worker, not the UI.
    let Some(rx) = oto_app::take_event_stream() else {
        // No wire installed yet, or stream already taken. The Dart
        // provider depends on `discoveryProvider`; once discover()
        // succeeds, this fn will be called again against the new wire.
        return;
    };
    // Capture the generation this consumer belongs to. If a future
    // `discover_with` runs concurrently, it bumps the generation; our
    // `apply_event_at_generation` calls then no-op so we cannot
    // pollute the NEW wire's freshly-seeded cache with leftover
    // events from the OLD wire's channel. The `sink.add(...)` path
    // still surfaces these events to the Dart subscriber on the OLD
    // stream until the rx Sender is dropped and `recv()` returns
    // Err — that's correct because the OLD subscriber is the one
    // listening on this sink.
    let gen = oto_app::current_generation();
    // Apply one event to the cache + forward it to Dart. Returns `false`
    // if the Dart subscriber cancelled (the caller should then return).
    let emit = |event: oto_core::ChangeEvent| -> bool {
        oto_app::apply_event_at_generation(gen, &event);
        sink.add(crate::map::to_change_event_dto(event)).is_ok()
    };
    loop {
        // Drain TWO sources onto the one FRB stream (v0.5 S2):
        //   1. oto-app's sibling bus — SubscriptionError/Recovered emitted
        //      on command-dispatch health transitions,
        //   2. the wire's v0.4 channel (`rx`) — property events from the
        //      pump; its `Disconnected` is the teardown signal (wire
        //      replaced on discover() → stream completes → Dart rebuilds).
        //
        // Drain the app bus FIRST, fully, every iteration — otherwise a
        // busy wire channel could starve app events indefinitely (review
        // #65). Drain at OUR generation so a stale event from an old wire
        // is dropped, not forwarded onto this stream (review #67-followup
        // #3). The app bus never disconnects (it's process-global), so only
        // the wire channel drives loop exit.
        while let Some(event) = oto_app::try_recv_app_event(gen) {
            if !emit(event) {
                return;
            }
        }
        // Then block on the wire channel with a coarse poll so an idle
        // stream doesn't busy-wake (review #67-followup #6: a 10 ms poll
        // span at 100 Hz when nothing's happening). 250 ms bounds both the
        // app-bus re-drain cadence and teardown-detection latency — fine,
        // app events are degraded-state flags, not real-time, and teardown
        // is not latency-critical. When events flow the inner drains + the
        // Ok arm keep the loop hot regardless.
        match rx.recv_timeout(std::time::Duration::from_millis(250)) {
            Ok(event) => {
                if !emit(event) {
                    return;
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            // Wire's Sender dropped — wire was replaced (discover() ran).
            // Return cleanly; FRB stream completes; Dart rebuilds.
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return,
        }
    }
}

/// The current wire generation — bumped by `discover_with` on every
/// **successful** wire install. The Dart event-stream provider keys its
/// re-subscription on this so a FAILED re-discover (which does not bump it)
/// doesn't tear down the live stream into a one-shot, un-retakeable receiver
/// (review #67-followup #2). `#[frb(sync)]` — a cheap atomic read, called
/// inline from a Riverpod `select`, so it must not be a `Future`.
#[flutter_rust_bridge::frb(sync)]
pub fn current_wire_generation() -> u64 {
    oto_app::current_generation()
}
