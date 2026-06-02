//! The `Wire` seam — the trait `oto-app` depends on instead of
//! `sonos-sdk` (or any direct Sonos library). v0.2: discovery + playback
//! commands + a one-shot state read. v0.3: real ZoneGroupTopology grouping;
//! signatures unchanged as designed.

use std::{fmt, sync::mpsc::Receiver};

use crate::{
    events::ChangeEvent,
    identifiers::{GroupId, SpeakerId},
    identity::DiscoverySnapshot,
    state::SpeakerState,
    volume::Volume,
};

/// The `Wire` seam. `oto-app` depends on this trait, never on a Sonos
/// library directly (`oto-wire` uses `sonos-api`; `oto-mock` is LAN-free).
///
/// Addressing: playback is per-coordinator, so play/pause/next/previous take
/// a `GroupId`; the impl resolves group → coordinator → IP from the
/// ZoneGroupTopology cache (v0.1/v0.2 used group-of-one — each speaker was
/// its own group; v0.3 uses real ZoneGroupTopology without changing these
/// signatures). `speaker_state` reads volume/mute per-speaker and transport
/// at the group coordinator (D2). volume/mute/state are per-`SpeakerId`.
/// All methods block (SOAP).
pub trait Wire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError>;

    fn play(&self, group: &GroupId) -> Result<(), WireError>;
    fn pause(&self, group: &GroupId) -> Result<(), WireError>;
    fn next(&self, group: &GroupId) -> Result<(), WireError>;
    fn previous(&self, group: &GroupId) -> Result<(), WireError>;

    fn set_volume(&self, speaker: &SpeakerId, volume: Volume) -> Result<(), WireError>;
    fn set_mute(&self, speaker: &SpeakerId, muted: bool) -> Result<(), WireError>;

    fn speaker_state(&self, speaker: &SpeakerId) -> Result<SpeakerState, WireError>;

    /// Register v0.4 property-event interest for all currently-known
    /// speakers (per the latest `discover()`). Activates the upstream
    /// subscription + the wire's pump thread. One-shot per wire.
    ///
    /// Returns `WireError::NoSpeakersDiscovered` if the wire has no
    /// discovery snapshot yet, `WireError::AlreadySubscribed` if
    /// called twice on the same wire. Runtime per-speaker
    /// subscription failures surface in-band as
    /// `ChangeEvent::SubscriptionError`, not via this `Result`.
    fn subscribe_speakers(&self) -> Result<(), WireError>;

    /// Register v0.5 topology-event interest (ZoneGroupTopology /
    /// `GroupMembership`) for all currently-known speakers. Emits
    /// `ChangeEvent::TopologyChanged` on the unified stream when the
    /// household is regrouped.
    ///
    /// **Ordering — must be called BEFORE `subscribe_speakers`.** The
    /// topology watch is registered when `subscribe_speakers` spawns the
    /// event pump, so this call only records intent; calling it after the
    /// pump is running is too late. `discover_with` enforces the ordering
    /// (it calls `subscribe_topology` then `subscribe_speakers`).
    ///
    /// Requires a prior successful `discover()` (else
    /// `NoSpeakersDiscovered`). Idempotent while the pump is not yet
    /// running: repeated pre-`subscribe_speakers` calls return `Ok`. Once
    /// the pump is running it returns `Ok` if topology was already
    /// requested (the watch is active), but `AlreadySubscribed` if it was
    /// not — failing fast on the misuse rather than silently no-op'ing.
    fn subscribe_topology(&self) -> Result<(), WireError>;

    /// Re-fetch the current topology via `GetZoneGroupState` SOAP
    /// against a cached speaker IP — no SSDP. Returns a fresh
    /// `DiscoverySnapshot`. Network errors leave all existing caches
    /// unchanged.
    ///
    /// Requires a prior successful `discover()` to have a cached IP.
    fn refresh_topology(&self) -> Result<DiscoverySnapshot, WireError>;

    /// Take the unified event-stream receiver. Returns `None` if
    /// already taken or if no `subscribe_*` call has activated the
    /// pump yet. May be called before or after `subscribe_speakers`;
    /// events flow only once at least one `subscribe_*` is active.
    fn take_event_stream(&self) -> Option<Receiver<ChangeEvent>>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WireError {
    /// Transport-level failure: no usable IPv4 interface / SSDP socket
    /// error during discovery, or a connection failure on a command or
    /// state-read SOAP call.
    Network(String),
    /// SSDP completed but found zero Sonos devices.
    NoDevicesFound,
    /// A device was reached but the request failed: device-description
    /// fetch/parse during discovery, or a SOAP fault / response-parse
    /// failure on a command or state read.
    Backend(String),
    /// Command target (speaker/group id) is not in the current snapshot,
    /// or no discovery has populated the wire yet. A precondition error,
    /// distinct from a transport failure.
    NotFound(String),
    /// `subscribe_speakers` was called before a successful `discover()`.
    NoSpeakersDiscovered,
    /// `subscribe_speakers` was called more than once on the same wire.
    AlreadySubscribed,
}

impl fmt::Display for WireError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WireError::Network(m) => write!(f, "network error: {m}"),
            WireError::NoDevicesFound => {
                write!(f, "no Sonos devices found on the network")
            }
            WireError::Backend(m) => write!(f, "backend error: {m}"),
            WireError::NotFound(w) => write!(f, "not found: {w}"),
            WireError::NoSpeakersDiscovered => {
                write!(f, "subscribe_speakers called before discovery")
            }
            WireError::AlreadySubscribed => {
                write!(f, "subscribe_speakers already called on this wire")
            }
        }
    }
}

impl std::error::Error for WireError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_strings() {
        assert_eq!(
            WireError::NoDevicesFound.to_string(),
            "no Sonos devices found on the network"
        );
        assert_eq!(
            WireError::Network("bind failed".into()).to_string(),
            "network error: bind failed"
        );
        assert_eq!(
            WireError::Backend("parse failed".into()).to_string(),
            "backend error: parse failed"
        );
        assert_eq!(
            WireError::NotFound("RINCON_X".into()).to_string(),
            "not found: RINCON_X"
        );
        assert_eq!(
            WireError::NoSpeakersDiscovered.to_string(),
            "subscribe_speakers called before discovery"
        );
        assert_eq!(
            WireError::AlreadySubscribed.to_string(),
            "subscribe_speakers already called on this wire"
        );
    }
}
