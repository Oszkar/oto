# Roadmap

Milestone status and forward plan. Sibling docs: [ARCHITECTURE.md](ARCHITECTURE.md) for system structure, [sonos-notes.md](sonos-notes.md) for protocol/SDK reference, [CHANGELOG.md](../CHANGELOG.md) for per-release detail.

## Current status

| Version | Status | What |
|---|---|---|
| v0.1.0 | released | Foundation + LAN identity-only discovery |
| v0.2.0 | released | Playback control + one-shot state read (group-of-one) |
| v0.3.0 | released | Real ZoneGroupTopology grouping — multi-room, coordinator election, bonded satellites folded |
| v0.4.0 | released | Live **property** events (GENA) — Rust → Dart event stream for volume / mute / transport / track |
| v0.5.0 | released | **Hardening before UI** — topology events, SubscriptionError surfacing, Android `MulticastLock`, model repopulate (group form/break → v0.5.1) |
| v0.6   | next | The designed Flutter UI |
| v1.0   | future | Stable — externally tested, packaged |

v0.1–v0.4 are verified on Windows. **v0.5 hardware acceptance — PASS** (2026-06-02/03, 2-speaker LAN + a real Android device): S1 topology events (regroup → `TopologyChanged` + refresh, no rediscover loop), S4 model repopulate, the v0.4 regression suite (incl. a 28.5 min renewal cycle), and **S3 — Android *release* discovery now works** with the held `WifiManager.MulticastLock` (it was non-functional before). Evidence at [docs/superpowers/specs/2026-06-02-v0.5-release-evidence/](superpowers/specs/2026-06-02-v0.5-release-evidence/README.md). Earlier: v0.4 full evidence at [2026-05-25-v0.4-release-evidence/](superpowers/specs/2026-05-25-v0.4-release-evidence/); P0a debug-APK smoke at [2026-05-30-v0.5-android-debug-evidence.md](superpowers/specs/2026-05-30-v0.5-android-debug-evidence.md).

## v0.4 — Live property events (released)

Reactive state via GENA: Rust → Dart event stream, no oto-owned polling. **Property events only** — volume, mute, transport state, current track. The chosen upstream reactive layer maintains GENA subscriptions and also polls internally for the few properties Sonos doesn't NOTIFY; v0.4 does not add a second oto polling loop. Topology change events and group form/break stay v0.5 (see below).

### Shipped

