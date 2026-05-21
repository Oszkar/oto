use oto_app::discover as app_discover;

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

// ── Discovery ─────────────────────────────────────────────────────────────────

// TODO(v0.5): Android release discovery needs a held WifiManager.MulticastLock
// (perms are declared in app/android/app/src/main/AndroidManifest.xml); SSDP
// multicast is dropped without it. v0.1 discovery is verified on Windows via
// this bridge.
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

// ── DEV-ONLY: v0.4 FRB Stream pre-check ─────────────────────────────────────
//
// TODO(v0.4): remove this entire section when `subscribe_change_events`
// lands. These functions exist only to empirically verify FRB v2's
// Stream<T> semantics (threading, drop/cancel detection, error
// propagation) before designing the real event-stream surface. Findings
// note: docs/superpowers/specs/2026-05-22-v0.4-frb-precheck-findings.md.

use std::sync::atomic::{AtomicU32, Ordering};

use crate::frb_generated::StreamSink;

/// Counts how many times a `dev_tick_stream` invocation observed Dart-side
/// subscription drop (the sink returning `Err` on `add`). The precheck test
/// snapshots this before + after a cancellation to prove the Rust side can
/// detect cancel without polling. `AtomicU32` matches the FRB-exposed
/// return type of `dev_cancel_observations_count` exactly — no truncation
/// cast at the boundary.
static DEV_CANCEL_OBSERVATIONS: AtomicU32 = AtomicU32::new(0);

/// DEV-ONLY: emits `count` monotonically increasing u64 ticks, `interval_ms`
/// apart, then terminates. Returns early — incrementing
/// `DEV_CANCEL_OBSERVATIONS` — if `sink.add` returns `Err`, which happens
/// when the Dart subscriber cancels.
pub fn dev_tick_stream(sink: StreamSink<u64>, interval_ms: u32, count: u32) {
    for i in 0..count {
        if sink.add(u64::from(i)).is_err() {
            DEV_CANCEL_OBSERVATIONS.fetch_add(1, Ordering::Relaxed);
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(u64::from(interval_ms)));
    }
}

/// DEV-ONLY: emits 3 ticks at 50 ms apart, then `sink.add_error(...)` —
/// the correct in-band channel for stream errors. (Returning `Err` from
/// a StreamSink fn does NOT propagate to the Dart Stream's `onError`;
/// the generated binding wraps the function call in `unawaited(...)`
/// and the error becomes an unhandled async exception. Verified
/// empirically during the precheck — see the findings note.)
pub fn dev_error_stream(sink: StreamSink<u64>) {
    for i in 0..3 {
        sink.add(i).ok();
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    sink.add_error("intentional error from dev_error_stream".to_string())
        .ok();
}

/// DEV-ONLY: read the cancel-observation counter (see `DEV_CANCEL_OBSERVATIONS`).
pub fn dev_cancel_observations_count() -> u32 {
    DEV_CANCEL_OBSERVATIONS.load(Ordering::Relaxed)
}
