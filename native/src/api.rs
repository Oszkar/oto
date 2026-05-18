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

// TODO(v0.4): Android release discovery needs a held WifiManager.MulticastLock
// (perms are declared in app/android/app/src/main/AndroidManifest.xml); SSDP
// multicast is dropped without it. v0.1 discovery is verified on Windows via
// this bridge.
/// Deferred warm-up. Blocking ~3–5 s; FRB runs it off the UI isolate.
/// NOT on the #[frb(init)] path. Identity-only snapshot.
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

/// Set `speaker_id`'s volume. `volume` is clamped to `0..=100` at the bridge
/// boundary (Dart may send any `u32`). Blocking SOAP round-trip; Dart `Future`.
pub fn set_volume(speaker_id: String, volume: u32) -> Result<(), CommandError> {
    let id = oto_core::SpeakerId::new(speaker_id);
    // `as i32` then clamp(0,100): a `u32 > i32::MAX` wraps negative and
    // floors to 0 — a volume setter is forgiving (never panics/rejects).
    let vol = oto_core::Volume::clamped(volume as i32);
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
