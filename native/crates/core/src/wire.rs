//! The `Wire` seam — the trait `oto-app` depends on instead of
//! `sonos-sdk`. v0.2: discovery + playback commands + a one-shot state
//! read; see the `Wire` doc for the v0.3 addressing seam.

use std::fmt;

use crate::{
    identifiers::{GroupId, SpeakerId},
    identity::DiscoverySnapshot,
    state::SpeakerState,
    volume::Volume,
};

/// The `Wire` seam. `oto-app` depends on this trait, never on `sonos-sdk`.
///
/// Addressing is the v0.3 seam: playback is per-coordinator, so
/// play/pause/next/previous take a `GroupId`; the impl resolves
/// group-of-one → coordinator → IP. v0.2 resolution is trivial (the
/// group's sole member is its coordinator); v0.3 swaps in real
/// ZoneGroupTopology resolution **without changing these signatures**.
/// volume/mute/state are per-`SpeakerId`. All methods block (SOAP).
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
    /// No usable IPv4 interface, or SSDP send/socket failure.
    Network(String),
    /// SSDP completed but found zero Sonos devices.
    NoDevicesFound,
    /// Device-description fetch or parse failed (HTTP/XML stage).
    Backend(String),
    /// Command target (speaker/group id) is not in the current snapshot,
    /// or no discovery has populated the wire yet. A precondition error,
    /// distinct from a transport failure.
    NotFound(String),
}

impl fmt::Display for WireError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WireError::Network(m) => write!(f, "discovery network error: {m}"),
            WireError::NoDevicesFound => {
                write!(f, "no Sonos devices found on the network")
            }
            WireError::Backend(m) => write!(f, "discovery backend error: {m}"),
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
            "discovery network error: bind failed"
        );
        assert_eq!(
            WireError::Backend("parse failed".into()).to_string(),
            "discovery backend error: parse failed"
        );
        assert_eq!(
            WireError::NotFound("RINCON_X".into()).to_string(),
            "not found: RINCON_X"
        );
    }
}