- `StateManager` in `oto-app` caching per-speaker (Volume / Mute) and per-group (Playback / Track) properties. Mutated by `apply_event_at_generation` from the FRB-worker consumer loop in `api.rs::subscribe_change_events`; read by the cache-backed `oto-app::speaker_state`.
- One multiplexed event-pump thread per active wire in `oto-wire` (not per-speaker, per the [event-model design note](sonos-notes.md#opt-in-via-watch--one-multiplexed-pump-thread)). Per-property watches via `watch_property_with_subscription`; coordinator-only AVTransport filter so Playback events carry a `GroupId`. Drop-safe via `Arc<AtomicBool>` stop flag + `recv_timeout` polling — the SDK's `StateManager::Clone` fans out independent senders, so sender-close is not a viable shutdown signal.
- Single FRB stream surface `subscribe_change_events(sink: StreamSink<ChangeEventDto>)` with `ChangeEventDto::{Volume, Mute, Playback, Track, SubscriptionError, SubscriptionRecovered}`. Riverpod `subscribeChangeEventsProvider` depends on `discoveryProvider` and auto-rebuilds on re-discovery; the FRB stream completes cleanly when the wire is replaced.
- `Wire::speaker_state` impl swaps SOAP-per-call → `StateManager` cache read (Slice 4). The `Wire` *signature* is unchanged; the trait method is kept for hardware-baseline reads (used by `live_events` tests) and `MockWire` unit tests, but `oto-app::speaker_state` no longer dispatches it in production.
- Generation token (`AtomicU64`) on `StateManager` makes the `discover_with` wire replacement race-free: bump-and-clear runs before slot swap, OLD-wire consumer's in-flight applies fail the gen check and no-op against the freshly-cleared cache.
- `native/examples/event-tail.rs` — small dogfooding binary that subscribes to the event stream and prints changes. Produces the production-data evidence for the v0.5 reactive-vs-NOTIFY revisit; not a user-facing CLI.

### Out of scope (deferred to v0.5)

- **Topology change events.** Live `ZoneGroupTopology` subscription. `discover()` remains the only topology source through v0.4; a stale `GroupId` still returns `WireError::NotFound`.
- **Group form/break** commands. Same surface as topology events (`GroupManagement` / `ZoneGroupTopology`); re-scoped to **v0.5.1** (own spike + mutating-SOAP design — see v0.5 design § 1).
- **In-band per-speaker SubscriptionError surfacing.** The SDK at `=0.5.2` does not expose per-speaker subscription failures (`watch_property_with_subscription` swallows them with a `tracing::warn!` and returns `Ok`). v0.4 carries the `ChangeEvent::SubscriptionError` / `SubscriptionRecovered` variants on the trait surface so the contract is forward-compatible, but production never emits them. Address in v0.5 either via an SDK feature or a wire-side timeout-driven sweep.

### Decisions captured against the chosen path

The "upstream reactive layer vs. raw `callback-server` + own change-detection" decision was made before v0.4 implementation began, by a small hardware spike against the 4-speaker LAN (Path A chosen — see [`docs/superpowers/specs/2026-05-22-v0.4-spike-findings.md`](superpowers/specs/2026-05-22-v0.4-spike-findings.md)). The non-chosen Path B stays a v0.5 reconsideration point if topology events expose new reliability evidence. Detail on the chosen path's quirks lives in [sonos-notes.md § Event model](sonos-notes.md#event-model-v04-load-bearing) and [§ Ergonomic footgun](sonos-notes.md#ergonomic-footgun-bare-statemanagernew).

## v0.5 — Hardening before UI

Capability-layer items that land before the v0.6 UI milestone designs against the surface. The milestone goal is "finish the capability work so the UI is a pure design+build problem," not "every nice-to-have."

### Adds (concrete v0.4 carryovers + originals)

- ✅ **Topology change events — DONE (S1).** Live ZoneGroupTopology via a per-speaker `GroupMembership` watch on the v0.4 `ChangeEvent` stream (payload-less `TopologyChanged`); the Dart `TopologyController` debounces 250 ms then re-discovers (Option A — full rebuild; the SOAP `refresh_topology` fast-path is deferred to v0.6). Additive `Wire` trait (`subscribe_topology` + `refresh_topology`). Pump guards a seed-suppression + post-regroup dirty-drop (codex cumulative-review fixes). Stale `GroupId` → `NotFound` remains the fallback.
- **Group form/break** commands — **deferred to v0.5.1** (re-scoped in the v0.5 design, 2026-05-28). Mutating SOAP (`GroupManagement` / `x-rincon:` `SetAVTransportURI`) was not de-risked by the v0.3 spike and gets its own spike + design + milestone. The `Wire` trait grows additively; form/break mutates topology, then topology events surface the change. Not part of the v0.5 hardening scope below.
- ✅ **In-band per-speaker subscription failure surfacing — DONE (S2, Approach A).** v0.4 carried `SubscriptionError` / `SubscriptionRecovered` on the surface but never emitted them (the SDK at `=0.5.2` swallows subscription failures internally). S2 emits them **reactively from command dispatch**: `oto-app` tracks per-speaker `Healthy ↔ Errored` and emits on the edge — `WireError::Network` from a Healthy speaker → `SubscriptionError`; `Ok` from an Errored speaker → `SubscriptionRecovered` (`Backend`/`NotFound` don't flip health). Events ride a sibling app-event channel the FRB consumer drains alongside the wire channel. Approaches **B** (tracing-driven SDK `warn!` capture) and **C** (heartbeat probe) are recorded post-1.0 candidates below.
- ✅ **Reactive-vs-NOTIFY revisit — DONE (P0b, 2026-06-01).** Production `event-tail` traces (~80 min combined, idle + active) confirmed Path A (sonos-sdk-state) stable: 0 errors, renewals clean at ~82% TTL, all events prompt and complete, no cross-speaker bleed. Path B reconsideration trigger not met. See `docs/sonos-notes.md` § "Reactive-vs-NOTIFY traces — P0b validation". S1 notes: double Track events need last-wins dedup (~200 ms window); `Transitioning` Playback state passes through or maps to `Loading`.
- ✅ **Android `MulticastLock` — DONE (S3).** A `WifiManager.MulticastLock` (Kotlin `MulticastLockHandler` over a MethodChannel) is held around `discover()`'s SSDP window — without it Android drops the inbound SSDP multicast and release-build discovery finds nothing. Best-effort on the Dart side (a lock failure doesn't abort discovery).
- ✅ **Speaker `model` string repopulate — DONE (S4).** `SpeakerIdentity.model` is repopulated by a bounded, parallel per-member `device_description.xml` fetch (`ureq`) inside `discover()` + `refresh_topology()`; best-effort (a failed fetch leaves `model = None`).
- ✅ **Lock-granularity revisit (S5) — CLOSED, not triggered.** v0.4 dogfooding showed no contention; the v0.5 acceptance suite (incl. a 28.5 min renewal cycle with the topology-event stream active) showed no contention or stutter either. No lock narrowing needed.

### Explicit non-goals

- **No UI design or implementation.** The UI is v0.6.
- **No new feature surface beyond the listed items.** Hardening means "what was deferred to make the v0.4 milestone smaller," not a grab-bag.

## v0.6 — UI

The designed Flutter interface on the proven capability layers. Pure design + implementation work against a feature-complete `Wire` + event stream + FRB surface. No further capability-layer additions in this milestone.

## v1.0 — Stable

Externally tested, packaged: signed Android, signed Windows. **Bounded.** After v1.0, expect maintenance only — bug fixes, security updates. No new milestone-scale features. Per [README § Scope](../README.md#scope), this is a side project; resisting feature creep at v1.0 is part of the project's identity.

## Project-bound open items

Work items, not technical unknowns. Technical knowledge lives in [sonos-notes.md](sonos-notes.md).

### Post-1.0 polish — alternative SubscriptionError strategies

v0.5 S2 ships **Approach A** (reactive on command-dispatch failure): a speaker is marked unreachable only when the user's next command to it fails with a network error. That misses a speaker that goes silent while idle (no command to observe). Two richer strategies are recorded post-1.0 candidates per [v1.0 polish](sonos-notes.md) — pursue only if real-world dogfooding surfaces "silent speaker" complaints that command-time emission misses:

- **Approach B — tracing capture.** Install a `tracing` layer that watches for the SDK's internal `warn!` on a swallowed `watch_property_with_subscription` failure and re-emits it as a `SubscriptionError`. Couples to SDK log strings (brittle across version bumps).
- **Approach C — heartbeat probe.** A wire-side timer that periodically checks each speaker's last-NOTIFY age (or a cheap SOAP ping) and emits `SubscriptionError` for ones gone quiet past a threshold, `SubscriptionRecovered` when they return. More code + a polling loop (weigh against the LAN-politeness principle).

### Upstream multi-NIC SSDP PR

`oto-wire/src/ssdp.rs` is a near-drop-in better implementation of `sonos-sdk-discovery`'s `SsdpClient`. The fix is localized — enumerate interfaces, per-NIC bind, `set_multicast_if_v4` — and need not change the public `DiscoveryIterator` API.

**Status:** the `set_multicast_if_v4` egress pin now actually exists in oto-wire (it was described here before it was implemented — closed that drift). Landed + hardware-validated non-regressive on the 4-speaker LAN; #76 stays dormant on the dev host (its LAN NIC is the OS default multicast interface), so the upstream value is for hosts where Sonos sits behind a non-default NIC. Remaining work is purely **offering** the localized fix upstream — adapting it onto upstream's `SsdpClient` shape (more than a copy-paste) and testing against their code.

Offer as a PR against [`tatimblin/sonos-sdk#76`](https://github.com/tatimblin/sonos-sdk/issues/76). Acceptance is upside-only: oto-wire keeps its own SSDP either way (the [`oto-wire` boundary](ARCHITECTURE.md#crates) — only crate that touches the SDK), so there's no fork-maintenance burden if upstream declines.

### IPv6 SSDP coverage

`oto-wire/src/ssdp.rs` enumerates IPv4 interfaces only and joins `239.255.255.250:1900`. Sonos S2 devices also advertise on `[FF02::C]:1900`. An IPv6-only LAN — or one where the v4 path is blocked/firewalled per-NIC — would currently see zero speakers.

Hypothetical today: oto's two targets (Windows, Android) default to dual-stack with v4 reachable to the speaker's `/24`. Worth recording. Revisit when:

- A real user reports a v6-only or v4-broken-per-NIC failure, **or**
- The upstream PR above asks about dual-stack shape (drives whether the v4-only fix is the right upstream PR shape).
