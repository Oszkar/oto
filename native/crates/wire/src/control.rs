//! `sonos_api` SOAP calls + pure mapping helpers for playback/read operations.
//!
//! All network I/O lives in this module; `adapter.rs` delegates here after
//! resolving IDs to IP addresses.

use std::net::SocketAddr;
use std::time::Duration;

use oto_core::{PlaybackState, SpeakerState, Track, TrackId, TransportState, Volume, WireError};
use sonos_api::{
    services::{av_transport, rendering_control},
    ApiError, SonosClient,
};

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

/// Map a `sonos_api::ApiError` to a `WireError`.
///
/// `NetworkError` messages are sniffed for `"status code"` to distinguish a
/// device-reached-but-rejected scenario (→ `Backend`) from a pure connectivity
/// failure (→ `Network`).
///
/// # Status-sniff caveat
///
/// The `"status code"` substring is the **only** discriminator between a
/// rejected command and a network failure. This depends on `sonos-api`'s
/// error-message format remaining stable.
/// TODO(v0.4): replace string-sniff with structured error if sonos-api gains one
pub(crate) fn map_sdk_err(e: ApiError) -> WireError {
    match e {
        ApiError::NetworkError(msg) => {
            if msg.contains("status code") {
                // TODO(v0.4): replace string-sniff with structured error if sonos-api gains one
                WireError::Backend(msg)
            } else {
                WireError::Network(msg)
            }
        }
        ApiError::SoapFault(code) => WireError::Backend(format!("SOAP fault {code}")),
        ApiError::ParseError(msg) => WireError::Backend(msg),
        ApiError::InvalidParameter(msg) => WireError::Backend(msg),
        ApiError::DeviceError(msg) => WireError::Backend(msg),
        ApiError::SubscriptionError(msg) => WireError::Network(msg),
    }
}

// ---------------------------------------------------------------------------
// Duration helpers
// ---------------------------------------------------------------------------

/// Parse an `"H:MM:SS"` string into a `Duration`.
///
/// Returns `None` for `"NOT_IMPLEMENTED"`, empty strings, or any format that
/// does not parse.
pub(crate) fn parse_hms(s: &str) -> Option<Duration> {
    let s = s.trim();
    if s.is_empty() || s == "NOT_IMPLEMENTED" {
        return None;
    }
    let mut parts = s.splitn(3, ':');
    let h: u64 = parts.next()?.parse().ok()?;
    let m: u64 = parts.next()?.parse().ok()?;
    let sec_part = parts.next()?;
    // Truncate fractional seconds if present (e.g. "03:17.000")
    let s_str = sec_part.split('.').next()?;
    let s_val: u64 = s_str.parse().ok()?;
    Some(Duration::from_secs(h * 3600 + m * 60 + s_val))
}

/// Fill `Track.duration` from the response's top-level `track_duration`
/// when the DIDL `<res duration>` was absent. `GetPositionInfo` carries
/// both; some sources (radio, line-in) omit the DIDL duration but still
/// report a top-level one. The stopped/no-track `"0:00:00"` sentinel
/// (parsed as a zero `Duration`) is ignored so it can't mask "unknown".
pub(crate) fn merge_track_duration(track: Option<Track>, track_duration: &str) -> Option<Track> {
    track.map(|mut t| {
        if t.duration.is_none() {
            t.duration = parse_hms(track_duration).filter(|d| !d.is_zero());
        }
        t
    })
}

// ---------------------------------------------------------------------------
// DIDL-Lite parser
// ---------------------------------------------------------------------------

