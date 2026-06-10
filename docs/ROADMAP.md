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
| v0.5.1 | released | **Group operations** — form/break, group volume/mute (commands + read/event), fast topology refresh after a regroup (no SSDP re-discovery) |
| v0.6.0 | next | **UI: foundation + Home + Now Playing** — theming, source-model state architecture, adaptive shell, persistence |
| v0.6.1 | planned | **UI: room management** — group editor + room detail |
| v0.6.2 | planned | **UI: settings + states** — settings + empty/error/loading/offline states |
| v0.6.3 | planned | **UI: responsive** — tablet master-detail, desktop three-pane |
| v0.7.0 | planned | **Hardening + polish** — SSDP hardening, cleanup TODOs, dogfooding finds |
| v1.0   | future | Stable — externally tested, packaged |

v0.1–v0.4 are verified on Windows. **v0.5 hardware acceptance — PASS** (2026-06-02/03, 2-speaker LAN + a real Android device): live topology events (regroup → `TopologyChanged`; validated with a `refresh_topology` re-pull; no seed-induced rediscover loop), speaker-model repopulation, the v0.4 regression suite (incl. a 28.5 min renewal cycle), and **Android *release* discovery** working via the held `WifiManager.MulticastLock` (it was non-functional before). Evidence at [docs/evidence/v0.5-release/](evidence/v0.5-release/README.md). Earlier: v0.4 full evidence at [docs/evidence/v0.4-release/](evidence/v0.4-release/README.md); the Android debug-APK smoke at [docs/evidence/v0.5-android-debug.md](evidence/v0.5-android-debug.md).

## v0.4 — Live property events (released)

Reactive state via GENA: Rust → Dart event stream, no oto-owned polling. **Property events only** — volume, mute, transport state, current track. The chosen upstream reactive layer maintains GENA subscriptions and also polls internally for the few properties Sonos doesn't NOTIFY; v0.4 does not add a second oto polling loop. Topology change events and group form/break stay v0.5 (see below).

### Shipped

