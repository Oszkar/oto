//! Representational mapping: `oto_core` domain types → the FRB DTOs defined
//! in [`crate::api`].
//!
//! Deliberately **not** in `crate::api` (FRB's `rust_input`), so this is plain
//! testable Rust the `native/tests/` e2e can drive LAN-free. That closes the
//! bridge-DTO half of the v0.1 acceptance bar (plan deviation D2): the e2e
//! drives `oto_app::discover_with(MockWire)` and then asserts *this* map,
//! proving domain↔bridge-DTO with zero LAN. Keeping it here also keeps
//! `api.rs` a pure shim (AGENTS.md §4: `oto_native` is glue only).
//!
//! Pure and total: no I/O, no failure modes of its own — every `WireError`
//! has exactly one `DiscoveryError` image and every snapshot maps 1:1.

use oto_core::{DiscoverySnapshot, WireError};

use crate::api::{DiscoveredGroup, DiscoveredSpeaker, DiscoveryError, Topology};

/// `WireError` → the FRB-facing `DiscoveryError` (1:1; `Backend`/`NotFound` → `Sdk`).
///
/// `NotFound` cannot arise from `discover()` itself (it is a command-level
/// precondition error), but the match must be exhaustive. Map it to `Sdk` so
/// if it ever surfaces unexpectedly it is surfaced as a diagnostic string.
pub fn to_discovery_error(e: WireError) -> DiscoveryError {
    match e {
        WireError::Network(m) => DiscoveryError::Network(m),
        WireError::NoDevicesFound => DiscoveryError::NoDevicesFound,
        WireError::Backend(m) => DiscoveryError::Sdk(m),
        WireError::NotFound(m) => DiscoveryError::Sdk(format!("not found: {m}")),
    }
}

/// Identity `DiscoverySnapshot` → the FRB `Topology` DTO. `IpAddr` and the
/// typed ids are rendered to `String` for the bridge.
pub fn to_topology(snap: DiscoverySnapshot) -> Topology {
    Topology {
        speakers: snap
            .speakers
            .into_iter()
            .map(|s| DiscoveredSpeaker {
                id: s.id.to_string(),
                room_name: s.room_name,
                model: s.model,
                ip: s.ip.to_string(),
            })
            .collect(),
        groups: snap
            .groups
            .into_iter()
            .map(|g| DiscoveredGroup {
                id: g.id.to_string(),
                coordinator: g.coordinator.to_string(),
                members: g.members.iter().map(|m| m.to_string()).collect(),
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_error_maps_one_to_one() {
        assert!(matches!(
            to_discovery_error(WireError::Network("bind".into())),
            DiscoveryError::Network(m) if m == "bind"
        ));
        assert!(matches!(
            to_discovery_error(WireError::NoDevicesFound),
            DiscoveryError::NoDevicesFound
        ));
        // Backend → Sdk is the one non-obvious rename; pin it.
        assert!(matches!(
            to_discovery_error(WireError::Backend("xml".into())),
            DiscoveryError::Sdk(m) if m == "xml"
        ));
        // NotFound → Sdk (cannot arise from discover(), but must be exhaustive)
        assert!(matches!(
            to_discovery_error(WireError::NotFound("RINCON_X".into())),
            DiscoveryError::Sdk(_)
        ));
    }
}
