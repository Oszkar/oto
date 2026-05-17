//! The `Wire` seam. `oto-app` depends on this trait, never on `sonos-sdk`.
//! Minimal for v0.1: one identity-only discovery method.

use std::fmt;

use crate::identity::DiscoverySnapshot;

/// One-shot identity discovery. Blocking. Implemented by `oto-wire`
/// (production) and `oto-mock` (tests).
pub trait Wire {
    fn discover(&self) -> Result<DiscoverySnapshot, WireError>;
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