/// Parse a raw DIDL-Lite XML string into a [`Track`].
///
/// Returns `None` if `xml` is blank/empty or if the XML cannot be read at all.
/// Individual missing fields map to `None` within the returned `Track`.
///
/// Handles namespace prefixes `dc:`, `upnp:`, `r:`, and `&amp;` entity
/// decoding (quick-xml decodes entities in text content automatically).
pub(crate) fn parse_track_didl(xml: &str) -> Option<Track> {
    if xml.trim().is_empty() {
        return None;
    }

    use quick_xml::events::Event;
    use quick_xml::Reader;

    let mut reader = Reader::from_str(xml);
    reader.trim_text(true);

    let mut title: Option<String> = None;
    let mut artist: Option<String> = None;
    let mut album: Option<String> = None;
    let mut art_uri: Option<String> = None;
    let mut uri: Option<String> = None;
    let mut duration: Option<Duration> = None;
    let mut id: Option<TrackId> = None;

    // Track which element we're currently inside so we can capture text.
    #[derive(Debug, Clone, Copy, PartialEq)]
    enum Inside {
        Title,
        Creator,
        Album,
        AlbumArtUri,
        Res,
        Other,
    }
    let mut inside = Inside::Other;

    loop {
        match reader.read_event() {
            Ok(Event::Start(ref e)) | Ok(Event::Empty(ref e)) => {
                // local_name() strips the namespace prefix
                let local = e.local_name();
                let local_str = std::str::from_utf8(local.as_ref()).unwrap_or("");

                match local_str {
                    "item" => {
                        // Extract item id attribute; treat "-1" as absent
                        for attr in e.attributes().flatten() {
                            if attr.key.local_name().as_ref() == b"id" {
                                let val =
                                    attr.decode_and_unescape_value(&reader).unwrap_or_default();
                                if !val.is_empty() && val != "-1" {
                                    id = Some(TrackId::new(val.as_ref()));
                                }
                            }
                        }
                        inside = Inside::Other;
                    }
                    "res" => {
                        // Extract duration attribute
                        for attr in e.attributes().flatten() {
                            if attr.key.local_name().as_ref() == b"duration" {
                                let val =
                                    attr.decode_and_unescape_value(&reader).unwrap_or_default();
                                duration = parse_hms(&val);
                            }
                        }
                        inside = Inside::Res;
                    }
                    "title" => inside = Inside::Title,
                    "creator" => inside = Inside::Creator,
                    // Exact local-name match: `albumArtURI` is its own arm,
                    // so it never collides with `album`.
                    "album" => inside = Inside::Album,
                    "albumArtURI" => inside = Inside::AlbumArtUri,
                    _ => inside = Inside::Other,
                }
            }
            Ok(Event::Text(ref e)) => {
                let text = e.unescape().unwrap_or_default();
                let text = text.trim();
                if text.is_empty() {
                    continue;
                }
                match inside {
                    Inside::Title => title = Some(text.to_string()),
                    Inside::Creator => artist = Some(text.to_string()),
                    Inside::Album => album = Some(text.to_string()),
                    Inside::AlbumArtUri => art_uri = Some(text.to_string()),
                    Inside::Res => uri = Some(text.to_string()),
                    Inside::Other => {}
                }
            }
            Ok(Event::End(_)) => {
                inside = Inside::Other;
            }
            Ok(Event::Eof) => break,
            Err(_) => return None,
            _ => {}
        }
    }

    Some(Track {
        id,
        title,
        artist,
        album,
        art_uri,
        uri,
        duration,
        track_number: None,
    })
}

// ---------------------------------------------------------------------------
// Transport-state mapping
// ---------------------------------------------------------------------------

/// Map the UPnP `TransportState` string to [`PlaybackState`].
///
/// Observed values: `"STOPPED"`, `"PLAYING"`, `"PAUSED_PLAYBACK"`,
/// `"TRANSITIONING"`. Anything else → `WireError::Backend`.
pub(crate) fn map_transport_state(s: &str) -> Result<PlaybackState, WireError> {
    match s {
        "STOPPED" => Ok(PlaybackState::Stopped),
        "PLAYING" => Ok(PlaybackState::Playing),
        "PAUSED_PLAYBACK" => Ok(PlaybackState::Paused),
        "TRANSITIONING" => Ok(PlaybackState::Transitioning),
        other => Err(WireError::Backend(format!(
            "unexpected transport state: {other:?}"
        ))),
    }
}

// ---------------------------------------------------------------------------
// SOAP command helpers — return () on success, WireError on failure
// ---------------------------------------------------------------------------

