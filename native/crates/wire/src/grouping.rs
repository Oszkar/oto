//! `sonos_api` SOAP calls for group form/break (v0.5.1).
//!
//! All network I/O lives in this module; `adapter.rs` delegates here after
//! resolving ids to IP addresses. Shapes are hardware-validated — see
//! `examples/group_ops_probe.rs` (Sections 2 + 3). Error mapping reuses
//! `control::map_sdk_err` so a SOAP fault / network failure maps to the same
//! `WireError` variants as the playback commands.

use std::net::SocketAddr;

use oto_core::WireError;
use sonos_api::{services::av_transport, SonosClient};

use crate::control::map_sdk_err;

/// Fold a speaker into a coordinator's group.
///
/// `SetAVTransportURI` with `x-rincon:<coordinator_id>` is sent to the
/// JOINER's IP (`joiner_addr`); `coordinator_id` is the coordinator's bare
/// `RINCON_…` id. The joiner then plays in lock-step with the coordinator's
/// group (hardware-validated, probe Section 2).
pub(crate) fn join(
    client: &SonosClient,
    joiner_addr: SocketAddr,
    coordinator_id: &str,
) -> Result<(), WireError> {
    let uri = format!("x-rincon:{coordinator_id}");
    let op = av_transport::set_av_transport_uri(uri, String::new())
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&joiner_addr.ip().to_string(), op)
        .map(|_| ())
        .map_err(map_sdk_err)
}

/// Detach a speaker into its own standalone group.
///
/// `BecomeCoordinatorOfStandaloneGroup` (no args) is sent to the LEAVER's IP
/// (`leaver_addr`). Uniform regardless of whether the speaker coordinates a
/// group — the firmware re-elects a coordinator for any members left behind
/// (hardware-validated, probe Section 3). The structured response body is
/// ignored; the settled topology surfaces via the topology-event path.
pub(crate) fn leave(client: &SonosClient, leaver_addr: SocketAddr) -> Result<(), WireError> {
    let op = av_transport::become_coordinator_of_standalone_group()
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&leaver_addr.ip().to_string(), op)
        .map(|_| ())
        .map_err(map_sdk_err)
}
