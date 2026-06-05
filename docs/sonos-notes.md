# Sonos protocol & SDK notes

Durable reference for how oto talks to Sonos: UPnP/SOAP behaviors, the `sonos-api` crate at the pinned `=0.5.2`, and the load-bearing facts learned from hardware spikes on a 4-speaker LAN. Preserved here so we don't re-discover them.

Audience: anyone touching `oto-wire`. If you're touching the GENA event path for v0.4, the [Event model](#event-model-v04-load-bearing) section is the one to read first.

> **Scope.** This is technical reference. Project status, milestones, and forward plan live in [ROADMAP.md](ROADMAP.md). System structure lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Dependency pin

- `sonos-api = "=0.5.2"` (exact). Don't bump without re-checking the SOAP surface here and the multi-NIC SSDP issue [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76).
- `quick-xml = "=0.31.0"` (workspace). Used for DIDL-Lite parsing in `oto-wire/src/control.rs::parse_track_didl`. Already in the locked graph via `sonos-api` — unify, don't bump.
- The `sonos-sdk` umbrella and its `test-support` tree are **not** in oto-wire's dependency graph (dropped at v0.3). v0.4 live events add the upstream reactive state/event crates from the same SDK family; `sonos-api` remains the only Sonos crate used for direct SOAP commands and discovery.
- Raw `callback-server` + own change-detection was prototyped for v0.4 and remains the v0.5 reconsideration path, not the chosen v0.4 implementation path — see [Event model](#event-model-v04-load-bearing).

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
- **HTTP fetch quirk (`device_description.xml`).** Sonos's embedded server replies `HTTP/1.1` with `Transfer-Encoding: chunked` (no `Content-Length`, many tiny chunks) **even to an HTTP/1.0 request**. A raw `TcpStream` GET hands chunk-framed bytes to whatever XML parser receives them and breaks. Use `ureq` (already a locked transitive dep via `sonos-api`); it handles chunked + UTF-8 and bounds `timeout_connect` + `timeout`. **Now used** by `oto-wire/src/device_description.rs` (v0.5 `model` repopulate): parallel per-speaker fetch of `<modelName>` inside `discover()` + `refresh_topology()`, best-effort (a failed fetch leaves `model = None`, discovery still succeeds).
- **Per-NIC bind ≠ per-NIC egress.** Binding a socket to a NIC's unicast address does **not** select which interface a *multicast* datagram leaves by — the OS picks that from its multicast routing table (usually one default NIC). You must set `IP_MULTICAST_IF` (`socket2::set_multicast_if_v4`) per socket; oto-wire does this as of the v0.5 egress fix (the `set_multicast_if_v4` claim in this section's intro was aspirational until then). Verify with `examples/ssdp_multicast_if_probe`: it sends the M-SEARCH per NIC twice — with and without the pin — and counts responders each way. On the 4-speaker dev LAN both columns match (the LAN NIC is the OS default multicast interface, so #76 stays dormant — the "works by accident" case); a host where Sonos sits behind a non-default NIC is where the pinned column wins.

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
- Direct SOAP operations are **sync/blocking** (`ureq` under the hood). No tokio reactor is needed for this one-shot command/read path.

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

This section is what v0.4 needs. Authoritative findings live here; the experiment they came from is archived under [`docs/evidence/v0.4-spike/findings.md`](evidence/v0.4-spike/findings.md) (findings + raw logs).

**Decision:** v0.4 builds on the upstream `sonos-sdk-state` reactive layer (`StateManager` + `SonosEventManager`). The raw `sonos-sdk-callback-server` + own change-detection alternative ("Path B") stays a v0.5 reconsideration point.

### Opt-in via `.watch()` — one multiplexed pump thread

Sonos uses UPnP GENA NOTIFY for property change events. **Nothing fires without an explicit `.watch()` registration.** This makes event-stream granularity a design choice, not a forced shape: prefer **one multiplexed event stream → one pump thread**, not one thread per speaker.

### Cold-start: the initial SUBSCRIBE NOTIFY *is* the seed probe

Empirically resolved by the v0.4 spike on real hardware: when an SDK `.watch()` registration triggers an underlying UPnP `SUBSCRIBE`, the device's **first NOTIFY contains current state for every evented variable** — Volume, Mute, Bass, Treble, TransportState, CurrentTrack, etc. The cache transitions `None → populated` automatically within tens of ms of SUBSCRIBE completion.

No separate `.fetch()` step is needed for cold-start. The v0.3-era concern about *"watch-after-fetch suppression silently dropping the first event"* applies only to the pattern `.fetch()` then `.watch()` (which we do not use); a bare `.watch()` is its own seed probe.

### `sonos-stream` polls on top of GENA

Real architectural fact, not documented in the upstream READMEs. The `sonos-stream` broker maintains GENA subscriptions **and** runs a polling scheduler that re-queries AVTransport + RenderingControl on each speaker. Observed `BrokerConfig` defaults:

```text
callback_port_range:    (3400, 3500)
polling_activation_delay: 5 s   (poll starts 5s after broker init)
base_polling_interval:    5 s   (per-service poll cadence)
max_polling_interval:    30 s   (back-off ceiling)
subscription_timeout: 1800 s   (UPnP SUBSCRIBE TIMEOUT)
renewal_threshold:    300 s    (renew 5 min before expiry)
```

Implication: Path A surfaces ~2 s `position` cadence on a playing speaker — that's polling, not real GENA. Raw GENA AVTransport NOTIFYs on a playing speaker arrive **~every 3 minutes in bursts of 2–3 messages within ~250 ms** (4-speaker LAN, 27 min idle session, music playing on the Beam). If real-time position matters in a future implementation that doesn't use `sonos-stream`, polling has to come from somewhere.

LAN-politeness cost of polling: ~0.5 events/sec/playing-speaker. Trivial in absolute terms but real network traffic. Recorded.

### One NOTIFY = many property events (when decomposed)

UPnP `LastChange` semantics: each service bundles all changed properties into one NOTIFY's `<LastChange>` element. Observed bundles:

- **RenderingControl** NOTIFY: Volume (Master / LF / RF), Mute (Master / LF / RF), Bass, Treble, Loudness, OutputFixed, SpeakerSize, SubGain, SubCrossover.
- **AVTransport** NOTIFY: TransportState, CurrentTrack, CurrentTrackURI, CurrentTrackDuration, CurrentTrackMetaData (DIDL-Lite), CurrentPlayMode, NumberOfTracks, CurrentSection, …

If a Path-B-style implementation is ever written, decompose one NOTIFY into N typed property events before emitting to the rest of the stack.

### Doubly-escaped `LastChange` XML

GENA payloads come over HTTP as:

```text
POST /notify
NT: upnp:event
NTS: upnp:propchange
SID: uuid:RINCON_<uuid>_sub<NNN>
SEQ: <n>

<e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
  <e:property>
    <LastChange>&lt;Event …&gt;&lt;InstanceID val="0"&gt;…&lt;/Event&gt;</LastChange>
  </e:property>
</e:propertyset>
```

The `LastChange` *text* is the URI-encoded inner `<Event>` XML. Inside that Event, `<CurrentTrackMetaData>` is URI-encoded **again** (DIDL-Lite inside Event inside propertyset → three levels of nesting, two of them URI-encoded). A correct parser unescapes twice, then DIDL-parses the inner `<r:streamInfo>` / `<dc:title>` / etc. per the existing `oto-wire::control::parse_track_didl`. Don't roll your own with regex.

### Group volume propagation

When a Sonos client (the official app or oto) issues a group-volume change, the device fires **per-member `Volume` events** on each group member within ~6 ms of each other (observed: two pairs of LR/KT volume NOTIFYs at 6 ms and 6 ms intervals). v0.4's UI / StateManager has to either (a) collapse simultaneous volume events from group-mates inside a small time window, or (b) render group volume from a `GroupVolume` property (separate evented variable) rather than from per-speaker `Volume`. Implementation choice for v0.4; documented as a behavioral fact here.

### Subscription renewal

Path A (`sonos-event-manager` + `sonos-stream`) handles GENA renewal automatically per the `renewal_threshold` setting above — observed firing 4 renewals (one per speaker × service) at ~25 min into a 27 min run. Re-verified in v0.4 release acceptance: renewals at 24.6 min in idle dogfood and 24.75 min in active dogfood (music continued playing through the active-session renewal — no event-stream interruption). No intervention required.

If a future Path-B-style implementation is built, renewal is the implementer's responsibility — UPnP `SUBSCRIBE` returns a `TIMEOUT` (default 1800 s in our spike) and a follow-up `SUBSCRIBE` with the same `SID` header before expiry. Without renewal, all subscriptions silently expire after the timeout.

### Per-speaker seed NOTIFY behavior is non-uniform

Not every subscribed RenderingControl/AVTransport service emits an initial NOTIFY on every fresh `SUBSCRIBE`. Empirically (v0.4 release acceptance, 2026-05-26, against an Era 100 + Beam LAN): the Era 100 reliably did NOT send its initial RC NOTIFY on three back-to-back test runs in the same process. The Beam, on the same LAN at the same time, did. Once the operator drove a real Volume change, Era's RC subscription started emitting normally.

The most likely cause is an SDK-internal subscription-cooldown / dedupe on the speaker side when subscribe-unsubscribe-subscribe cycles happen quickly (tests dropping `SonosWire` then immediately creating another). The behavior is not reproducible from the SDK or wire-side code; it's a real speaker-firmware quirk that varies by model.

**Implications for v0.4 (and any v0.5 design):**

- **Don't assume "every subscribed service emits seed within X seconds"** in tests or production. The cache-`None` state during cold-start can persist past the SUBSCRIBE round-trip for some speakers.
- **`speaker_state` returning honest-partial (`None` for properties not yet seen) is load-bearing**, not a transitional state — for some speakers, a property's first observable event might come only when something actually changes.
- The `live_events::subscribe_then_seed_notifies_arrive` test asserts ≥ 1 seed across all discovered speakers within 5 s (was ≥ 2 of 4) for exactly this reason; multi-speaker coverage is verified by the active operator tests.

### Short connectivity outages recover organically

Surprised us during the v0.4 § 8.10 acceptance: disabling the host's Ethernet adapter for ~20–30 s and re-enabling it caused existing GENA subscriptions to RESUME delivering events without needing a fresh `discover()`. The recovery is the combined effect of:

- Sonos's UPnP retry on the NOTIFY delivery path — the speaker keeps trying for a while when the callback TCP fails
- `sonos-stream`'s polling layer kicking back in after the NIC comes back, which catches any state that drifted during the outage

This is much better behavior than the spec § 8.10 framing assumed ("recover or fail-loud"). Two caveats:

- **Short outages only.** The UPnP `SUBSCRIBE TIMEOUT` is 1800 s; if the outage exceeds that (~30 min), the subscription is genuinely dead and the speaker stops retrying.
- **Silent stale state is still possible** — if a Volume change happens during the disconnect and the retry queue drops it, the cache holds the prior value. This is the v0.5 in-band SubscriptionError surfacing target.

Useful real-world data for the v0.5 reactive-vs-NOTIFY revisit: for typical home WiFi disruptions (router reboot, NIC sleep), the SDK + polling combo self-heals without oto needing to do anything.

### Ergonomic footgun: bare `StateManager::new()`

`sonos_state::StateManager::new()` constructs a manager **without an event manager attached**. `register_watch(speaker, key)` on such a manager registers the watch *intent* but **never sends a UPnP SUBSCRIBE** — no error, no warning, just 0 events forever. The v0.4 spike rev 1 hit this and produced 25 min of empty stdout before the cause was identified.

**Use one of these two patterns instead:**

```rust
// Recommended — combines watch intent + subscription in one call.
let em = Arc::new(SonosEventManager::new()?);
let manager = StateManager::builder().with_event_manager(em.clone()).build()?;
manager.add_devices(devices)?;
manager.initialize(topology);  // ← NON-OPTIONAL; see warning below.
let cached_volume: Option<Volume> =
    manager.watch_property_with_subscription::<Volume>(&speaker_id)?;

// Equivalent long form.
manager.register_watch(&speaker_id, Volume::KEY);
em.ensure_service_subscribed(speaker_ip, Volume::SERVICE)?;
```

**`manager.initialize(topology)` is non-negotiable** even for solo speakers. The SDK's `resolve_subscription_target` for AVTransport routes subscriptions to the **coordinator** of each speaker's group; without an initialized topology, the routing falls back silently and AVTransport SUBSCRIBE is never sent. RenderingControl (Volume / Mute) works because it's per-speaker and doesn't need coordinator routing — which makes the failure mode particularly nasty: half the events work, the other half silently never arrive. The first hardware test failure ([PR #45 follow-up](https://github.com/Oszkar/oto/pulls?q=is%3Apr+initialize-topology+merged%3A%3E2026-05-23)) was exactly this: operator play/pause produced zero `ChangeEvent::Playback` because the implementer skipped this line. Construct the `Topology` from the discover snapshot's `speakers` + `groups`; see `oto-wire::events::build_sdk_topology` for the canonical reconstruction.

### SDK gotcha: `StateManager::Clone` fans out independent senders

Non-obvious SDK detail with no upstream README. `StateManager` implements `Clone`, and cloning produces a manager whose event channel uses an **independent** `mpsc::Sender` — not a shared `Arc<Sender>`. Two consequences:

1. **Dropping a clone does not close the channel.** The channel only closes when *every* outstanding clone is dropped. This makes "sender-close as shutdown signal" impossible for any pump thread that holds its own clone of the manager.
2. **Pump-thread shutdown must be out-of-band.** v0.4's pump in `oto-wire::events` uses `Arc<AtomicBool>` + `recv_timeout(POLL_INTERVAL)` so a parent-side `Drop` can flip the flag and the pump exits at the next poll boundary. An earlier design held a "keepalive" manager clone and expected dropping it to close the pump's channel — that broke the second `discover_with` in a row (the pump thread was self-deadlocked, waiting on its own sender clone to close).

Verified in the SDK source around `state.rs:855` at the time of v0.4 implementation. If the SDK pin moves off `=0.5.2`, re-verify this invariant — `Clone` semantics aren't part of the SDK's public contract.

### SDK `.get()` and `get_property` are cache reads, not fetches

`manager.get_property::<P>(&speaker_id) -> Option<P>` reads the in-memory cache only. Returns `None` until a NOTIFY populates the property. There is **no public `.fetch()` method** for one-shot SOAP-driven cache priming on `sonos-sdk-state` — the only ways to populate the cache are `.watch()` (subscribe and wait for the first NOTIFY) or a direct `sonos-api` SOAP call (`oto-wire`'s existing v0.3 path for one-shot reads).

### Status of the v0.3-era "weak spot" concern

The v0.3-era sonos-notes flagged `sonos-state` / `sonos-stream` / `sonos-event-manager` as the only known live correctness concern, citing **intermittent `position` updates** and the absence of hardware CI upstream.

The v0.4 spike (35 min combined idle + active on a 4-speaker LAN) did **not reproduce** the intermittent-position behavior — position events arrived at consistent ~2 s cadence throughout. Downgrade the concern from "load-bearing risk" to "watch for it; not observed in v0.4 spike." Caveat: single session, single LAN, single playing speaker — not a "solved" claim.

The lower layers under the reactive stack (`soap-client`, `sonos-api`, `callback-server`) remain solid; v0.2/v0.3 confirm `sonos-api` SOAP is reliable on real hardware, and the v0.4 spike confirms `callback-server` HTTP NOTIFY reception works correctly.

### Reconsideration point — v0.5

Path B (raw `sonos-sdk-callback-server` + own SUBSCRIBE + own XML parsing + own change-detection) was prototyped in the v0.4 spike, ran correctly with zero warnings, and remains a viable alternative. Switch trigger: if v0.5 topology events (which exercise the reactive layer differently — less upstream hardware coverage, lower event frequency) surface reliability issues.

Migration cost A → B is bounded (the seam — `Wire` trait, `ChangeEvent`, FRB stream surface, `oto-app::StateManager` — is designed for this swap). The spike-callback-server.rs commits in git history are a working starting point.

### Forward-reference: an alternative Path-B Rust crate

**Out of scope for oto** (a side project bounded at v1.0). Recorded here so the work isn't lost: anyone who wants to build a Path-B Rust library (raw GENA + own change-detection, transparent debugging, smaller dep tree) can start from the v0.4 spike binary at the merged spike-findings commit. Add renewal logic, write the doubly-escaped `LastChange` XML parser, add a public API. The case for such a crate gets stronger if upstream `sonos-sdk-*` stops being maintained or if the documented weak spots actually bite users in production.

### Topology change events — how regrouping surfaces (v0.5)

Hardware-confirmed 2026-05-30 (`cargo run -p oto-wire --example topology_probe --features live-tests`, 2-speaker LAN, form-then-break in the Sonos app).

**There is no `ZoneGroupTopology` *property* to watch.** `ZoneGroupTopology` is a `Service`, not a `SonosProperty` — the original v0.5 plan's `watch_property_with_subscription::<ZoneGroupTopology>` does not compile. Topology changes surface through the watchable property **`GroupMembership`**:

- `GroupMembership`: `KEY = "group_membership"`, `SERVICE = Service::ZoneGroupTopology`, `SCOPE = Scope::Speaker` (`sonos-sdk-state-0.5.2/src/property.rs:419-462`).
- ZGT NOTIFYs are handled on a **special path** in `event_worker.rs:49-61`: `decode_topology()` returns an empty `Vec<PropertyChange>` (`decoder.rs:277`); instead `apply_topology_changes()` rebuilds the store and, at its final step, emits `ChangeEvent::new(speaker_id, "group_membership", Service::ZoneGroupTopology)` for **each speaker whose membership changed AND is in the `watched` set** (`event_worker.rs:228-243`).
- So the change arrives on `manager.iter()` as an ordinary `ChangeEvent { property_key: "group_membership", .. }`.

**Implications for topology events:**
- Register `manager.watch_property_with_subscription::<GroupMembership>(&sid)` **per speaker** (it is `Scope::Speaker` — NOT per-coordinator like AVTransport).
- Map `"group_membership" => ChangeEvent::TopologyChanged` in `map_upstream_event`.

**Observed on the 2-speaker LAN:** **both** speakers fire (not one household-wide event), and a single regroup yields multiple `group_membership` events — so the Dart-side 250 ms trailing debounce + `refresh_topology()` re-pull is load-bearing, not optional. NOTIFY→event latency was sub-second once regrouping. Payload is opaque/notification-only at this layer (we re-pull authoritative topology via `GetZoneGroupState` SOAP regardless), exactly what Option 3 assumes.

**Seed NOTIFY on subscribe (load-bearing).** The subscription emits one `group_membership` event **per speaker at startup, before any user action** — the same "the initial SUBSCRIBE NOTIFY *is* the seed" behaviour the property events have (see § Cold-start). In the hardware run, 2 of the observed events were these startup seeds (they arrived *after* the probe's 3 s drain window, so seed latency for `GroupMembership` can exceed 3 s — consistent with § "Per-speaker seed NOTIFY behavior is non-uniform"); the rest were the actual regroup.

  **Outcome (shipped).** `subscribe_topology` runs inside `discover_with` right after `discover()`, so each speaker's subscription emits its seed `group_membership` almost immediately. Rather than let those seeds drive a redundant post-discovery `refresh_topology()`, the **pump suppresses the first `group_membership` per speaker** (`TopologyFilter` in `oto-wire/src/events.rs`). This is not merely an optimisation: a `TopologyChanged` triggers a full re-discover → new pump → fresh seeds, so an *un*-suppressed seed would loop forever. The seed therefore never reaches Dart and no redundant refresh is scheduled.

  **Known limitation (seed vs. real regroup).** Because the *first* `group_membership` per speaker is always treated as the seed, a real regroup that lands before a given speaker's seed is swallowed *for that speaker* — and seed latency for `GroupMembership` can exceed 3 s (above). In practice a regroup fires on multiple speakers, so an already-seeded speaker still forwards the change and a regroup is rarely missed wholesale; the stale-`GroupId` → `NotFound` fallback (below) covers the residual. An authoritative post-subscribe topology re-confirm (compare the first membership event against the discovered topology) is a candidate refinement for v0.6.

**Fallback if this ever goes quiet:** the v0.4 stale-`GroupId` → `WireError::NotFound` contract still holds; the UI re-discovers on `NotFound`. Degraded UX, not broken.

### Reactive-vs-NOTIFY traces — v0.5 validation

Production data collected 2026-06-01 via `cargo run -p oto_native --example event-tail --features oto-wire/live-tests` on the 2-speaker LAN. Two sessions:

| Session | Duration | Renewals | Errors | Spurious events |
|---|---|---|---|---|
| Idle | ~50 min | 4/4 clean (~1475 s, ~82% of 1800 s TTL) | 0 | 0 |
| Active | ~28 min | 4/4 clean (~1481 s, same timing) | 0 | 0 |

**Decision: Path A (sonos-sdk-state) confirmed stable. No switch to Path B.**

Active session exercised: play/pause on both speakers independently, 25 volume slider events (rapid-fire), 10+ track skips, Playback state transitions including `Transitioning`. Every action produced the expected event within ~1 s, correct speaker/group IDs, no cross-speaker bleed, no drops.

**Findings:**

- **Double Track events.** Every track change emits 2 (sometimes more on rapid skipping) consecutive `(group_id, Track, same_title)` events within 0–2 s. The device fires an intermediate-metadata NOTIFY then the resolved-metadata NOTIFY; the SDK delivers both. The UI layer or `map_upstream_event` should apply last-wins dedup with a ~200 ms window on consecutive identical `(group_id, Track)` pairs. Expect the same pattern on `group_membership` (see the topology change events section above).
- **`Transitioning` Playback state.** Appears briefly on track skip and play-start. Map it to a `Loading` variant or suppress; should not reach the UI as "unknown."
- **Renewal timing.** Both sessions renewed at ~82% of 1800 s TTL (~1475–1481 s). Consistent and predictable.

**Path B reconsideration (updated).** The trigger was "topology events surface new reliability evidence." These traces show no reliability issues on the existing property event stream; the trigger condition is not met. Path B remains an off-ramp if v0.5 topology events surface new problems.

## Concurrency

`sonos-api` command calls are sync-first at oto's boundary; the v0.4 event stack may carry an upstream-managed async runtime internally.

- **Commands:** non-sync FRB fns (Dart `Future`) into blocking `sonos-api` SOAP. `oto-app` holds a `Mutex<Option<HeldWire>>` **locked across the SOAP call**. Deliberate: commands are user-initiated and low-frequency; serializing them is the LAN-politeness story (no command storms against the user's speakers).
- **Events (v0.4):** a `ChangeIterator`-equivalent `recv()` blocks. Each event stream exposed to Dart is pumped by a dedicated OS thread that reads the iterator and pushes onto an FRB `Stream`. Revisit lock granularity only if v0.4 event threads contend with command threads on the slot lock.

No async/await in oto's own surface code. `sonos-api` uses async internally via `reqwest`; v0.4 also pulls a tokio runtime transitively via `sonos-event-manager` (Path A's worker thread). Tokio in the lockfile is the cost of any event-stream architecture for Sonos — both Path A and Path B require it. The principle is "no async syntax in oto's own surface code" (commands stay sync; the event-pump thread blocks on `manager.iter()`), not "no tokio in the lockfile."

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

## Group operations (v0.5.1 spike) — hardware-confirmed 2026-06-04

Confirmed on the 2-zone LAN (Beam "Living Room" `.103` = `RINCON_542A1B9463A801400`; Sonos One "Kitchen" `.105` = `RINCON_7828CAE858CA01400`; the Beam's bonded surrounds fold in → only **2 controllable zones**, so a 3+-member group can't be formed here). Probe: `cargo run -p oto-wire --example group_ops_probe --features live-tests`.

### Form a group — `SetAVTransportURI` x-rincon

To make speaker X join coordinator C's group: `av_transport::set_av_transport_uri(format!("x-rincon:{C_uuid}"), String::new())` (two `String` args: current_uri, current_uri_meta_data) on **X's** IP. Confirmed: Living Room joined Kitchen → one group `RINCON_7828CAE858CA01400:386373682`, coord=Kitchen, members=[Living Room, Kitchen]. **The joiner folds into the coordinator's existing group** — the result carries the **coordinator's** GroupId (here unchanged); the joiner's old standalone group dissolves.

### Break / leave — `BecomeCoordinatorOfStandaloneGroup`

`av_transport::become_coordinator_of_standalone_group()` (no args) on **the leaving speaker's** IP. Returns a **structured** response `{ delegated_group_coordinator_id, new_group_id }` (NOT `()`). Sent to the **coordinator** of a 2-member group (Kitchen) → OK, `delegated_group_coordinator_id=Living Room`, `new_group_id=…:386373683`: the leaver delegates the old group's coordination to a remaining member and forms its own new standalone group. **`leave_group(speaker)` is uniform** — same primitive whether or not the speaker coordinates; firmware delegates coordination; no oto-side branch. The 3+-member re-election path is firmware-handled and untested on this 2-zone LAN.

### ⚠ Topology settle latency (load-bearing for the refresh design)

The probe's **immediate** post-BCOS `GetZoneGroupState` re-poll returned a **transitional** state (old group `…682`, coordinator flipped to Living Room, Kitchen still listed — the split had not propagated). The post-JOIN re-poll happened to catch the settled state; the post-leave one did not. **Lesson: do not trust an immediate post-mutation topology re-pull.** Drive the view refresh off the settled `GroupMembership` event (debounced 250 ms), which fires after the household settles. Consequence for v0.5.1: a Dart-side *self-triggered* refresh right after a form/break command would race the settle — so form/break relies on the existing topology-event path instead (the mutation fires `GroupMembership` NOTIFYs exactly like a Sonos-app regroup). Integration/live tests must assert the **settled** topology by **polling `refresh_topology` until the expected state** (with a generous cap), never an immediate re-poll and never a single *fixed* delay — settle latency is variable: a 3 s fixed wait flaked once on real hardware (`leave` not yet propagated) and passed on retry, which is why `live_grouping.rs` polls.

### Group volume / mute — `GroupRenderingControl`

`group_rendering_control::{get_group_volume, set_group_volume(u16), set_relative_group_volume(i16), get_group_mute, set_group_mute(bool)}` on the **coordinator** IP. Confirmed: GetGroupVolume=18; Set 30/50 OK; SetRelative +5→55 / −5→50 (returns the new volume); GetGroupMute=false; SetGroupMute true/false OK. **`set_group_volume(101)` is rejected at `.build()`** with `RangeError { parameter: "desired_volume", min:0, max:100 }` — client-side, like per-speaker `set_volume`. The FRB shim must clamp BEFORE the call (signed i32 → `Volume::clamped`), same pattern as `set_volume`.

### Group volume / mute events

`sonos_state::{GroupVolume, GroupMute}` (need `use sonos_state::property::Property` in scope for `::KEY`), watched per **coordinator** via `watch_property_with_subscription`, fire correctly. A single group-volume drag produced **23 `group_volume` events** (rapid-fire — **last-wins dedup needed**, ~200 ms window, same as Track / per-speaker Volume). Events arrive stamped with the **coordinator's** `speaker_id` → route via `av_transport_group_id` (coordinator → GroupId). `group_mute` *events* were not exercised this run (operator changed volume only); the `set_group_mute` command works and the watch is registered identically — confirm the mute event in the Task 3 live test.

**⚠ Read group-scoped values via `get_group_property`, not `get_property`.** `GroupVolume`/`GroupMute` are `Scope::Group` and the SDK stores them in `group_props` keyed by `GroupId`, NOT in the coordinator's `speaker_props` (`sonos-sdk-state-0.5.2/src/state.rs:182-187`). `manager.get_property::<GroupVolume>(&speaker_id)` reads `speaker_props` → returns `None` → the pump silently drops every group event. Use `manager.get_group_property::<GroupVolume>(&GroupId::new(group.as_str()))`. **Unit tests cannot catch this** — `MockWire` auto-emits the `ChangeEvent` directly, bypassing the SDK property lookup; and the spike read `ChangeEvent.property_key` straight off `manager.iter()`, never via `get_property`. Caught only by codex review of PR #73; the corrected `live_grouping.rs` is the sole real-hardware proof. (Per-speaker `volume`/`mute` and coordinator-routed `playback_state`/`current_track` are fine — those live in `speaker_props`.)

**No-change → no NOTIFY (event tests must change the value).** `set_group_volume(X)` (and per-speaker `set_volume`) on a device already at `X` produces NO `group_volume`/`volume` NOTIFY — Sonos suppresses unchanged values. A hardware event test that sets a fixed target therefore flakes across re-runs (the group may already be at that value from a prior run): observed on the 2-zone LAN, where `set_group_volume(35)` passed on a fresh group but emitted nothing once the group was already at 35. Prime with one value then set a different one to guarantee a change — see `live_grouping.rs::assert_group_volume_event`.

### Fast topology refresh — in-place `manager.initialize()` option (investigated, not chosen)

Calling `manager.initialize(new_topology)` a **second time on the running manager** after a regroup returned OK (no panic) and group_volume events kept flowing, routing to the new topology's coordinators. **But this exercised only GroupRenderingControl events — NOT AVTransport (Playback/Track) re-routing, and not the hardest case (a speaker becoming a NEW coordinator needing a fresh AVTransport SUBSCRIBE).** AVTransport is the load-bearing routing (`resolve_subscription_target` fixed at `initialize`). **Decision: fast topology refresh = SSDP-skipped pump respawn** — drop the `EventPump` + `EventPump::spawn` a fresh one from refreshed caches (no SSDP), reusing the already-hardened spawn/drop machinery; it definitively rebuilds ALL subscriptions (incl. AVTransport for new coordinators) with a clean `TopologyFilter`. In-place re-initialize is a viable future optimization (doesn't crash) but is unverified for AVTransport new-coordinator routing, so it is not the v0.5.1 default.

**Shipped (v0.5.1) — fast RE-DISCOVER, not a same-wire respawn.** The respawn idea was refined once more during implementation: `refresh_topology()` installs a wholly **fresh wire** (`SonosWire::new_seeded(ips)` — skip SSDP, `GetZoneGroupState` from a cached IP) through the existing `discover_with` lifecycle, rather than respawning the pump on the same wire. Reason: the Dart event stream re-subscribes only on a `discoveryProvider` **transition** (keyed on the wire generation, bumped by `discover_with`); a same-wire respawn bumps the generation but does NOT trigger that transition, so the new event receiver is never taken and events silently stop. A fast re-discover IS a genuine wire replacement (minus SSDP), so it reuses the hardware-proven path verbatim. **Value-equality gotcha (codex PR #74):** when the new `Topology` is value-equal to the old (a no-op `TopologyChanged`), the Dart `AsyncData` is `==` the current state and Riverpod suppresses the transition — the `TopologyController` invalidates `wireGenerationProvider` after a successful refresh to force the re-subscribe regardless.