pub(crate) fn soap_play(addr: SocketAddr) -> Result<(), WireError> {
    let client = SonosClient::new();
    let op = av_transport::play("1".to_string())
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&addr.ip().to_string(), op)
        .map_err(map_sdk_err)
}

pub(crate) fn soap_pause(addr: SocketAddr) -> Result<(), WireError> {
    let client = SonosClient::new();
    let op = av_transport::pause()
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&addr.ip().to_string(), op)
        .map_err(map_sdk_err)
}

pub(crate) fn soap_next(addr: SocketAddr) -> Result<(), WireError> {
    let client = SonosClient::new();
    let op = av_transport::next()
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&addr.ip().to_string(), op)
        .map_err(map_sdk_err)
}

pub(crate) fn soap_previous(addr: SocketAddr) -> Result<(), WireError> {
    let client = SonosClient::new();
    let op = av_transport::previous()
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&addr.ip().to_string(), op)
        .map_err(map_sdk_err)
}

pub(crate) fn soap_set_volume(addr: SocketAddr, volume: Volume) -> Result<(), WireError> {
    let client = SonosClient::new();
    let op = rendering_control::set_volume("Master".to_string(), volume.get())
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&addr.ip().to_string(), op)
        .map_err(map_sdk_err)
}

pub(crate) fn soap_set_mute(addr: SocketAddr, muted: bool) -> Result<(), WireError> {
    let client = SonosClient::new();
    let op = rendering_control::set_mute("Master".to_string(), muted)
        .build()
        .map_err(|e| WireError::Backend(format!("build error: {e}")))?;
    client
        .execute_enhanced(&addr.ip().to_string(), op)
        .map_err(map_sdk_err)
}

/// Read the full speaker state from `addr`.
///
/// Per-read failure → that `SpeakerState` field is `None`; the others are
/// still populated. Only an unresolvable id → `Err(NotFound)`.
pub(crate) fn soap_speaker_state(addr: SocketAddr) -> Result<SpeakerState, WireError> {
    let ip = addr.ip().to_string();
    let client = SonosClient::new();

    // GetVolume
    let volume: Option<Volume> = {
        let op = rendering_control::get_volume("Master".to_string())
            .build()
            .ok();
        op.and_then(|o| client.execute_enhanced(&ip, o).ok())
            .map(|r| Volume::clamped(r.current_volume as i32))
    };

    // GetMute
    let muted: Option<bool> = {
        let op = rendering_control::get_mute("Master".to_string())
            .build()
            .ok();
        op.and_then(|o| client.execute_enhanced(&ip, o).ok())
            .map(|r| r.current_mute)
    };

    // GetTransportInfo + GetPositionInfo (combined into Option<TransportState>)
    let transport: Option<TransportState> = {
        let ti_op = av_transport::get_transport_info().build().ok();
        let pi_op = av_transport::get_position_info().build().ok();

        let ti = ti_op.and_then(|o| client.execute_enhanced(&ip, o).ok());
        let pi = pi_op.and_then(|o| client.execute_enhanced(&ip, o).ok());

        match ti {
            None => None,
            Some(ti_resp) => {
                let playback = match map_transport_state(&ti_resp.current_transport_state) {
                    Ok(p) => p,
                    Err(_) => {
                        return Ok(SpeakerState {
                            volume,
                            muted,
                            transport: None,
                        })
                    }
                };

                let (current_track, position) = match pi {
                    None => (None, None),
                    Some(pi_resp) => {
                        // Sentinel: rel_count == i32::MAX → position is absent (discard
                        // rel_time); otherwise parse "H:MM:SS" (also handles
                        // "NOT_IMPLEMENTED" via parse_hms).
                        let pos = if pi_resp.rel_count == i32::MAX {
                            None
                        } else {
                            parse_hms(&pi_resp.rel_time)
                        };

                        let track = if pi_resp.track_meta_data.trim().is_empty() {
                            None
                        } else {
                            merge_track_duration(
                                parse_track_didl(&pi_resp.track_meta_data),
                                &pi_resp.track_duration,
                            )
                        };

                        (track, pos)
                    }
                };

                Some(TransportState {
                    state: playback,
                    current_track,
                    position,
                })
            }
        }
    };

    Ok(SpeakerState {
        volume,
        muted,
        transport,
    })
}

