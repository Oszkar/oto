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
//! has exactly one `DiscoveryError` / `CommandError` image. Snapshots map
//! field-for-field; the one deliberate narrowing is `Duration` → whole
//! `u64` seconds (Sonos SOAP time fields carry no sub-second component, so
//! this is lossless in practice).

use oto_core::{DiscoverySnapshot, PlaybackState, SpeakerState, WireError};

use crate::api::{
    CommandError, DiscoveredGroup, DiscoveredSpeaker, DiscoveryError, PlaybackStateDto,
    SpeakerStateDto, Topology, TrackDto, TransportDto,
};

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

/// `WireError` → the FRB-facing `CommandError`.
///
/// `Backend` → `Sonos` is the one non-obvious rename (the SDK-internal error
/// is exposed to Dart as a `Sonos` diagnostic rather than the wire-layer name).
/// `NoDevicesFound` → `NotFound` because no device list means the target
/// speaker/group is unavailable; cannot normally arise from a command (discover
/// must succeed first), but the match must be exhaustive.
pub fn to_command_error(e: WireError) -> CommandError {
    match e {
        WireError::Network(m) => CommandError::Network(m),
        WireError::Backend(m) => CommandError::Sonos(m),
        WireError::NotFound(m) => CommandError::NotFound(m),
        // Cannot normally arise from a command (discover must precede it), but
        // the match is exhaustive. Surface as NotFound so Dart can handle it
        // uniformly with a missing-speaker condition.
        WireError::NoDevicesFound => CommandError::NotFound("no devices discovered".into()),
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

/// `SpeakerState` → the FRB `SpeakerStateDto`. All optional fields pass
/// through as `Option`; typed newtypes are unwrapped to scalars.
pub fn to_speaker_state_dto(state: SpeakerState) -> SpeakerStateDto {
    SpeakerStateDto {
        volume: state.volume.map(|v| u32::from(v.get())),
        muted: state.muted,
        transport: state.transport.map(|t| TransportDto {
            state: to_playback_state_dto(t.state),
            position_secs: t.position.map(|d| d.as_secs()),
            current_track: t.current_track.map(|track| TrackDto {
                id: track.id.map(|i| i.to_string()),
                title: track.title,
                artist: track.artist,
                album: track.album,
                track_number: track.track_number,
                duration_secs: track.duration.map(|d| d.as_secs()),
                art_uri: track.art_uri,
                uri: track.uri,
            }),
        }),
    }
}

/// `PlaybackState` → `PlaybackStateDto` (1:1 enum map).
fn to_playback_state_dto(state: PlaybackState) -> PlaybackStateDto {
    match state {
        PlaybackState::Stopped => PlaybackStateDto::Stopped,
        PlaybackState::Playing => PlaybackStateDto::Playing,
        PlaybackState::Paused => PlaybackStateDto::Paused,
        PlaybackState::Transitioning => PlaybackStateDto::Transitioning,
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use oto_core::{PlaybackState, SpeakerState, Track, TrackId, TransportState, Volume};

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

    // ── CommandError pinning tests ────────────────────────────────────────────

    #[test]
    fn command_error_network_passes_through() {
        assert!(matches!(
            to_command_error(WireError::Network("timeout".into())),
            CommandError::Network(m) if m == "timeout"
        ));
    }

    #[test]
    fn command_error_backend_maps_to_sonos() {
        // Backend → Sonos is the one non-obvious rename; pin it.
        assert!(matches!(
            to_command_error(WireError::Backend("soap fault".into())),
            CommandError::Sonos(m) if m == "soap fault"
        ));
    }

    #[test]
    fn command_error_not_found_passes_through() {
        assert!(matches!(
            to_command_error(WireError::NotFound("RINCON_X".into())),
            CommandError::NotFound(m) if m == "RINCON_X"
        ));
    }

    #[test]
    fn command_error_no_devices_found_maps_to_not_found() {
        // NoDevicesFound cannot normally arise from a command (discover must
        // precede it), but the match is exhaustive. Verify the fallback.
        assert!(matches!(
            to_command_error(WireError::NoDevicesFound),
            CommandError::NotFound(m) if m == "no devices discovered"
        ));
    }

    // ── SpeakerStateDto pinning tests ─────────────────────────────────────────

    #[test]
    fn speaker_state_dto_all_none() {
        let state = SpeakerState {
            volume: None,
            muted: None,
            transport: None,
        };
        let dto = to_speaker_state_dto(state);
        assert!(dto.volume.is_none());
        assert!(dto.muted.is_none());
        assert!(dto.transport.is_none());
    }

    #[test]
    fn speaker_state_dto_full_round_trip() {
        let state = SpeakerState {
            volume: Some(Volume::new(75).unwrap()),
            muted: Some(true),
            transport: Some(TransportState {
                state: PlaybackState::Playing,
                position: Some(Duration::from_secs(120)),
                current_track: Some(Track {
                    id: Some(TrackId::new("t-42")),
                    title: Some("Halcyon".into()),
                    artist: Some("Orbital".into()),
                    album: Some("Snivilisation".into()),
                    track_number: Some(3),
                    duration: Some(Duration::from_secs(593)),
                    art_uri: Some("http://example/art.jpg".into()),
                    uri: Some("x-file-cifs://nas/halcyon.flac".into()),
                }),
            }),
        };
        let dto = to_speaker_state_dto(state);

        assert_eq!(dto.volume, Some(75u32));
        assert_eq!(dto.muted, Some(true));

        let transport = dto.transport.expect("transport must be Some");
        assert!(matches!(transport.state, PlaybackStateDto::Playing));
        assert_eq!(transport.position_secs, Some(120u64));

        let track = transport.current_track.expect("track must be Some");
        assert_eq!(track.id.as_deref(), Some("t-42"));
        assert_eq!(track.title.as_deref(), Some("Halcyon"));
        assert_eq!(track.artist.as_deref(), Some("Orbital"));
        assert_eq!(track.album.as_deref(), Some("Snivilisation"));
        assert_eq!(track.track_number, Some(3u32));
        assert_eq!(track.duration_secs, Some(593u64));
        assert_eq!(track.art_uri.as_deref(), Some("http://example/art.jpg"));
        assert_eq!(track.uri.as_deref(), Some("x-file-cifs://nas/halcyon.flac"));
    }
}
