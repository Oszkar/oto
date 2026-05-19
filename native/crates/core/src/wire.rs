//! The `Wire` seam — the trait `oto-app` depends on instead of
//! `sonos-sdk` (or any direct Sonos library). v0.2: discovery + playback
//! commands + a one-shot state read. v0.3: real ZoneGroupTopology grouping;
//! signatures unchanged as designed.

use std::fmt;

use crate::{
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
    }
}
