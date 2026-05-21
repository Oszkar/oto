# Sonos protocol & SDK notes

Durable reference for how oto talks to Sonos: UPnP/SOAP behaviors, the `sonos-api` crate at the pinned `=0.5.2`, and the load-bearing facts learned from hardware spikes on a 4-speaker LAN. Preserved here so we don't re-discover them.

Audience: anyone touching `oto-wire`. If you're touching the GENA event path for v0.4, the [Event model](#event-model-v04-load-bearing) section is the one to read first.

> **Scope.** This is technical reference. Project status, milestones, and forward plan live in [ROADMAP.md](ROADMAP.md). System structure lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Dependency pin

- `sonos-api = "=0.5.2"` (exact). Don't bump without re-checking the SOAP surface here and the multi-NIC SSDP issue [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76).
- `quick-xml = "=0.31.0"` (workspace). Used for DIDL-Lite parsing in `oto-wire/src/control.rs::parse_track_didl`. Already in the locked graph via `sonos-api` — unify, don't bump.
- The `sonos-sdk` umbrella and its `test-support` / `reqwest` / `tokio` tree are **not** in oto-wire's dependency graph (dropped at v0.3). `sonos-api` is the only Sonos crate `oto-wire` depends on.

If v0.4 wants GENA callbacks, the natural next dep is `callback-server` (same family as `sonos-api`) — see [Event model](#event-model-v04-load-bearing).

## SSDP discovery

oto-wire runs its own multi-interface SSDP (`crates/wire/src/ssdp.rs`) and does **not** use `sonos-sdk-discovery`'s built-in SSDP. The reason is one bug:

```rust
// sonos-sdk-discovery-0.5.2/src/ssdp.rs:27
let socket = UdpSocket::bind("0.0.0.0:0")
```

The SSDP socket binds to `0.0.0.0` and the M-SEARCH multicast is sent without setting `IP_MULTICAST_IF` (`set_multicast_if_v4`) and without enumerating interfaces. On a multi-NIC host the OS picks the egress interface from the routing table; on a Windows dev box with a WSL Hyper-V vEthernet, that vEthernet wins and the query never reaches the actual LAN. Single-NIC hosts work by accident. Tracked upstream as [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76); oto's own SSDP enumerates IPv4 interfaces, binds per-NIC, and calls `set_multicast_if_v4`. The library is otherwise sound — only discovery interface binding is broken.

Mechanics:

- **IPv4 SSDP group:** `239.255.255.250:1900`. M-SEARCH target: `urn:schemas-upnp-org:device:ZonePlayer:1`.
- **IPv6 SSDP group:** `[FF02::C]:1900`. Sonos S2 also advertises here. oto-wire does **not** join — see [ROADMAP § IPv6 SSDP coverage](ROADMAP.md#ipv6-ssdp-coverage).
- **Responder `LOCATION`** header → `http://<ip>:1400/xml/device_description.xml`.
- **Identity proof.** As of v0.3, success of `GetZoneGroupState` SOAP on any responder *is* the "this is a Sonos" proof. oto-wire no longer fetches `device_description.xml` in the identity path.
- **HTTP fetch quirk (if you ever fetch `device_description.xml` again — e.g. for the v0.5 `model` repopulate).** Sonos's embedded server replies `HTTP/1.1` with `Transfer-Encoding: chunked` (no `Content-Length`, many tiny chunks) **even to an HTTP/1.0 request**. A raw `TcpStream` GET hands chunk-framed bytes to whatever XML parser receives them and breaks. Use `ureq` (already a locked transitive dep via `sonos-api`); it handles chunked + UTF-8 and bounds `timeout_connect` + `timeout`.

Multi-responder behavior: `ServiceScope::PerNetwork` — any reachable Sonos returns the whole household, so on `GetZoneGroupState` failure (e.g. an asleep first responder) fall through to another. Validated: of 4 LAN speakers, the vanished `.115` returned `NetworkError(connection timed out)`; `.103/.105/.187` each returned the complete topology, 10/10.

## Topology — `GetZoneGroupState` SOAP

The deterministic, complete, fast topology path. **Never use `SonosSystem::from_discovered_devices`** — it runs `ensure_topology()`, which was hardware-proven lazy / non-deterministic (returned 1 of 4 speakers, flapped 0↔1). The whole `SonosSystem` flow was dropped at v0.3.

Call shape:

```rust
use sonos_api::services::zone_group_topology::{get_zone_group_state, parse_zone_group_state_xml};

let op = get_zone_group_state().build();
let resp = client.execute_enhanced(&ip, op)?;  // -> GetZoneGroupStateResponse { zone_group_state: String }
let infos: Vec<ZoneGroupInfo> = parse_zone_group_state_xml(&resp.zone_group_state)?;
```

- **Parser:** use the crate's `parse_zone_group_state_xml`. Do **not** write our own ZoneGroupState parser; `quick-xml` stays DIDL-only.
- **Timing:** ~7–40 ms per call on a healthy LAN (vs. `SonosSystem::new()`'s 3–5 s).
- **Determinism:** 50/50 calls across two topologies returned the complete household, count-stable.
- **Per-network parity:** every live speaker reports the same household. Pick any reachable one.
- **XML is NOT byte-identical across speakers** — `ZoneGroup`/member order is query-relative (the queried speaker's group tends to come first), and a few volatile attrs differ (`MicEnabled`, `ChannelFreq`). The *logical* topology is identical. Compare on the parsed model, never raw XML.

### Bonded satellites — `Invisible="1"`

A bonded HT/stereo set surfaces as **one** `ZoneGroupMember` (the primary) with nested `<Satellite>` children carrying `Invisible="1"`. `parse_zone_group_state_xml` folds them into `ZoneGroupMemberInfo.satellites`. A bonded primary that's also grouped keeps its satellites (e.g. Beam+sat joined Kitchen → 2 members, Beam member `satellites=1`).

**Surface only the primary.** Satellites share the primary's `RoomName`, are not standalone players, and are not separately commandable. This is also what fixed the v0.1 bug of bonded surrounds appearing as standalone players — because v0.1 used raw SSDP device descriptions; v0.3+ uses topology, which folds them by construction.

The `HTSatChanMapSet` attribute encodes channel role (e.g. `…BE01400:RR`) for surround layout. Not surfaced; revisit only if a UI shows surround layout.

### Vanished devices

`<VanishedDevices>` lists units that the household saw recently but are now offline (asleep, unplugged). `parse_zone_group_state_xml` **drops them silently**. That's fine — we don't want them in the snapshot. The raw XML still contains them if ever needed (`ZoneGroupTopologyState::vanished_devices()` is the escape hatch); not used today.

### Coordinator-not-first

The parser does **not** guarantee `members[0] == coordinator`. Observed: a query against `.105` returned member order `[Kitchen, LivingRoom(=coordinator)]`. `oto-core::Group::members` invariant **D3** requires coordinator-first; `oto-wire::adapter::to_snapshot` re-orders. Don't trust wire order.

### Coordinator-absent-from-members

In all hardware runs the coordinator UUID appeared in the member list. Defensive: `to_snapshot` skips a group whose coordinator is not among its members (anomalous → drop the group, don't surface its members as orphans).

### Identifiers

- `SpeakerId` = bare `RINCON_…` (no `uuid:` prefix, unlike the device-description UDN path).
- `GroupId` = `RINCON_<coord_uuid>:N`, e.g. `RINCON_542A1B9463A801400:3426502563`. `N` is opaque; the household assigns it.
- App-side regrouping **changes `N`**. Stale `GroupId` → `WireError::NotFound` (the existing precondition error). This is the freshness contract: caches are populated by `discover()` only; commands using a stale ID error out cleanly.

### No `model` attribute on live members

`ZoneGroupMemberInfo` and `<Satellite>` carry `uuid`, `zone_name` (the Sonos room label), `location` (→ IP), but **no `Model`/`ModelInfo` attribute**. Only `<VanishedDevices>` entries carry `ModelInfo`. `SpeakerIdentity.model: Option<String>` therefore stays `None` since v0.3. The v0.5 hardening milestone repopulates this via a bounded per-member `device_description.xml` fetch over the authoritative topology member set (so the v0.6 UI has model strings to render); see [`docs/ROADMAP.md`](ROADMAP.md).

## Playback control — AVTransport / RenderingControl SOAP

All operations go through `SonosClient::execute_enhanced(ip, op)` directly. **No `SonosSystem`, no `Speaker.play()` handles** — the `SonosSystem` path runs `ensure_topology()` first and is non-deterministic.

```rust
use sonos_api::SonosClient;
use sonos_api::services::av_transport::{play, pause, next, previous, get_transport_info, get_position_info};
use sonos_api::services::rendering_control::{get_volume, set_volume, get_mute, set_mute};

let client = SonosClient::new();
let resp = client.execute_enhanced(&ip, op)?;
```

Conventions:
- **`InstanceID = 0`** is hardcoded inside each operation's macro payload. Not a parameter.
- **Channel for RenderingControl ops:** `"Master"`.
- All operations are **sync/blocking** (`ureq` under the hood). No tokio reactor needed.

Operation table (hardware-verified — Run 1 stopped/empty queue, Run 2 playing Spotify):

| Operation | Builder | Response type | Observed (Run 1 / Run 2) |
|---|---|---|---|
| `play` | `play(speed: String)` | `()` | `Err(NetworkError(…500))` / `Ok(())` |
| `pause` | `pause()` | `()` | `Err(NetworkError(…500))` / `Ok(())` |
| `next` | `next()` | `()` | `Err(NetworkError(…500))` / `Ok(())` |
| `previous` | `previous()` | `()` | `Err(NetworkError(…500))` / `Err(NetworkError(…500))` |
| `get_transport_info` | `get_transport_info()` | `GetTransportInfoResponse { current_transport_state, current_transport_status, current_speed }` | `"STOPPED","OK","1"` / `"PLAYING","OK","1"` |
| `get_position_info` | `get_position_info()` | `GetPositionInfoResponse { track, track_duration, track_meta_data, track_uri, rel_time, abs_time, rel_count, abs_count }` | all-zero/empty / DIDL — see below |
| `get_volume` | `get_volume(channel: String)` | `GetVolumeResponse { current_volume: u8 }` | `33` / `21` |
| `set_volume` | `set_volume(channel, desired_volume: u8)` | `()` | `Ok(())` |
| `get_mute` | `get_mute(channel: String)` | `GetMuteResponse { current_mute: bool }` | `false` |
| `set_mute` | `set_mute(channel, desired_mute: bool)` | `()` | `Ok(())` |

Write commands return `()` on success and carry no data. A device-side rejection (`Pause` when STOPPED, `Previous` when no previous track, transport-not-available) returns **HTTP 500** with a UPnP fault body — see error mapping.

## Transport-state strings

`get_transport_info().current_transport_state` is a string. Map:

| Wire string | `oto_core::PlaybackState` |
|---|---|
| `"STOPPED"` | `Stopped` |
| `"PLAYING"` | `Playing` |
| `"PAUSED_PLAYBACK"` | `Paused` |
| `"TRANSITIONING"` | `Transitioning` |
| anything else | `WireError::Backend` |

Only `"STOPPED"` and `"PLAYING"` were observed in the two-run spike. The other two are UPnP-spec and assumed-correct; if ever observed differently, capture and revisit.

## Error mapping — `ApiError` → `WireError`

**Critical quirk.** `ApiError::SoapFault(u16)` is **not emitted** by `sonos-api` for device-side UPnP faults. A device that rejects a command (HTTP 500 + UPnP fault body, e.g. fault 701 "transition not available") surfaces as:

```text
NetworkError("http://10.83.0.103:1400/MediaRenderer/AVTransport/Control: status code 500")
```

This means we cannot cleanly distinguish "device reached, rejected command" from "device unreachable" — both arrive as `NetworkError`. The discriminator is a substring check on the message:

| `ApiError` | Condition | `WireError` |
|---|---|---|
| `NetworkError(msg)` | msg contains `"status code"` | `Backend(msg)` — device reached but rejected |
| `NetworkError(msg)` | no `"status code"` | `Network(msg)` — connect/timeout failure |
| `SoapFault(code)` | defined but not observed | `Backend(format!("SOAP fault {code}"))` |
| `ParseError(msg)` | — | `Backend(msg)` |
| `InvalidParameter(msg)` | — | `Backend(msg)` |
| `DeviceError(msg)` | — | `Backend(msg)` |
| `SubscriptionError(msg)` | — | `Network(msg)` |

**Fragile.** Depends on `sonos-api`'s error message format remaining stable. The call site carries a `TODO(v0.X): replace the "status code" string-sniff with structured error if sonos-api gains one`. Don't paper over it silently.

## DIDL-Lite track metadata

`GetPositionInfoResponse.track_meta_data` is a **raw XML string** — DIDL-Lite — or an empty string when stopped/queue-empty. `sonos-api` does **not** decode it.

Representative sample (Run 2, Spotify):

```xml
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
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
  </item>
</DIDL-Lite>
```

Three namespace prefixes (`dc:`, `upnp:`, `r:`), `xmlns` declarations on the root element, `&amp;` entity escaping in text content. A regex approach will fail on minor format variation; **use `quick-xml`** (already in the dep graph).

Parser: `oto-wire::control::parse_track_didl(xml: &str) -> Option<oto_core::Track>`. Mapping:

| DIDL field | XPath / note | `oto_core::Track` |
|---|---|---|
| `<dc:title>` text | namespace `dc:` | `title: Option<String>` |
| `<dc:creator>` text | namespace `dc:` | `artist: Option<String>` |
| `<upnp:album>` text | namespace `upnp:` | `album: Option<String>` |
| `<upnp:albumArtURI>` text | namespace `upnp:` | `art_uri: Option<String>` |
| `<res>` text content | entity-unescape `&amp;`→`&` | `uri: Option<String>` |
| `<res duration="H:MM:SS">` attribute | parsed to `Duration` | `duration: Option<Duration>` |
| `<item id="…">` attribute | treat `-1` as absent | `id: Option<TrackId>` |
| (not present in DIDL) | — | `track_number: None` |

Missing fields → `None`. Empty/blank `track_meta_data` → don't attempt parse, `current_track: None`.

### `GetPositionInfoResponse` sentinels

Top-level response fields carry sentinels that must map to `None`, not values:

- `abs_time: "NOT_IMPLEMENTED"` → discard.
- `rel_count: 2147483647` / `abs_count: 2147483647` → these are `i32::MAX`; discard.
- `track_duration: "H:MM:SS"` and `rel_time: "H:MM:SS"` — parse **directly from these top-level fields**, not from DIDL. They populate `TransportState.position`.

## Volume / mute

- Volume is `u8`, range `0..=100`.
- `set_volume(>100)` is rejected **client-side** by `sonos-api` (`ApiError::InvalidParameter` / `ValidationError::RangeError`) — before the SOAP call.
- `oto_core::Volume::new` is strict (`>100` → `Error::InvalidVolume`). `Volume::clamped(i32)` is lenient — use only when parsing inbound SOAP that might be out of range.
- No clamping needed at the wire boundary for outbound volume.

## Event model (v0.4 load-bearing)

This section is what v0.4 needs. The lower layers (`soap-client`, `sonos-api`, `callback-server`) are solid — v0.2/v0.3 confirm `sonos-api` SOAP is reliable for direct control and reads. The reactive layer above them carries the live correctness concerns.

### Opt-in via `.watch()`

Sonos uses UPnP GENA NOTIFY for property change events. **Nothing fires without an explicit `.watch()` registration.** A 12 s observation window with no `.watch()` registered → 0 events. This makes event-stream granularity a design choice, not a forced shape: prefer **one multiplexed event stream → one pump thread**, not one thread per speaker.

### Watch-after-fetch initial-event suppression

**Key constraint.** Upstream change-detection suppresses the initial `.watch()` notification if a prior `.fetch()` already cached the same value. Documented upstream as by-design; unlikely to change.

Implication: the natural pattern "fetch initial state, then subscribe" will **silently miss the first event**. Do not rely on a post-`fetch()` `.watch()` firing an initial event.

**Treat `.watch()` itself as the reachability/seed probe.** If you need an initial value, get it from the first `.watch()` emission (or, accept that the cache populates only when the property next changes). Cold-start handling is the main open design item for v0.4.

### Upstream reactive layer is the weak spot

`sonos-state` / `sonos-stream` / `sonos-event-manager` carry the only known live correctness concern: **intermittent `position` updates** (open upstream). The reactive layer has **no hardware CI** in the upstream repo — every behavior here is hardware-gated and unverified by upstream's automated tests.

The lower layers under it (`soap-client`, `sonos-api`, `callback-server`) are fine. v0.2/v0.3 confirm `sonos-api` SOAP is reliable on real hardware.

### Fallback if reactive proves unreliable

**Not a fork.** If event delivery via the upstream reactive layer is unreliable on real hardware, narrow the dependency: `oto-wire` uses `sonos-api` `fetch` + `callback-server` (GENA raw NOTIFYs) and `oto-app` does change-detection itself. `oto-app` is already the sole runtime-state owner, so this is a localized swap, not an architectural shift.

Decision made by a **pre-v0.4 hardware spike** against the 4-speaker LAN — v0.4 implements only the chosen path, doesn't carry both adapters. The non-chosen path is a v0.5 reconsideration point: when topology events land they exercise the reactive layer differently (less hardware coverage upstream, lower event frequency), so re-pick then if v0.5 evidence diverges from the v0.4 spike result.

### SDK `.get()` is `Option`

`sonos-sdk-state` property accessors (`volume.get()`, `mute.get()`, `playback_state.get()`) are `Option<T>` over an initially empty cache. **Immediately after discovery, they all return `None`** — verified in the 4-speaker spike. The cache populates only via `.fetch()` (one-shot SOAP) or `.watch()` (subscribe). Anything that expects `.get()` to be populated post-discovery is wrong.

For v0.2/v0.3 oto bypasses this layer entirely (`SonosClient::execute_enhanced` direct SOAP). For v0.4 this is the layer we either use or replace per the fallback above.

## Concurrency

`sonos-api` is sync-first; no async runtime is required.

- **Commands:** non-sync FRB fns (Dart `Future`) into blocking `sonos-api` SOAP. `oto-app` holds a `Mutex<Option<HeldWire>>` **locked across the SOAP call**. Deliberate: commands are user-initiated and low-frequency; serializing them is the LAN-politeness story (no command storms against the user's speakers).
- **Events (v0.4):** a `ChangeIterator`-equivalent `recv()` blocks. Each event stream exposed to Dart is pumped by a dedicated OS thread that reads the iterator and pushes onto an FRB `Stream`. Revisit lock granularity only if v0.4 event threads contend with command threads on the slot lock.

No `tokio` in oto's own code. `sonos-api` uses async internally via `reqwest`; that is encapsulated and does not surface at the `Wire` boundary.

## ZoneGroupState fixture XML

The verbatim ZoneGroupState samples captured from the 2026-05-19 hardware spike live in `native/crates/wire/src/adapter.rs` as `const GROUPED_XML`, `const COORD_NOT_FIRST_XML` (the `.105`-view, parser-doesn't-coordinator-first test), `const BAD_IP_XML`, `const GHOST_COORD_XML` (synthetic edge cases). They are the regression-test fixture authoritative source for `to_snapshot`. If the topology changes substantially or `sonos-api` gains a structured XML model, regenerate by re-running the hardware spike against the 4-speaker LAN.

Hardware context for the captures:

| UUID | IP | Role |
|---|---|---|
| `RINCON_542A1B9463A801400` | .103 | Beam, "Living Room" — HT primary / coordinator |
| `RINCON_38420B9275BE01400` | .187 | Surround RR — `Invisible="1"` satellite of the Beam |
| `RINCON_38420B92755401400` | (.115) | Surround LR — vanished (powered off, in `<VanishedDevices>`) |
| `RINCON_7828CAE858CA01400` | .105 | Sonos One, "Kitchen" — standalone |

Two captured topologies:

- **Ungrouped (`.103` view):** 2 groups (Living Room with bonded RR satellite; Kitchen standalone), `<VanishedDevices>` contains LR.
- **Grouped (`.103` view):** 1 group containing both Living Room (with satellite) and Kitchen, coordinator = Living Room; vanished LR still present.
- **Coordinator-not-first (`.105` view of the grouped topology):** member order is `[Kitchen, Living Room(coordinator)]` — exercises the D3 reorder.