- `StateManager` in `oto-app` caching per-speaker (Volume / Mute) and per-group (Playback / Track) properties. Mutated by `apply_event_at_generation` from the FRB-worker consumer loop in `api.rs::subscribe_change_events`; read by the cache-backed `oto-app::speaker_state`.
- One multiplexed event-pump thread per active wire in `oto-wire` (not per-speaker, per the [event-model design note](sonos-notes.md#opt-in-via-watch--one-multiplexed-pump-thread)). Per-property watches via `watch_property_with_subscription`; coordinator-only AVTransport filter so Playback events carry a `GroupId`. Drop-safe via `Arc<AtomicBool>` stop flag + `recv_timeout` polling — the SDK's `StateManager::Clone` fans out independent senders, so sender-close is not a viable shutdown signal.
- Single FRB stream surface `subscribe_change_events(sink: StreamSink<ChangeEventDto>)` with `ChangeEventDto::{Volume, Mute, Playback, Track, SubscriptionError, SubscriptionRecovered}`. Riverpod `subscribeChangeEventsProvider` depends on `discoveryProvider` and auto-rebuilds on re-discovery; the FRB stream completes cleanly when the wire is replaced.
- `Wire::speaker_state` impl swaps SOAP-per-call → `StateManager` cache read. The `Wire` *signature* is unchanged; the trait method is kept for hardware-baseline reads (used by `live_events` tests) and `MockWire` unit tests, but `oto-app::speaker_state` no longer dispatches it in production.
- Generation token (`AtomicU64`) on `StateManager` makes the `discover_with` wire replacement race-free: bump-and-clear runs before slot swap, OLD-wire consumer's in-flight applies fail the gen check and no-op against the freshly-cleared cache.
- `native/examples/event-tail.rs` — small dogfooding binary that subscribes to the event stream and prints changes. Produces the production-data evidence for the v0.5 reactive-vs-NOTIFY revisit; not a user-facing CLI.

### Out of scope (deferred to v0.5)

- **Topology change events.** Live `ZoneGroupTopology` subscription. `discover()` remains the only topology source through v0.4; a stale `GroupId` still returns `WireError::NotFound`.
- **Group form/break** commands. Same surface as topology events (`GroupManagement` / `ZoneGroupTopology`); re-scoped to **v0.5.1** (own spike + mutating-SOAP design).
- **In-band per-speaker SubscriptionError surfacing.** The SDK at `=0.5.2` does not expose per-speaker subscription failures (`watch_property_with_subscription` swallows them with a `tracing::warn!` and returns `Ok`). v0.4 carries the `ChangeEvent::SubscriptionError` / `SubscriptionRecovered` variants on the trait surface so the contract is forward-compatible, but production never emits them. Address in v0.5 either via an SDK feature or a wire-side timeout-driven sweep.

### Decisions captured against the chosen path

The "upstream reactive layer vs. raw `callback-server` + own change-detection" decision was made before v0.4 implementation began, by a small hardware spike against the 4-speaker LAN (reactive layer chosen — see [`docs/evidence/v0.4-spike/findings.md`](evidence/v0.4-spike/findings.md)). The raw callback-server alternative stays a v0.5 reconsideration point if topology events expose new reliability evidence. Detail on the chosen path's quirks lives in [sonos-notes.md § Event model](sonos-notes.md#event-model-v04-load-bearing) and [§ Ergonomic footgun](sonos-notes.md#ergonomic-footgun-bare-statemanagernew).

## v0.5 — Hardening before UI

Capability-layer items that land before the v0.6 UI milestone designs against the surface. The milestone goal is "finish the capability work so the UI is a pure design+build problem," not "every nice-to-have."

### Shipped

- ✅ **Topology change events.** Live ZoneGroupTopology via a per-speaker `GroupMembership` watch on the v0.4 `ChangeEvent` stream (payload-less `TopologyChanged`); the Dart `TopologyController` debounces 250 ms then refreshes (v0.5 shipped a full SSDP re-discover; **v0.5.1** swapped in the no-SSDP fast `refresh_topology` re-discover). The controller is implemented + unit-tested but **dormant in v0.5's headless build** (no UI watches it yet — the v0.6 UI activates it). Additive `Wire` trait (`subscribe_topology` + `refresh_topology`); the pump guards against a subscribe-seed loop and post-regroup stale routing. Stale `GroupId` → `NotFound` remains the fallback.
- ✅ **In-band per-speaker subscription-failure surfacing.** `SubscriptionError` / `SubscriptionRecovered` (carried on the surface since v0.4 but never emitted — the SDK at `=0.5.2` swallows subscription failures internally) now emit **reactively from command dispatch**: `oto-app` tracks per-speaker `Healthy ↔ Errored` and emits on the edge — `WireError::Network` from a Healthy speaker → `SubscriptionError`; `Ok` from an Errored speaker → `SubscriptionRecovered` (`Backend`/`NotFound` don't flip health). Richer strategies (tracing capture, heartbeat probe) are recorded post-1.0 candidates below.
- ✅ **Reactive-vs-NOTIFY revisit — closed.** ~80 min of combined production `event-tail` traces (idle + active) confirmed the chosen reactive layer stable: 0 errors, renewals clean at ~82% TTL, all events prompt and complete, no cross-speaker bleed — the raw callback-server reconsideration trigger was not met. Detail in [sonos-notes.md § Reactive-vs-NOTIFY traces](sonos-notes.md#reactive-vs-notify-traces--p0b-validation-v05). Notes: double Track events need last-wins dedup (~200 ms window); `Transitioning` Playback state passes through or maps to `Loading`.
- ✅ **Android `MulticastLock`.** A `WifiManager.MulticastLock` (Kotlin `MulticastLockHandler` over a MethodChannel) is held around `discover()`'s SSDP window — without it Android drops the inbound SSDP multicast and release-build discovery finds nothing. Best-effort on the Dart side (a lock failure doesn't abort discovery).
- ✅ **Speaker `model` string repopulate.** `SpeakerIdentity.model` is repopulated by a bounded, parallel per-member `device_description.xml` fetch (`ureq`) inside `discover()` + `refresh_topology()`; best-effort (a failed fetch leaves `model = None`).
- ✅ **Lock-granularity revisit — closed, not triggered.** v0.4 dogfooding showed no contention; the v0.5 acceptance suite (incl. a 28.5 min renewal cycle with the topology-event stream active) showed none either. No lock narrowing needed.

### Deferred to v0.5.1 — shipped

- **Group form/break**, **group volume/mute**, and the **fast topology refresh** all shipped in v0.5.1 (see the v0.5.1 section below).

### Explicit non-goals

- **No UI design or implementation.** The UI is v0.6.
- **No new feature surface beyond the listed items.** Hardening means "what was deferred to make the v0.4 milestone smaller," not a grab-bag.

## v0.5.1 — Group operations (released)

The last capability-layer release before the v0.6 UI: the deferred group form/break plus the group-volume gap surfaced during planning, so v0.6 is a pure design+build problem.

### Shipped

- ✅ **Group form/break.** `Wire::join_group(speaker, coordinator)` (`x-rincon:` `SetAVTransportURI`) + `leave_group(speaker)` (`BecomeCoordinatorOfStandaloneGroup`), additive across all layers. Uniform — no coordinator branch (firmware re-elects; topology events surface the settled result). Form/break does **not** self-trigger a refresh; the existing `GroupMembership` event path drives it (hardware finding: an immediate post-mutation re-pull races the topology settle).
- ✅ **Group volume/mute — commands + read/event.** `set_group_volume` / `set_group_mute` (GroupRenderingControl, coordinator-routed) plus `ChangeEvent::{GroupVolume, GroupMute}` on the existing stream, cached per-`GroupId` in the `StateManager`. Group-scoped values are read via the SDK's `get_group_property` (not the per-speaker `get_property`, which reads `speaker_props` and would silently drop every group event).
- ✅ **Fast topology refresh.** A regroup now refreshes in ~tens of ms instead of a ~3–5 s SSDP re-discover: `refresh_topology()` re-pulls topology from a cached IP (no SSDP) and installs a fresh seeded wire through the proven `discover_with` lifecycle (new pump, generation bump, Dart event re-subscribe). Refined from the plan's "same-wire pump respawn" — that would have stranded the event receiver, since the Dart re-subscribe keys on a `discoveryProvider` transition.

### Process

Spike-gated, risk-ordered (spike → form/break → group volume → fast topology refresh), one PR per workstream, hardware-validated on the 2-zone LAN (Beam + Sonos One). Durable Sonos facts in [sonos-notes.md § Group operations](sonos-notes.md). Two production-breaking event-lifecycle bugs (group events read from the wrong property store; a value-equal refresh stranding the stream) were caught by independent `/codex` review before merge. One hardware-gated group-volume live test is known-flaky on the shared 2-zone LAN; the seeded-fast-rediscover live test covers the same command+event path reliably.

## v0.6 — UI

The designed Flutter interface on the proven capability layers — pure design + implementation, no new capability-layer work. The visual design system landed in [`docs/design-system/`](design-system/handoff/HANDOFF.md) (tokens, screens, states, responsive, brand). v0.6 builds the **backend-true core**: exactly the controls the `Wire` + event stream support today. Controls in the design that need new backend (shuffle/repeat/seek, queue, EQ/Sound) or are outside oto's scope (search/library, stereo pair, surround, TruePlay, add-speaker, sleep timer, telemetry) are **not rendered** — deferred to later milestones together with their backend work, never faked or shown disabled.

Shipped as phased, independently-runnable sub-releases (matching the v0.5 → v0.5.1 cadence; each provable end-to-end and dogfoodable):

- **v0.6.0 — Foundation + Home + Now Playing.** Theming (tokens → `ThemeData` + a `ThemeExtension` for the non-Material roles; bundled Geist; light/dark; user-selectable accent), the **source-model state architecture** (a keep-alive `householdProvider` that accumulates per-room / per-group state from discovery + the live event stream, a `sourcesFromRooms` derived selector, and optimistic command updates), the adaptive app shell, and local prefs persistence — then Home (Cards / Stack toggle) + Now Playing. This phase also de-risks the one genuinely novel piece: the event → view-model layer.
- **v0.6.1 — Room management.** Group editor (join / leave / ungroup) + Room detail (now-playing + per-room volume; the Sound / TV / System sections need backend that doesn't exist yet, so they're deferred). Also the **Now Playing progress bar**, deferred from v0.6.0: the live `Track` event carries no duration (the SDK's reactive `CurrentTrack` lacks it) and the backend doesn't event position, so the bar must poll `speakerState` (GetPositionInfo) for the track duration + a position anchor and tick locally. The `now_playing.dart` `positionAt` / `NowPlayingPosition` logic is already written + tested for this.
- **v0.6.2 — Settings + states.** Settings (theme, default layout, about, read-only devices list) + the empty / error / loading / offline states.
- **v0.6.3 — Responsive.** Tablet master-detail + desktop three-pane (Windows is first-class); the bottom strip dissolves into a persistent pane.

The genuinely-novel work is concentrated in v0.6.0's state architecture; the rest is faithful translation of an already-complete visual design.

## v0.7 — Hardening + polish

A small bucket after the UI: **SSDP hardening** (validate the `200` status line + `ST` + match the `LOCATION` host to the responder's source IP + cap the candidate count — the accepted, low-impact LAN risk documented in [ARCHITECTURE § Known constraints](ARCHITECTURE.md#known-constraints); the marker is the `TODO` in `native/crates/wire/src/ssdp.rs`), the cleanup TODOs (remove the dev `MockWire` injection seam once UI integration tests cover the path; stale doc comments), and whatever UI dogfooding surfaces. SSDP hardening lives entirely in `oto-wire` and is independent of the UI (its own PR), so it was sequenced *after* the UI rather than blocking it — ordering was a batching choice, not a dependency.

## v1.0 — Stable

Externally tested, packaged: signed Android, signed Windows. **Bounded.** After v1.0, expect maintenance only — bug fixes, security updates. No new milestone-scale features. Per [README § Scope](../README.md#scope), this is a side project; resisting feature creep at v1.0 is part of the project's identity.

## Project-bound open items

Work items, not technical unknowns. Technical knowledge lives in [sonos-notes.md](sonos-notes.md).

### Post-1.0 polish — alternative SubscriptionError strategies

v0.5 ships the **reactive strategy** (emit on command-dispatch failure): a speaker is marked unreachable only when the user's next command to it fails with a network error. That misses a speaker that goes silent while idle (no command to observe). Two richer strategies are recorded post-1.0 candidates per [v1.0 polish](sonos-notes.md) — pursue only if real-world dogfooding surfaces "silent speaker" complaints that command-time emission misses:

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
