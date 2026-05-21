# Roadmap

Milestone status and forward plan. Sibling docs: [ARCHITECTURE.md](ARCHITECTURE.md) for system structure, [sonos-notes.md](sonos-notes.md) for protocol/SDK reference, [CHANGELOG.md](../CHANGELOG.md) for per-release detail.

## Current status

| Version | Status | What |
|---|---|---|
| v0.1.0 | released | Foundation + LAN identity-only discovery |
| v0.2.0 | released | Playback control + one-shot state read (group-of-one) |
| v0.3.0 | released | Real ZoneGroupTopology grouping — multi-room, coordinator election, bonded satellites folded |
| v0.4   | next | Live **property** events (GENA) — Rust → Dart event stream for volume / mute / transport / track |
| v0.5   | future | **Hardening before UI** — topology events, group form/break, Android `MulticastLock`, model repopulate |
| v0.6   | future | The designed Flutter UI |
| v1.0   | future | Stable — externally tested, packaged |

v0.1, v0.2, and v0.3 are verified on Windows. Android **release** discovery is non-functional pending a held `WifiManager.MulticastLock` — see [v0.5](#v05--hardening-before-ui).

## v0.4 — Live property events

Reactive state via GENA: Rust → Dart event stream, no polling. **Property events only** — volume, mute, transport state, current track. Topology change events and group form/break are v0.5 (see below); pulling them in inflates one milestone with two cache shapes, two cold-start stories, and the less-exercised side of the upstream reactive layer.

### Adds

- `StateManager` in `oto-app` caching per-speaker properties, emitting `ChangeEvent`s on change.
- One multiplexed event-pump thread (not per-speaker, per the [event-model design note](sonos-notes.md#opt-in-via-watch)).
- Riverpod providers shift from `FutureProvider` (one-shot reads) to `StreamProvider` (subscribed projections); they hold projections for rendering, not source data. State mutations stay in Rust, avoiding cross-FFI consistency bugs.
- `Wire::speaker_state` impl swaps fetch → event-cache read. The `Wire` signature is unchanged across the swap (designed in v0.2 for this).
- Resolves the v0.2 ADR's deeper "revisit at v0.3 → revisit at v0.4" item: transport may move off `SpeakerState` onto a group-addressed read when state is event-fed.
- `native/examples/event-tail.rs` — small dogfooding binary that subscribes to the event stream and prints changes. Produces the kind of production-data evidence that drives the v0.5 reactive-vs-NOTIFY review; not a user-facing CLI.

### Out of scope (deferred to v0.5)

- **Topology change events.** Live `ZoneGroupTopology` subscription. `discover()` remains the only topology source through v0.4; a stale `GroupId` still returns `WireError::NotFound`.
- **Group form/break** commands. Same surface as topology events (`GroupManagement` / `ZoneGroupTopology`); land together in v0.5.

### Pre-milestone spike

The "upstream reactive layer vs. raw `callback-server` + own change-detection" decision is made **before** v0.4 implementation begins, by a small hardware spike against the 4-speaker LAN. v0.4 implements only the chosen path — don't carry both adapters.

This collapses the previous "decide with real-hardware data once events are wired end-to-end" framing: that ambiguity is too expensive inside the milestone. The non-chosen path stays a v0.5 reconsideration point — if topology events expose new reliability evidence in v0.5, the question reopens then.

### Known constraints

Detail in [sonos-notes.md § Event model](sonos-notes.md#event-model-v04-load-bearing). Headlines:

- **Watch-after-fetch initial-event suppression** — upstream change-detection suppresses the initial `.watch()` notification if a prior `.fetch()` cached the same value. Documented upstream as by-design. Implication: treat `.watch()` itself as the seed probe; cold-start handling is the main thing to settle this milestone.
- **Upstream reactive layer is the weak spot.** `sonos-state` / `sonos-stream` / `sonos-event-manager` carry the only known live correctness concern (intermittent `position` updates, open upstream) and have no hardware CI coverage. The lower layers (`soap-client`, `sonos-api`, `callback-server`) are solid.

## v0.5 — Hardening before UI

Capability-layer items that land before the v0.6 UI milestone designs against the surface. The milestone goal is "finish the capability work so the UI is a pure design+build problem," not "every nice-to-have."

### Adds

- **Topology change events** — live `ZoneGroupTopology` subscription. Resolves the freshness contract: regrouping in the Sonos app updates oto's view automatically, no re-`discover()` required. Subsumes the previous "cache-miss → re-fetch-once → retry self-heal" item; reconsider that only if topology events leave windows where misses still occur in practice.
- **Group form/break** commands — was deferred at the v0.3 boundary. Mutating SOAP (`GroupManagement` / `x-rincon:` `SetAVTransportURI`) was not de-risked by the v0.3 spike and gets its own spike + design when scheduled. The `Wire` trait grows additively; form/break mutates topology, then topology events surface the change.
- **Reactive-vs-NOTIFY revisit** — review the v0.4 pre-milestone spike decision with production data from v0.4 dogfooding (`event-tail.rs` traces). Re-pick if topology events expose new reliability evidence; otherwise leave as-is.
- **Android `MulticastLock`** (`native/src/api.rs`, `TODO(v0.5)`). Android silently drops SSDP multicast without a held `WifiManager.MulticastLock`. The Android main manifest declares `INTERNET` + `CHANGE_WIFI_MULTICAST_STATE`, but the lock acquisition is platform code that's currently deferred. **Android release** discovery is non-functional until this lands; the debug APK works because Flutter tooling supplies `INTERNET`.
- **Speaker `model` string repopulate** (`oto_core::SpeakerIdentity::model`, `TODO(v0.5)`). ZoneGroupTopology carries no model attribute (only `<VanishedDevices>` entries do), so `model` is `None` since v0.3. Repopulate via a bounded per-member `device_description.xml` fetch over the authoritative topology member set — zero type/FRB change required.

### Explicit non-goals

- **No UI design or implementation.** The UI is v0.6.
- **No new feature surface beyond the listed items.** Hardening means "what was deferred to make the v0.4 milestone smaller," not a grab-bag.

## v0.6 — UI

The designed Flutter interface on the proven capability layers. Pure design + implementation work against a feature-complete `Wire` + event stream + FRB surface. No further capability-layer additions in this milestone.

## v1.0 — Stable

Externally tested, packaged: signed Android, signed Windows. **Bounded.** After v1.0, expect maintenance only — bug fixes, security updates. No new milestone-scale features. Per [README § Scope](../README.md#scope), this is a side project; resisting feature creep at v1.0 is part of the project's identity.

## Project-bound open items

Work items, not technical unknowns. Technical knowledge lives in [sonos-notes.md](sonos-notes.md).

### Upstream multi-NIC SSDP PR

`oto-wire/src/ssdp.rs` is a near-drop-in better implementation of `sonos-sdk-discovery`'s `SsdpClient`. The fix is localized — enumerate interfaces, per-NIC bind, `set_multicast_if_v4` — and need not change the public `DiscoveryIterator` API.

Offer as a PR against [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76). Acceptance is upside-only: oto-wire keeps its own SSDP either way (the [`oto-wire` boundary](ARCHITECTURE.md#crates) — only crate that touches the SDK), so there's no fork-maintenance burden if upstream declines.

### IPv6 SSDP coverage

`oto-wire/src/ssdp.rs` enumerates IPv4 interfaces only and joins `239.255.255.250:1900`. Sonos S2 devices also advertise on `[FF02::C]:1900`. An IPv6-only LAN — or one where the v4 path is blocked/firewalled per-NIC — would currently see zero speakers.

Hypothetical today: oto's two targets (Windows, Android) default to dual-stack with v4 reachable to the speaker's `/24`. Worth recording. Revisit when:

- A real user reports a v6-only or v4-broken-per-NIC failure, **or**
- The upstream PR above asks about dual-stack shape (drives whether the v4-only fix is the right upstream PR shape).
