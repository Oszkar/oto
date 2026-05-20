# Playback spike — findings

**Date:** 2026-05-18 **Context:** Before implementing `SonosWire`'s playback surface (Task 4) we ran a throwaway spike against `sonos-api` directly on real hardware to answer the five Phase-0 questions in the v0.2 design. Two runs against a single speaker (`10.83.0.103`, RINCON_542A1B9463A801400): one with the queue empty/stopped, one while actively streaming Spotify. This doc records the evidence and the resulting directives.

Spike ref: `docs/findings-playback-spike.txt` (scratch; kept for raw output); source authority is `sonos-api-0.5.2/src/{client,services/av_transport,services/rendering_control,error}.rs`.

## Evidence

Speaker: `10.83.0.103` (Sonos PLAY:1, RINCON_542A1B9463A801400). Direct `sonos-api = "=0.5.2"` dev-dep; umbrella `sonos_sdk` does **not** re-export `SonosClient` or the service builders.

| Run | Speaker state | Key inputs / outputs |
|---|---|---|
| 1 | STOPPED, empty queue | `GetVolume→33`, `GetMute→false`, `TransportState→"STOPPED"`, `GetPositionInfo→all-zero/empty`, `SetVolume/SetMute→()`, `Pause/Play/Next/Previous→NetworkError(…500)` |
| 2 | PLAYING (Spotify) | `GetVolume→21`, `GetMute→false`, `TransportState→"PLAYING"`, `GetPositionInfo→track+DIDL`, `SetVolume/SetMute→()`, `Pause/Play/Next→()`, `Previous→NetworkError(…500)` |

## Findings

### Q1 — Builder API, response types, InstanceID

Client: `sonos_api::SonosClient::new()`; dispatch: `client.execute_enhanced(&ip: &str, op) -> Result<Op::Response, ApiError>` (`sonos-api-0.5.2/src/client.rs:130`).

InstanceID is **hardcoded `0`** in each operation's macro payload — it is not a parameter.

| Operation | Builder expression | Response type | Observed value (Run 1 / Run 2) |
|---|---|---|---|
| `play` | `play(speed: String)` (`:717`) | `()` | `Err(NetworkError(…500))` / `Ok(())` |
| `pause` | `pause()` (`:716`) | `()` | `Err(NetworkError(…500))` / `Ok(())` |
| `next` | `next()` (`:714`) | `()` | `Err(NetworkError(…500))` / `Ok(())` |
| `previous` | `previous()` (`:718`) | `()` | `Err(NetworkError(…500))` / `Err(NetworkError(…500))` |
| `get_transport_info` | `get_transport_info()` (`:728`) | `GetTransportInfoResponse { current_transport_state: String, current_transport_status: String, current_speed: String }` | `"STOPPED","OK","1"` / `"PLAYING","OK","1"` |
| `get_position_info` | `get_position_info()` (`:722`) | `GetPositionInfoResponse { track: u32, track_duration: String, track_meta_data: String, track_uri: String, rel_time: String, abs_time: String, rel_count: i32, abs_count: i32 }` | all-zero/empty / see Q2 |
| `get_volume` | `get_volume(channel: String)` (`:400`) | `GetVolumeResponse { current_volume: u8 }` | `33` / `21` |
| `set_volume` | `set_volume(channel: String, desired_volume: u8)` (`:402`) | `()` | `Ok(())` / `Ok(())` |
| `get_mute` | `get_mute(channel: String)` (`:163`) | `GetMuteResponse { current_mute: bool }` | `false` / `false` |
| `set_mute` | `set_mute(channel: String, desired_mute: bool)` (`:193`) | `()` | `Ok(())` / `Ok(())` |

Channel argument for all RenderingControl ops: `"Master"`.

All six commands succeed with `Ok(())` when the transport allows them; the response carries no data.

### Q2 — DIDL-Lite metadata: raw string, mapping, parser

`sonos_api` does **not** decode `track_meta_data`. The field is a raw XML string — DIDL-Lite — or an empty string when stopped/queue-empty. Representative value from Run 2:

```
track_meta_data: "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\"
  xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\"
  xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\"
  xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">
  <item id=\"-1\" parentID=\"-1\">
    <res duration=\"0:03:17\">x-sonos-spotify:spotify:track:5f92OpAQ0TenbweMyWR3Fb?sid=12&amp;flags=0&amp;sn=4</res>
    <upnp:albumArtURI>https://i.scdn.co/image/ab67616d0000b27367e2f02b7a0c3864840ff675</upnp:albumArtURI>
    <upnp:class>object.item.audioItem.musicTrack</upnp:class>
    <dc:title>Rise</dc:title>
    <dc:creator>State of Mine</dc:creator>
    <upnp:album>Devil in Disguise</upnp:album>
    <r:streamInfo>bd:16,sr:44100,c:0,l:0,d:0</r:streamInfo>
  </item></DIDL-Lite>"
```

`oto-wire` must implement `parse_track_didl(xml: &str) -> Option<Track>` with this mapping to `oto_core::Track`:

| DIDL-Lite field | XPath / note | `oto_core::Track` field |
|---|---|---|
| `<dc:title>` text | namespace `dc:` | `title: Option<String>` |
| `<dc:creator>` text | namespace `dc:` | `artist: Option<String>` |
| `<upnp:album>` text | namespace `upnp:` | `album: Option<String>` |
| `<upnp:albumArtURI>` text | namespace `upnp:` | `art_uri: Option<String>` |
| `<res>` text content | decoded (entity-unescape `&amp;`→`&`) | `uri: Option<String>` |
| `<res duration="H:MM:SS">` attribute | parsed to `Duration` | `duration: Option<Duration>` |
| `<item id="…">` attribute | treat `-1` as absent | `id: Option<TrackId>` |
| (not present in DIDL) | — | `track_number: Option<u32>` → `None` |