// ---------------------------------------------------------------------------
// Unit tests — LAN-free, pure helper coverage
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use oto_core::WireError;

    // -----------------------------------------------------------------------
    // merge_track_duration
    // -----------------------------------------------------------------------

    fn bare_track(duration: Option<Duration>) -> Track {
        Track {
            id: None,
            title: Some("X".into()),
            artist: None,
            album: None,
            track_number: None,
            duration,
            art_uri: None,
            uri: None,
        }
    }

    #[test]
    fn merge_fills_missing_duration_from_top_level() {
        let merged = merge_track_duration(Some(bare_track(None)), "0:03:17").unwrap();
        assert_eq!(merged.duration, Some(Duration::from_secs(197)));
    }

    #[test]
    fn merge_keeps_existing_didl_duration() {
        let merged =
            merge_track_duration(Some(bare_track(Some(Duration::from_secs(300)))), "0:03:17")
                .unwrap();
        assert_eq!(
            merged.duration,
            Some(Duration::from_secs(300)),
            "DIDL <res duration> must win over the top-level fallback"
        );
    }

    #[test]
    fn merge_ignores_zero_sentinel_and_none_track() {
        assert_eq!(
            merge_track_duration(Some(bare_track(None)), "0:00:00")
                .unwrap()
                .duration,
            None,
            "stopped/no-track 0:00:00 must not mask unknown duration"
        );
        assert_eq!(merge_track_duration(None, "0:03:17"), None);
    }

    // -----------------------------------------------------------------------
    // map_sdk_err
    // -----------------------------------------------------------------------

    #[test]
    fn network_error_with_status_code_maps_to_backend() {
        let e = ApiError::NetworkError(
            "http://10.83.0.103:1400/MediaRenderer/AVTransport/Control: status code 500"
                .to_string(),
        );
        assert!(matches!(map_sdk_err(e), WireError::Backend(_)));
    }

    #[test]
    fn network_error_without_status_code_maps_to_network() {
        let e = ApiError::NetworkError("connection refused".to_string());
        assert!(matches!(map_sdk_err(e), WireError::Network(_)));
    }

    #[test]
    fn soap_fault_maps_to_backend() {
        let e = ApiError::SoapFault(701);
        match map_sdk_err(e) {
            WireError::Backend(msg) => assert!(msg.contains("701")),
            other => panic!("expected Backend, got {other:?}"),
        }
    }

    #[test]
    fn parse_error_maps_to_backend() {
        let e = ApiError::ParseError("bad xml".to_string());
        assert!(matches!(map_sdk_err(e), WireError::Backend(_)));
    }

    #[test]
    fn invalid_parameter_maps_to_backend() {
        let e = ApiError::InvalidParameter("out of range".to_string());
        assert!(matches!(map_sdk_err(e), WireError::Backend(_)));
    }

    #[test]
    fn device_error_maps_to_backend() {
        let e = ApiError::DeviceError("not coordinator".to_string());
        assert!(matches!(map_sdk_err(e), WireError::Backend(_)));
    }

    #[test]
    fn subscription_error_maps_to_network() {
        let e = ApiError::SubscriptionError("expired".to_string());
        assert!(matches!(map_sdk_err(e), WireError::Network(_)));
    }

    // -----------------------------------------------------------------------
    // parse_hms
    // -----------------------------------------------------------------------

    #[test]
    fn parse_hms_basic() {
        assert_eq!(parse_hms("0:03:17"), Some(Duration::from_secs(197)));
    }

    #[test]
    fn parse_hms_hours() {
        assert_eq!(parse_hms("1:02:03"), Some(Duration::from_secs(3723)));
    }

    #[test]
    fn parse_hms_not_implemented() {
        assert_eq!(parse_hms("NOT_IMPLEMENTED"), None);
    }

    #[test]
    fn parse_hms_empty() {
        assert_eq!(parse_hms(""), None);
    }

    #[test]
    fn parse_hms_zeros() {
        assert_eq!(parse_hms("0:00:00"), Some(Duration::from_secs(0)));
    }

    // -----------------------------------------------------------------------
    // map_transport_state
    // -----------------------------------------------------------------------

    #[test]
    fn transport_state_stopped() {
        assert_eq!(map_transport_state("STOPPED"), Ok(PlaybackState::Stopped));
    }

    #[test]
    fn transport_state_playing() {
        assert_eq!(map_transport_state("PLAYING"), Ok(PlaybackState::Playing));
    }

    #[test]
    fn transport_state_paused() {
        assert_eq!(
            map_transport_state("PAUSED_PLAYBACK"),
            Ok(PlaybackState::Paused)
        );
    }

    #[test]
    fn transport_state_transitioning() {
        assert_eq!(
            map_transport_state("TRANSITIONING"),
            Ok(PlaybackState::Transitioning)
        );
    }

    #[test]
    fn transport_state_unknown_is_backend_error() {
        let result = map_transport_state("UNKNOWN_STATE");
        assert!(matches!(result, Err(WireError::Backend(_))));
    }

    // -----------------------------------------------------------------------
    // parse_track_didl — EXACT verbatim sample from the findings doc
    // -----------------------------------------------------------------------

    /// The verbatim DIDL-Lite sample from
    /// `docs/plans/2026-05-18-playback-spike-findings.md` § Q2.
    const FINDINGS_DIDL: &str = r#"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
  xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"
  xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
  <item id="-1" parentID="-1">
    <res duration="0:03:17">x-sonos-spotify:spotify:track:5f92OpAQ0TenbweMyWR3Fb?sid=12&amp;flags=0&amp;sn=4</res>
    <upnp:albumArtURI>https://i.scdn.co/image/ab67616d0000b27367e2f02b7a0c3864840ff675</upnp:albumArtURI>
    <upnp:class>object.item.audioItem.musicTrack</upnp:class>
    <dc:title>Rise</dc:title>
    <dc:creator>State of Mine</dc:creator>
    <upnp:album>Devil in Disguise</upnp:album>
    <r:streamInfo>bd:16,sr:44100,c:0,l:0,d:0</r:streamInfo>
  </item></DIDL-Lite>"#;

    #[test]
    fn parse_findings_didl_sample() {
        let track = parse_track_didl(FINDINGS_DIDL).expect("should parse");

        assert_eq!(track.title.as_deref(), Some("Rise"), "title");
        assert_eq!(track.artist.as_deref(), Some("State of Mine"), "artist");
        assert_eq!(track.album.as_deref(), Some("Devil in Disguise"), "album");

        // duration: 0:03:17 = 197 s
        assert_eq!(track.duration, Some(Duration::from_secs(197)), "duration");

        // art_uri starts with https://i.scdn.co
        assert!(
            track
                .art_uri
                .as_deref()
                .unwrap_or("")
                .starts_with("https://i.scdn.co"),
            "art_uri = {:?}",
            track.art_uri
        );

        // id="-1" → None (sentinel)
        assert!(track.id.is_none(), "id should be None for -1");

        // track_number always None from DIDL
        assert!(track.track_number.is_none());

        // uri with &amp; decoded
        let uri = track.uri.as_deref().unwrap_or("");
        assert!(uri.contains("x-sonos-spotify:"), "uri prefix");
        assert!(uri.contains('&'), "& should be decoded from &amp;");
    }

    #[test]
    fn parse_empty_didl_returns_none() {
        assert!(parse_track_didl("").is_none());
        assert!(parse_track_didl("   ").is_none());
    }

    #[test]
    fn parse_didl_with_non_minus1_id() {
        let xml = r#"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
  xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
  <item id="track-99" parentID="-1">
    <dc:title>Test</dc:title>
  </item></DIDL-Lite>"#;
        let track = parse_track_didl(xml).expect("should parse");
        assert_eq!(track.id, Some(TrackId::new("track-99")));
        assert_eq!(track.title.as_deref(), Some("Test"));
    }
}
