#![deny(unsafe_code)]

//! `oto-app` — owns runtime state (the active `Wire`) and routes the
//! discover command. See docs/plans/2026-05-15-frb-discover-command-design.md.

use std::sync::{Mutex, OnceLock};

use oto_core::{DiscoverySnapshot, Wire, WireError};
use oto_wire::SonosWire;

type HeldWire = Box<dyn Wire + Send>;

fn slot() -> &'static Mutex<Option<HeldWire>> {
    static SLOT: OnceLock<Mutex<Option<HeldWire>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(None))
}

/// Construct a wire, run discovery, and on success replace the held
/// wire (so v0.2 playback can act on it). On failure the previously
/// held wire — if any — is left intact.
pub fn discover_with(make: impl FnOnce() -> HeldWire) -> Result<DiscoverySnapshot, WireError> {
    let wire = make();
    let snapshot = wire.discover()?;
    *slot().lock().expect("wire slot poisoned") = Some(wire);
    Ok(snapshot)
}

/// Production entry point: discovery backed by `SonosWire`.
pub fn discover() -> Result<DiscoverySnapshot, WireError> {
    discover_with(|| Box::new(SonosWire::new()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use oto_mock::MockWire;

    #[test]
    fn success_then_failure_keeps_prior_wire() {
        // success stores a wire and returns the fixture
        let snap = discover_with(|| Box::new(MockWire::default())).unwrap();
        assert_eq!(snap.speakers.len(), 3);

        // failure returns Err but does not clear the held wire
        let err = discover_with(|| Box::new(MockWire::failing(WireError::NoDevicesFound)));
        assert_eq!(err, Err(WireError::NoDevicesFound));
        assert!(slot().lock().unwrap().is_some());
    }
}