All fields map to `None` when absent. Empty/blank `track_meta_data` → `current_track: None` (don't attempt parse).

**Sentinel fields** in `GetPositionInfoResponse` — map to `None`, not values:
- `abs_time: "NOT_IMPLEMENTED"` — discard.
- `rel_count: 2147483647` / `abs_count: 2147483647` — these are `i32::MAX`; discard.

**Separate duration/position without DIDL:** `track_duration` ("H:MM:SS") and `rel_time` ("H:MM:SS") are top-level response fields. Parse them directly for `TransportState.position` — no DIDL needed.

**XML parser:** `quick-xml` is already present in the locked dep graph (transitive via `sonos-sdk`). Task 4 must use `quick-xml` for DIDL parsing — do **not** add a competing XML crate. The DIDL uses three namespace prefixes (`dc:`, `upnp:`, `r:`), `xmlns` declarations on the root element, and `&amp;` entity escaping in text content; a regex approach will fail on even minor format variation. This is a §7 dependency decision to record in the Task-4 PR.

### Q3 — `ApiError` shape and WireError mapping

`ApiError` variants (`sonos-api-0.5.2/src/error.rs`): `NetworkError(String)`, `ParseError(String)`, `SoapFault(u16)`, `InvalidParameter(String)`, `SubscriptionError(String)`, `DeviceError(String)`.

**Observed in both runs:** device-side SOAP faults (UPnP 701 "transition not available" — Pause when STOPPED; Previous when no previous track in stream) surface as:

```
NetworkError("http://10.83.0.103:1400/MediaRenderer/AVTransport/Control: status code 500")
```

`SoapFault(u16)` was **never emitted** in either run. The device returns HTTP 500 with a UPnP fault body, and `sonos-api` maps this to `NetworkError`, not `SoapFault`. This means `map_sdk_err` **cannot cleanly distinguish** a device that rejected a command (reached, HTTP 500) from a device that is unreachable (connection refused / timeout) — both arrive as `NetworkError`.

**Proposed WireError mapping for Task 4:**

| `ApiError` variant | Condition | `WireError` variant |
|---|---|---|
| `NetworkError(msg)` | `msg` contains `"status code"` | `WireError::Backend(msg)` — device reached but rejected |
| `NetworkError(msg)` | no `"status code"` in msg | `WireError::Network(msg)` — connect/timeout failure |
| `SoapFault(code)` | (not observed, but defined) | `WireError::Backend(format!("SOAP fault {code}"))` |
| `ParseError(msg)` | — | `WireError::Backend(msg)` |
| `InvalidParameter(msg)` | — | `WireError::Backend(msg)` |
| `DeviceError(msg)` | — | `WireError::Backend(msg)` |
| `SubscriptionError(msg)` | — | `WireError::Network(msg)` |

**Explicit constraint for Task 4:** the `"status code"` substring is the **only** discriminator between a rejected command and a network failure. This is fragile — it depends on `sonos-api`'s error message format remaining stable. Record a `// TODO(v0.3): replace string-sniff with structured error if sonos-api gains one` at the call site. Do not paper over it silently.

### Q4 — Volume width and clamp behaviour

`GetVolumeResponse.current_volume` is `u8`. Observed: `33` (Run 1), `21` (Run 2). Range is `0..=100`. `set_volume(desired_volume: u8 > 100)` is rejected by `sonos-api` **client-side** before the SOAP call, returning `ApiError::InvalidParameter` / `ValidationError::RangeError`. This matches `oto_core::Volume` (`u8`, `0..=100`, `Volume::new` rejects `>100`). No clamping is needed at the wire boundary for outbound volume; `Volume::clamped` is available for inbound SOAP values if they ever arrive outside range.

### Q5 — Sync / no tokio reactor

All ten calls are blocking and synchronous. No `tokio::runtime::Runtime` is constructed; no `async fn` is called. Confirmed both at runtime (no reactor threads observed) and in `sonos-api-0.5.2/src/client.rs` (uses `reqwest` blocking client, not the async client). `SonosWire`'s playback methods can be called directly from FRB handler threads without a Tokio context.

## Feeds Task 4 / §7

Concrete directives for the SonosWire implementation:

1. **DIDL parser:** use `quick-xml` (already in the dep graph). Implement `parse_track_didl(xml: &str) -> Option<Track>` in `oto-wire`. Do not add an alternative XML crate.

2. **Error mapping:** `map_sdk_err` must sniff `"status code"` in `NetworkError` messages to distinguish `WireError::Backend` (device rejected) from `WireError::Network` (unreachable). Mark the string-sniff as `TODO(v0.3)`.

3. **Sentinel handling:** discard `abs_time:"NOT_IMPLEMENTED"`, `rel_count/abs_count:i32::MAX`; parse `rel_time` and `track_duration` from top-level response fields (not DIDL).

4. **Transport-state strings:** observed `"STOPPED"` and `"PLAYING"`. UPnP-standard `"PAUSED_PLAYBACK"` and `"TRANSITIONING"` were not observed in these two runs but are defined by the UPnP AVTransport spec and `oto_core::PlaybackState` already covers them. Match all four; anything else → `WireError::Backend`.

5. **InstanceID:** hardcoded `0` in all `sonos-api` operation builders — no parameter needed.

6. **Direct `sonos-api` dep required:** add `sonos-api = "=0.5.2"` as a direct dependency in `oto-wire`'s `Cargo.toml` (it is not re-exported by the umbrella `sonos-sdk` crate).
