# Sonos protocol & SDK notes

Durable reference for how oto talks to Sonos: UPnP/SOAP behaviors, the `sonos-api` crate at the pinned `=0.8.0`, and the load-bearing facts learned from hardware spikes. Historical observations below name the SDK version used at the time.

Audience: anyone touching `oto-wire`. If you're touching the GENA event path, the [Event model](#event-model) section is the one to read first.

> **Scope.** This is technical reference. Project status, milestones, and forward plan live in [ROADMAP.md](ROADMAP.md). System structure lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Dependency pin

- `sonos-api = "=0.8.0"` (exact), aligned with the reactive SDK crates. Re-check SOAP, discovery, events, and hardware acceptance when upgrading.
- All Sonos crates now resolve from crates.io. Upstream 0.8 removed the reqwest/native-TLS dependencies that required our fork; [`LOCAL_PATCHES.md`](../LOCAL_PATCHES.md) #2 records its retirement. SDK discovery uses ureq 3.4, shared with oto's model fetches; upstream SOAP still uses ureq 2.x.
- `quick-xml = "=0.31.0"` (workspace). Used for DIDL-Lite parsing in `oto-wire/src/control.rs::parse_track_didl` and model-name extraction in `device_description.rs`. Already in the locked graph via `sonos-api` - unify, don't bump.
- The `sonos-sdk` umbrella and its `test-support` tree are **not** in oto-wire's dependency graph (dropped at v0.3). v0.4 live events add the upstream reactive state/event crates from the same SDK family; `sonos-api` remains the only Sonos crate used for direct SOAP commands and discovery.
- Raw `callback-server` + own change-detection was prototyped but not chosen; oto uses the upstream reactive stack - see [Event model](#event-model).

## SSDP discovery

oto-wire runs its own IPv4 multi-interface SSDP in `native/crates/wire/src/ssdp.rs`. Each socket binds to an interface and explicitly sets `IP_MULTICAST_IF`; `mio::Poll` shares one absolute receive deadline across them. Binding a unicast address alone does not select multicast egress.

Upstream added concurrent per-interface probing after the SDK 0.5.2 bug, but the pinned SDK still lacks explicit multicast egress and an absolute receive deadline. Keep oto's implementation until both safeguards and multi-NIC hardware validation are available upstream.

Mechanics:

- **IPv4 SSDP group:** `239.255.255.250:1900`. M-SEARCH target: `urn:schemas-upnp-org:device:ZonePlayer:1`.
- **IPv6 SSDP group:** `[FF02::C]:1900`. Sonos S2 also advertises here. oto-wire does **not** join - see [ROADMAP § IPv6 SSDP coverage](ROADMAP.md#ipv6-ssdp-coverage).
- **Responder `LOCATION`** header → `http://<ip>:1400/xml/device_description.xml`.
- **Topology validation.** A successful, parseable `GetZoneGroupState` response admits a responder. This is not authentication. Device descriptions are fetched only to enrich the resulting member identities with model names.
- **HTTP fetch quirk (`device_description.xml`).** Sonos's embedded server replies with chunked HTTP even to an HTTP/1.0 request. A raw `TcpStream` hands chunk framing to the XML parser. `oto-wire/src/device_description.rs` uses ureq 3.4 with `timeout_connect` (1 s) and `timeout_global` (2 s), shared with upstream discovery's dependency. Parallel per-speaker model fetches remain best-effort: failure leaves `model = None` and discovery still succeeds.
- **Hardware probe:** `native/crates/wire/examples/ssdp_multicast_if_probe.rs` compares M-SEARCH with and without the egress pin. The original dev LAN used the default multicast interface, so matching results there establish non-regression, not correctness on a non-default NIC.

Any reachable Sonos can return the whole household. If one responder fails its topology read, discovery tries another. Response validation and candidate-count limits remain [planned hardening](ROADMAP.md#v07---hardening--polish).

## Topology - `GetZoneGroupState` SOAP

The deterministic, complete, fast topology path. **Never use `SonosSystem::from_discovered_devices`** - it runs `ensure_topology()`, which was hardware-proven lazy / non-deterministic (returned 1 of 4 speakers, flapped 0↔1). The whole `SonosSystem` flow was dropped at v0.3.

Call shape:

```rust
use sonos_api::services::zone_group_topology::{
    get_zone_group_state, parse_zone_group_state_xml, ZoneGroupInfo,
};

let op = get_zone_group_state().build()?;
let resp = client.execute_enhanced(&ip, op)?;  // -> GetZoneGroupStateResponse { zone_group_state: String }
let infos: Vec<ZoneGroupInfo> = parse_zone_group_state_xml(&resp.zone_group_state)?;
```

- **Parser:** use the crate's `parse_zone_group_state_xml`. Do **not** write our own ZoneGroupState parser; oto uses `quick-xml` directly for DIDL-Lite and device-description model names.
- **Historical timing (SDK 0.5.2):** ~7-40 ms per direct call on the test LAN.
- **Historical completeness (SDK 0.5.2):** 50/50 calls across two topologies returned the complete household, count-stable.
- **Per-network parity:** every live speaker reports the same household. Pick any reachable one.
- **XML is NOT byte-identical across speakers** - `ZoneGroup`/member order is query-relative (the queried speaker's group tends to come first), and a few volatile attrs differ (`MicEnabled`, `ChannelFreq`). The *logical* topology is identical. Compare on the parsed model, never raw XML.

### Bonded satellites - `Invisible="1"`

A bonded HT/stereo set surfaces as **one** `ZoneGroupMember` (the primary) with nested `<Satellite>` children carrying `Invisible="1"`. `parse_zone_group_state_xml` folds them into `ZoneGroupMemberInfo.satellites`. A bonded primary that's also grouped keeps its satellites (e.g. Beam+sat joined Kitchen → 2 members, Beam member `satellites=1`).

**Surface only the primary.** Satellites share the primary's `RoomName`, are not standalone players, and are not separately commandable. This is also what fixed the v0.1 bug of bonded surrounds appearing as standalone players - because v0.1 used raw SSDP device descriptions; v0.3+ uses topology, which folds them by construction.

The `HTSatChanMapSet` attribute encodes channel role (e.g. `...BE01400:RR`) for surround layout. Not surfaced; revisit only if a UI shows surround layout.

### Vanished devices

`<VanishedDevices>` lists units that the household saw recently but are now offline (asleep, unplugged). `parse_zone_group_state_xml` **drops them silently**. That's fine - we don't want them in the snapshot. The raw XML still contains them if ever needed (`ZoneGroupTopologyState::vanished_devices()` is the escape hatch); not used today.

### Coordinator-not-first

The parser does **not** guarantee `members[0] == coordinator`. Observed: a query against `.105` returned member order `[Kitchen, LivingRoom(=coordinator)]`. `oto-core::Group::members` invariant **D3** requires coordinator-first; `oto-wire::adapter::to_snapshot` re-orders. Don't trust wire order.

### Coordinator-absent-from-members

In all hardware runs the coordinator UUID appeared in the member list. Defensive: `to_snapshot` skips a group whose coordinator is not among its members (anomalous → drop the group, don't surface its members as orphans).

### Identifiers

- `SpeakerId` = bare `RINCON_...` (no `uuid:` prefix, unlike the device-description UDN path).
- `GroupId` = `RINCON_<coord_uuid>:N`, e.g. `RINCON_542A1B9463A801400:3426502563`. `N` is opaque; the household assigns it.
- Regrouping can change `N`. Discovery and fast topology refresh replace the routing caches. An old ID then returns `WireError::NotFound`; before refresh it can still route to the former coordinator. Do not treat `NotFound` as immediate detection of a regroup.

### No `model` attribute on live members

Topology members provide UUID, room name, and location, but no model name. `discover()` and `refresh_topology()` enrich each member through a bounded, parallel `device_description.xml` fetch. Failure leaves `SpeakerIdentity.model = None` without failing discovery.

## Playback control - AVTransport / RenderingControl SOAP

All operations go through `SonosClient::execute_enhanced(ip, op)` directly. **No `SonosSystem`, no `Speaker.play()` handles** - the `SonosSystem` path runs `ensure_topology()` first and is non-deterministic.

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
- Direct SOAP operations are **sync/blocking** (`ureq` under the hood). No tokio reactor is needed for this one-shot command/read path.

Operation table (historical SDK 0.5.2 hardware observations: Run 1 stopped/empty queue, Run 2 playing Spotify; these observations are not SDK 0.8 acceptance):

| Operation | Builder | Response type | Observed (Run 1 / Run 2) |
|---|---|---|---|
| `play` | `play(speed: String)` | `()` | `Err(NetworkError(...500))` / `Ok(())` |
| `pause` | `pause()` | `()` | `Err(NetworkError(...500))` / `Ok(())` |
| `next` | `next()` | `()` | `Err(NetworkError(...500))` / `Ok(())` |
| `previous` | `previous()` | `()` | `Err(NetworkError(...500))` / `Err(NetworkError(...500))` |
| `get_transport_info` | `get_transport_info()` | `GetTransportInfoResponse { current_transport_state, current_transport_status, current_speed }` | `"STOPPED","OK","1"` / `"PLAYING","OK","1"` |
| `get_position_info` | `get_position_info()` | `GetPositionInfoResponse { track, track_duration, track_meta_data, track_uri, rel_time, abs_time, rel_count, abs_count }` | all-zero/empty / DIDL - see below |
| `get_volume` | `get_volume(channel: String)` | `GetVolumeResponse { current_volume: u8 }` | `33` / `21` |
| `set_volume` | `set_volume(channel, desired_volume: u8)` | `()` | `Ok(())` |
| `get_mute` | `get_mute(channel: String)` | `GetMuteResponse { current_mute: bool }` | `false` |
| `set_mute` | `set_mute(channel, desired_mute: bool)` | `()` | `Ok(())` |

Write commands return `()` on success and carry no data. A device-side rejection (`Pause` when STOPPED, `Previous` when no previous track, transport-not-available) returns **HTTP 500** with a UPnP fault body - see error mapping.

## Transport-state strings

`get_transport_info().current_transport_state` is a string. Map:

| Wire string | `oto_core::PlaybackState` |
|---|---|
| `"STOPPED"` | `Stopped` |
| `"PLAYING"` | `Playing` |
| `"PAUSED_PLAYBACK"` | `Paused` |
| `"TRANSITIONING"` | `Transitioning` |
| anything else | `WireError::Backend` |

Paused and transitioning states were also observed during subsequent live-event acceptance. Unknown values remain errors in the one-shot SOAP mapping.

## Error mapping - `ApiError` → `WireError`

**Historical hardware finding, still reflected in the adapter:** device-side HTTP 500 faults arrived as `NetworkError` rather than `ApiError::SoapFault(u16)`, for example:

```text
NetworkError("http://10.83.0.103:1400/MediaRenderer/AVTransport/Control: status code 500")
```

This means we cannot cleanly distinguish "device reached, rejected command" from "device unreachable" - both arrive as `NetworkError`. The discriminator is a substring check on the message:

| `ApiError` | Condition | `WireError` |
|---|---|---|
| `NetworkError(msg)` | msg contains `"status code"` | `Backend(msg)` - device reached but rejected |
| `NetworkError(msg)` | no `"status code"` | `Network(msg)` - connect/timeout failure |
| `SoapFault(code)` | defined but not observed | `Backend(format!("SOAP fault {code}"))` |
| `ParseError(msg)` | - | `Backend(msg)` |
| `InvalidParameter(msg)` | - | `Backend(msg)` |
| `DeviceError(msg)` | - | `Backend(msg)` |
| `SubscriptionError(msg)` | - | `Network(msg)` |

**Fragile.** Depends on `sonos-api`'s error message format remaining stable. The
call site carries a `TODO(v0.7): replace the "status code" string-sniff with
structured error if sonos-api gains one`. Don't paper over it silently.

## DIDL-Lite track metadata

`GetPositionInfoResponse.track_meta_data` is a **raw XML string** - DIDL-Lite - or an empty string when stopped/queue-empty. `sonos-api` does **not** decode it.

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
| `<item id="...">` attribute | treat `-1` as absent | `id: Option<TrackId>` |
| (not present in DIDL) | - | `track_number: None` |

Missing fields → `None`. Empty/blank `track_meta_data` → don't attempt parse, `current_track: None`.

### `GetPositionInfoResponse` sentinels

Top-level response fields carry sentinels that must map to `None`, not values:

- `abs_time: "NOT_IMPLEMENTED"` → discard.
- `rel_count: 2147483647` / `abs_count: 2147483647` → these are `i32::MAX`; discard.
- `track_duration: "H:MM:SS"` and `rel_time: "H:MM:SS"` - parse **directly from these top-level fields**, not from DIDL. They populate `TransportState.position`.

> **Gotcha (cost a v0.6.1 QA cycle):** the COUNT fields (`rel_count`/`abs_count`) sitting at `i32::MAX` is the *permanent, normal* Sonos state - those byte counters are never implemented. Discard them only as values; **never** let them gate `rel_time`. The position is `parse_hms(rel_time)` *alone*. Gating it on `rel_count == i32::MAX` discards a valid position on every track (the Now Playing bar always reads 0). See `oto-wire`'s `parse_rel_position`.

## Volume / mute

- Volume is `u8`, range `0..=100`.
- `set_volume(>100)` is rejected **client-side** by `sonos-api` (`ApiError::InvalidParameter` / `ValidationError::RangeError`) - before the SOAP call.
- `oto_core::Volume::new` is strict (`>100` → `Error::InvalidVolume`). `Volume::clamped(i32)` is lenient; the FRB shim uses it for signed Dart volume inputs and SOAP parsing uses it for device values.
- No clamping needed at the wire boundary for outbound volume.

## Event model

oto uses the aligned SDK reactive stack (`StateManager`, `SonosEventManager`, and the stream/callback layers). It owns GENA subscriptions, renewal, and internal polling. oto maps typed event payloads into domain events; it does not add a second general property-polling loop. Track progress has a separate bounded SOAP read path described in [Architecture](ARCHITECTURE.md#state-ownership).

### Initialization and event delivery

The ordering in `native/crates/wire/src/events.rs` is required:

1. Attach a `SonosEventManager` through `StateManager::builder()`.
2. Add discovered devices and call `manager.initialize(topology)`.
3. Create `manager.iter()` before registering watches. SDK 0.8 has no event replay; attaching later can lose initial NOTIFYs.
4. Register `watch_property_with_subscription` for the supported properties.

A bare `StateManager::new()` plus watch intent does not establish subscriptions. Missing topology initialization breaks AVTransport coordinator routing even when per-speaker volume events work. Use `build_sdk_topology` and the production spawn path as the implementation reference.

Volume/mute and `GroupMembership` are watched per speaker. Playback, track, and group volume/mute are watched for coordinators. Mapping reads `ChangeEvent.change` directly, preserving the value observed when each event was queued rather than reading a cache that may already have advanced.

### Cold-start and seed notifications

An initial SUBSCRIBE NOTIFY usually seeds current values, so do not fetch before watching: an already-cached value can suppress the first change notification. Startup values remain optional until observed.

Historical hardware runs found delayed or missing seed notifications on repeated subscriptions. The cause was not established; do not promise a seed deadline for every service or infer speaker failure from a missing seed alone. Live tests check that seeding works across the household, then use actual value changes for per-speaker coverage.

### SDK polling and renewal

The SDK supplements GENA with polling. Historical SDK 0.5.2 traces saw periodic position updates and renewals near 25 minutes for an 1800-second subscription. These timings are observations, not oto latency guarantees. oto does not expose the SDK position stream; Now Playing anchors its clock from `GetPositionInfo`.

The callback listener uses the SDK's configured TCP port range (3400-3500 in the pinned default configuration). The speakers must be able to connect back to it.

### Shutdown

SDK 0.8 manager clones share an event fanout. A held manager keeps it alive, so channel closure cannot stop a pump that itself holds a manager.

`EventPump::Drop` first calls `SonosEventManager::shutdown()` to release the SDK worker's self-owned reference cycle, then sets oto's stop flag and joins its pump after the next `recv_timeout` boundary. SDK cleanup can complete asynchronously. Both the stop/join and explicit SDK shutdown are necessary; the strong-reference regression test covers eventual release.

### Topology change events

`ZoneGroupTopology` is a service; the watchable property is speaker-scoped `GroupMembership`. Several speakers can emit for one regroup, so Dart debounces for 250 ms and re-pulls authoritative topology.

The initial subscription also emits membership seeds. `TopologyFilter` suppresses the first membership event per speaker only within a five-second startup window. A later first event is treated as a real regroup. This bounds the risk of swallowing a change when a seed never arrives.

After a regroup, the old pump's coordinator maps are stale. It temporarily drops group-addressed events until a fresh wire is installed. If both fast refresh and full discovery fail, its dirty flag expires after 60 seconds, checked on the next event. That bounds silence while accepting possibly stale routing. See [Architecture](ARCHITECTURE.md#live-events) for the wire-generation lifecycle.

### Repeated events and connectivity

Track changes can emit intermediate and resolved metadata; apply later values rather than assuming one event per track. `Transitioning` is a real playback state. Group-volume writes can also emit per-member volume changes; the group master uses the separate `GroupVolume` event, not an inferred average of room volumes.

Historical acceptance observed subscriptions recovering after a 20-30 second host-network outage. That does not establish recovery after longer outages or guarantee that every missed value is replayed. Health events currently report command-time network failure/recovery; idle silence can remain undetected.

### Raw GENA alternative

A raw callback-server spike also worked, but would require oto to own subscription renewal, XML parsing, and change detection. Retain the SDK path unless maintenance or reliability problems justify that cost. [The spike record](evidence/v0.4-spike/findings.md) preserves the comparison and raw logs.

If revisited, one NOTIFY can contain many property changes. `LastChange` contains XML-escaped inner XML, and `CurrentTrackMetaData` can contain another escaped DIDL-Lite document. Decode the XML layers with a parser, not URI decoding or regular expressions. Renew each subscription before its returned `TIMEOUT` using the same `SID`.

## ZoneGroupState fixture XML

The verbatim ZoneGroupState samples captured from the 2026-05-19 hardware spike live in `native/crates/wire/src/adapter.rs` as `const GROUPED_XML`, `const COORD_NOT_FIRST_XML` (the `.105`-view, parser-doesn't-coordinator-first test), `const BAD_IP_XML`, `const GHOST_COORD_XML` (synthetic edge cases). They are the regression-test fixture authoritative source for `to_snapshot`. If the topology changes substantially or `sonos-api` gains a structured XML model, regenerate by re-running the hardware spike against the 4-speaker LAN.

Hardware context for the captures:

| UUID | IP | Role |
|---|---|---|
| `RINCON_542A1B9463A801400` | .103 | Beam, "Living Room" - HT primary / coordinator |
| `RINCON_38420B9275BE01400` | .187 | Surround RR - `Invisible="1"` satellite of the Beam |
| `RINCON_38420B92755401400` | (.115) | Surround LR - vanished (powered off, in `<VanishedDevices>`) |
| `RINCON_7828CAE858CA01400` | .105 | Sonos One, "Kitchen" - standalone |

Two captured topologies:

- **Ungrouped (`.103` view):** 2 groups (Living Room with bonded RR satellite; Kitchen standalone), `<VanishedDevices>` contains LR.
- **Grouped (`.103` view):** 1 group containing both Living Room (with satellite) and Kitchen, coordinator = Living Room; vanished LR still present.
- **Coordinator-not-first (`.105` view of the grouped topology):** member order is `[Kitchen, Living Room(coordinator)]` - exercises the D3 reorder.

## Group operations

The original SDK 0.5.2 probe used two controllable zones (Beam and Sonos One); bonded surrounds were folded into the primary. It did not validate three-member coordinator re-election. Current integration code lives in `native/crates/wire/src/control.rs`; hardware tests are in `native/crates/wire/tests/live_grouping.rs` and `live_seeded_fast_rediscover.rs`.

### Join and leave

- Join: send `SetAVTransportURI` with `x-rincon:<coordinator UUID>` and empty metadata to the joining speaker. It joins the coordinator's existing group.
- Leave: send `BecomeCoordinatorOfStandaloneGroup` to the leaving speaker, including when that speaker is the coordinator. Firmware delegates the old group's coordination; oto needs no special coordinator branch.

An immediate post-mutation `GetZoneGroupState` can return a transitional topology. The UI refreshes from debounced membership events instead of immediately after the command. Hardware tests poll for the expected settled topology within a bounded deadline; fixed sleeps have flaked.

### Group volume and mute

`GroupRenderingControl` reads and writes target the coordinator. Volume builders reject values outside 0-100; the FRB shim clamps signed input through `Volume::clamped` before dispatch. Group volume/mute events carry the coordinator's speaker ID, which oto maps to its group ID.

SDK 0.8 carries values in typed payloads. The old SDK 0.5.2 trap of reading group events from the speaker-property cache no longer applies; do not restore cache lookups in event mapping.

Unchanged writes need not emit NOTIFY. An event test must prime one value and write a different one, then wait for the matching event. A fixed target can silently match the value left by an earlier run.

### Fast topology refresh

Refresh builds a fresh seeded wire from cached IPs, without SSDP, and installs it through `discover_with`. This rebuilds every subscription, including AVTransport when a speaker becomes coordinator. In-place SDK topology reinitialization was only probed for group-volume events, so it is not evidence that new-coordinator subscriptions work.

Dart re-subscribes using the successful wire-install generation signal. This must not depend on topology value equality: a wire replacement needs a fresh receiver even when the visible household is unchanged. Failed replacement preserves the old wire and its one-shot receiver.
