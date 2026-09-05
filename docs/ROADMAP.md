# Roadmap

Milestone status and forward plan. Sibling docs: [ARCHITECTURE.md](ARCHITECTURE.md) for system structure, [sonos-notes.md](sonos-notes.md) for protocol/SDK reference, [CHANGELOG.md](../CHANGELOG.md) for per-release detail.

## Current status

| Version | Status | What |
|---|---|---|
| v0.1.0 | released | Foundation + LAN identity-only discovery |
| v0.2.0 | released | Playback control + one-shot state read (group-of-one) |
| v0.3.0 | released | Real ZoneGroupTopology grouping - multi-room, coordinator election, bonded satellites folded |
| v0.4.0 | released | Live **property** events (GENA) - Rust → Dart event stream for volume / mute / transport / track |
| v0.5.0 | released | **Hardening before UI** - topology events, SubscriptionError surfacing, Android `MulticastLock`, model repopulate (group form/break → v0.5.1) |
| v0.5.1 | released | **Group operations** - form/break, group volume/mute (commands + read/event), fast topology refresh after a regroup (no SSDP re-discovery) |
| v0.6.0 | released | **UI: foundation + Home + Now Playing** - theming, source-model state architecture, adaptive shell, persistence |
| v0.6.1 | released | **UI: room management** - group editor + room detail |
| v0.6.2 | released | **UI: settings + states** - settings plus a Home presentation state model |
| v0.6.3 | released | **UI: responsive** - tablet master-detail, desktop three-pane |
| v0.6.4 | released | **UI: mute + honest failure** - mute controls, command-failure surfacing, recovery from unreachable state |
| v0.7.0 | planned | **Hardening + polish** - SSDP hardening, cleanup TODOs, dogfooding finds |
| v1.0   | future | Stable - externally tested, packaged |

v0.1–v0.4 are verified on Windows. **v0.5 hardware acceptance - PASS** (2026-06-02/03, 2-speaker LAN + a real Android device): live topology events (regroup → `TopologyChanged`; validated with a `refresh_topology` re-pull; no seed-induced rediscover loop), speaker-model repopulation, the v0.4 regression suite (incl. a 28.5 min renewal cycle), and **Android *release* discovery** working via the held `WifiManager.MulticastLock` (it was non-functional before). Evidence at [docs/evidence/v0.5-release/](evidence/v0.5-release/README.md). Earlier: v0.4 full evidence at [docs/evidence/v0.4-release/](evidence/v0.4-release/README.md); the Android debug-APK smoke at [docs/evidence/v0.5-android-debug.md](evidence/v0.5-android-debug.md).

## v0.4 - Live property events (released)

Reactive state via GENA: Rust → Dart event stream, no oto-owned polling. **Property events only** - volume, mute, transport state, current track. The chosen upstream reactive layer maintains GENA subscriptions and also polls internally for the few properties Sonos doesn't NOTIFY; v0.4 does not add a second oto polling loop. Topology change events and group form/break stay v0.5 (see below).

### Shipped

- `StateManager` in `oto-app` caching per-speaker (Volume / Mute) and per-group (Playback / Track) properties. Mutated by `apply_event_at_generation` from the FRB-worker consumer loop in `api.rs::subscribe_change_events`; read by the cache-backed `oto-app::speaker_state`.
- One multiplexed event-pump thread per active wire in `oto-wire` (not
  per-speaker, per the
  [event-model design note](sonos-notes.md#opt-in-via-watch---one-multiplexed-pump-thread)).
  Per-property watches via `watch_property_with_subscription`;
  coordinator-only AVTransport filter so Playback events carry a `GroupId`.
  Drop-safe through two explicit steps: call
  `SonosEventManager::shutdown()` to break the SDK worker's self-owned `Arc`
  cycle, then stop and join oto's pump via an `Arc<AtomicBool>` flag +
  `recv_timeout` polling. `StateManager::Clone` fans out independent senders,
  so sender-close is not a viable signal for either step.
- Single FRB stream surface `subscribe_change_events(sink: StreamSink<ChangeEventDto>)` with `ChangeEventDto::{Volume, Mute, Playback, Track, SubscriptionError, SubscriptionRecovered}`. Riverpod `subscribeChangeEventsProvider` depends on `discoveryProvider` and auto-rebuilds on re-discovery; the FRB stream completes cleanly when the wire is replaced.
- `Wire::speaker_state` impl swaps SOAP-per-call → `StateManager` cache read. The `Wire` *signature* is unchanged; the trait method is kept for hardware-baseline reads (used by `live_events` tests) and `MockWire` unit tests, but `oto-app::speaker_state` no longer dispatches it in production.
- Generation token (`AtomicU64`) on `StateManager` makes the `discover_with` wire replacement race-free: bump-and-clear runs before slot swap, OLD-wire consumer's in-flight applies fail the gen check and no-op against the freshly-cleared cache.
- `native/examples/event-tail.rs` - small dogfooding binary that subscribes to the event stream and prints changes. Produces the production-data evidence for the v0.5 reactive-vs-NOTIFY revisit; not a user-facing CLI.

### Out of scope (deferred to v0.5)

- **Topology change events.** Live `ZoneGroupTopology` subscription. `discover()` remains the only topology source through v0.4; a stale `GroupId` still returns `WireError::NotFound`.
- **Group form/break** commands. Same surface as topology events (`GroupManagement` / `ZoneGroupTopology`); re-scoped to **v0.5.1** (own spike + mutating-SOAP design).
- **In-band per-speaker SubscriptionError surfacing.** The SDK at `=0.5.2` does not expose per-speaker subscription failures (`watch_property_with_subscription` swallows them with a `tracing::warn!` and returns `Ok`). v0.4 carries the `ChangeEvent::SubscriptionError` / `SubscriptionRecovered` variants on the trait surface so the contract is forward-compatible, but production never emits them. Address in v0.5 either via an SDK feature or a wire-side timeout-driven sweep.

### Decisions captured against the chosen path

The "upstream reactive layer vs. raw `callback-server` + own change-detection" decision was made before v0.4 implementation began, by a small hardware spike against the 4-speaker LAN (reactive layer chosen - see [`docs/evidence/v0.4-spike/findings.md`](evidence/v0.4-spike/findings.md)). The raw callback-server alternative stays a v0.5 reconsideration point if topology events expose new reliability evidence. Detail on the chosen path's quirks lives in [sonos-notes.md § Event model](sonos-notes.md#event-model-v04-load-bearing) and [§ Ergonomic footgun](sonos-notes.md#ergonomic-footgun-bare-statemanagernew).

## v0.5 - Hardening before UI

Capability-layer items that land before the v0.6 UI milestone designs against the surface. The milestone goal is "finish the capability work so the UI is a pure design+build problem," not "every nice-to-have."

### Shipped

- ✅ **Topology change events.** Live ZoneGroupTopology via a per-speaker `GroupMembership` watch on the v0.4 `ChangeEvent` stream (payload-less `TopologyChanged`); the Dart `TopologyController` debounces 250 ms then refreshes (v0.5 shipped a full SSDP re-discover; **v0.5.1** swapped in the no-SSDP fast `refresh_topology` re-discover). The controller is implemented + unit-tested but **dormant in v0.5's headless build** (no UI watches it yet - the v0.6 UI activates it). Additive `Wire` trait (`subscribe_topology` + `refresh_topology`); the pump guards against a subscribe-seed loop and post-regroup stale routing. Stale `GroupId` → `NotFound` remains the fallback.
- ✅ **In-band per-speaker subscription-failure surfacing.** `SubscriptionError` / `SubscriptionRecovered` (carried on the surface since v0.4 but never emitted - the SDK at `=0.5.2` swallows subscription failures internally) now emit **reactively from command dispatch**: `oto-app` tracks per-speaker `Healthy ↔ Errored` and emits on the edge - `WireError::Network` from a Healthy speaker → `SubscriptionError`; `Ok` from an Errored speaker → `SubscriptionRecovered` (`Backend`/`NotFound` don't flip health). Richer strategies (tracing capture, heartbeat probe) are recorded post-1.0 candidates below.
- ✅ **Reactive-vs-NOTIFY revisit - closed.** ~80 min of combined production `event-tail` traces (idle + active) confirmed the chosen reactive layer stable: 0 errors, renewals clean at ~82% TTL, all events prompt and complete, no cross-speaker bleed - the raw callback-server reconsideration trigger was not met. Detail in [sonos-notes.md § Event model](sonos-notes.md#event-model-v04-load-bearing). Notes: double Track events need last-wins dedup (~200 ms window); `Transitioning` Playback state passes through or maps to `Loading`.
- ✅ **Android `MulticastLock`.** A `WifiManager.MulticastLock` (Kotlin `MulticastLockHandler` over a MethodChannel) is held around `discover()`'s SSDP window - without it Android drops the inbound SSDP multicast and release-build discovery finds nothing. Best-effort on the Dart side (a lock failure doesn't abort discovery).
- ✅ **Speaker `model` string repopulate.** `SpeakerIdentity.model` is repopulated by a bounded, parallel per-member `device_description.xml` fetch (`ureq`) inside `discover()` + `refresh_topology()`; best-effort (a failed fetch leaves `model = None`).
- ✅ **Lock-granularity revisit - closed, not triggered.** v0.4 dogfooding showed no contention; the v0.5 acceptance suite (incl. a 28.5 min renewal cycle with the topology-event stream active) showed none either. No lock narrowing needed.

### Deferred to v0.5.1 - shipped

- **Group form/break**, **group volume/mute**, and the **fast topology refresh** all shipped in v0.5.1 (see the v0.5.1 section below).

### Explicit non-goals

- **No UI design or implementation.** The UI is v0.6.
- **No new feature surface beyond the listed items.** Hardening means "what was deferred to make the v0.4 milestone smaller," not a grab-bag.

## v0.5.1 - Group operations (released)

The last capability-layer release before the v0.6 UI: the deferred group form/break plus the group-volume gap surfaced during planning, so v0.6 is a pure design+build problem.

### Shipped

- ✅ **Group form/break.** `Wire::join_group(speaker, coordinator)` (`x-rincon:` `SetAVTransportURI`) + `leave_group(speaker)` (`BecomeCoordinatorOfStandaloneGroup`), additive across all layers. Uniform - no coordinator branch (firmware re-elects; topology events surface the settled result). Form/break does **not** self-trigger a refresh; the existing `GroupMembership` event path drives it (hardware finding: an immediate post-mutation re-pull races the topology settle).
- ✅ **Group volume/mute - commands + read/event.** `set_group_volume` / `set_group_mute` (GroupRenderingControl, coordinator-routed) plus `ChangeEvent::{GroupVolume, GroupMute}` on the existing stream, cached per-`GroupId` in the `StateManager`. Group-scoped values are read via the SDK's `get_group_property` (not the per-speaker `get_property`, which reads `speaker_props` and would silently drop every group event).
- ✅ **Fast topology refresh.** A regroup now refreshes in ~tens of ms instead of a ~3–5 s SSDP re-discover: `refresh_topology()` re-pulls topology from a cached IP (no SSDP) and installs a fresh seeded wire through the proven `discover_with` lifecycle (new pump, generation bump, Dart event re-subscribe). Refined from the plan's "same-wire pump respawn" - that would have stranded the event receiver, since the Dart re-subscribe keys on a `discoveryProvider` transition.

### Process

Spike-gated, risk-ordered (spike → form/break → group volume → fast topology refresh), one PR per workstream, hardware-validated on the 2-zone LAN (Beam + Sonos One). Durable Sonos facts in [sonos-notes.md § Group operations](sonos-notes.md). Two production-breaking event-lifecycle bugs (group events read from the wrong property store; a value-equal refresh stranding the stream) were caught by independent `/codex` review before merge. One hardware-gated group-volume live test is known-flaky on the shared 2-zone LAN; the seeded-fast-rediscover live test covers the same command+event path reliably.

## v0.6 - UI

The designed Flutter interface on the proven capability layers - pure design + implementation, no new capability-layer work. The visual design system lives in [`docs/design-system/`](design-system/README.md) (canonical Dart tokens, the fixture-driven screens/states showcase, and brand assets). v0.6 builds the **backend-true core**: exactly the controls the `Wire` + event stream support today. Controls in the design that need new backend (shuffle/repeat/seek, queue, EQ/Sound) or are outside oto's scope (search/library, stereo pair, surround, TruePlay, add-speaker, sleep timer, telemetry) are **not rendered** - deferred to later milestones together with their backend work, never faked or shown disabled.

Shipped as phased, independently-runnable sub-releases (matching the v0.5 → v0.5.1 cadence; each provable end-to-end and dogfoodable):

- **v0.6.0 - Foundation + Home + Now Playing (released).** Theming (tokens → `ThemeData` + a `ThemeExtension` for the non-Material roles; bundled Geist; light/dark; user-selectable accent), the **source-model state architecture** (a keep-alive `householdProvider` that accumulates per-room / per-group state from discovery + the live event stream, a `sourcesFromRooms` derived selector, and optimistic command updates), the adaptive app shell, and local prefs persistence - then Home (Cards / Stack toggle) + Now Playing. This phase also de-risks the one genuinely novel piece: the event → view-model layer.
- **v0.6.1 - Room management.** Group editor (join / leave / ungroup) + Room detail (now-playing + per-room volume; the Sound / TV / System sections need backend that doesn't exist yet, so they're deferred). Also the **Now Playing progress bar**, deferred from v0.6.0: the live `Track` event carries no duration (the SDK's reactive `CurrentTrack` lacks it) and the backend doesn't event position, so the bar reads a dedicated `track_position` (GetPositionInfo) SOAP call for the track duration + a position anchor and ticks locally. The `now_playing.dart` `positionAt` / `NowPlayingPosition` logic is already written + tested for this.
- **v0.6.2 - Settings + states.** Settings (theme, default layout, about,
  read-only devices list) plus a Home presentation state model for loading,
  empty, discovery-error, and cached-error states, with offline room/device
  presentation.
- **v0.6.3 - Responsive (released).** Tablet master-detail + desktop three-pane (Windows first-class): on wide, the room grid keeps its place beside a persistent Now Playing pane (the phone's floating strip, dissolved), desktop adds a nav rail, Settings and the group editor open as dialogs, Room detail folds away (a wide room tap selects its group into the pane), and the Windows window remembers its size/position. Layout keys off one `LayoutTier` helper read from `MediaQuery`. Completes the designed UI as originally phased; v0.6.4 closes the milestone with what dogfooding and a capability-vs-UI audit surfaced afterwards.

The genuinely-novel work is concentrated in v0.6.0's state architecture; the rest is faithful translation of an already-complete visual design.

## v0.6.4 - Mute + honest failure (released)

The v0.6 closer.

### Shipped

- ✅ **Mute controls.** Per-room mute is available on room cards, rows, and room
  detail; group-master mute is available on group cards and Now Playing.
  Controls use the existing optimistic command/event path, dim muted sliders,
  and retain accessible labels.
- ✅ **Honest command failures.** A failed optimistic command rolls back and
  reports a non-modal SnackBar through the app-lifetime
  `commandFailuresProvider` listener. Messages distinguish network
  unreachability, a Sonos rejection, and a stale topology identifier.
- ✅ **A way out of unreachable state.** User-requested scans clear carried
  health errors, and Home presents a rescan affordance when every cached room is
  unreachable. Automatic topology refreshes preserve health state rather than
  falsely declaring recovery.
- ✅ **Honest device wording.** UI copy says "Unreachable," not "Powered off":
  a failed network command cannot reveal the speaker's power state.
- ✅ **[#129](https://github.com/Oszkar/oto/issues/129) - room options on
  wide.** A solo room in the persistent Now Playing pane exposes the shared
  `RoomOptionsButton`, so grouping remains reachable without resizing.
- ✅ **Pipeline lifecycle hardening.** Wire receivers are paired atomically with
  their generation; stale Rust and Dart consumers are gated out; topology
  refresh is bounded and transactional; and event-pump teardown explicitly
  shuts down the SDK manager before joining oto's pump.
- ✅ **[#105](https://github.com/Oszkar/oto/issues/105) - default vs. current
  Home layout.** Settings persists the startup default, while the Home header
  toggle changes only the current app session. A new session initializes from
  the saved default.

### Explicit non-goals

- **No backend work.** Deliberate constraint, accepted with its consequences - the power-off-vs-unreachable distinction and any richer speaker-health probing stay out (the post-1.0 `SubscriptionError` strategies below are the eventual home for the latter).
- **No new controls that need backend.** Shuffle/repeat/seek, queue, and EQ/Sound stay unrendered under the v0.6 backend-true rule - never faked, never shown disabled. They arrive with their own SOAP work in a later milestone, not here.
- **[#125](https://github.com/Oszkar/oto/issues/125) (Windows CI job)** is not UI and stays parked on its own stated trigger.

## v0.7 - Hardening + polish

A small bucket after the UI: **SSDP hardening** (validate the `200` status line + `ST` + match the `LOCATION` host to the responder's source IP + cap the candidate count - the accepted, low-impact LAN risk documented in [ARCHITECTURE § Known constraints](ARCHITECTURE.md#known-constraints); the marker is the `TODO` in `native/crates/wire/src/ssdp.rs`), the cleanup TODOs (remove the dev `MockWire` injection seam once UI integration tests cover the path; stale doc comments), and whatever UI dogfooding surfaces. SSDP hardening lives entirely in `oto-wire` and is independent of the UI (its own PR), so it was sequenced *after* the UI rather than blocking it - ordering was a batching choice, not a dependency.

## v1.0 - Stable

Externally tested, packaged: signed Android, signed Windows. **Bounded.** After v1.0, expect maintenance only - bug fixes, security updates. No new milestone-scale features. Per [README § Scope](../README.md#scope), this is a side project; resisting feature creep at v1.0 is part of the project's identity.

## Project-bound open items

Work items, not technical unknowns. Technical knowledge lives in [sonos-notes.md](sonos-notes.md).

### Power state vs. network unreachable

oto cannot tell a powered-off speaker from one it simply cannot reach: the only signal is a `WireError::Network` from a dispatched command, which v0.5's reactive health tracking flips to `Errored`. v0.6.4 responds by wording the UI to what is actually known ("unreachable") rather than claiming `Powered off`.

Actually distinguishing the two needs backend - a reachability probe that can separate "no route / no response" from "responds but is in standby", and a story for speakers that are idle rather than off. Related to (and probably solved alongside) the richer `SubscriptionError` strategies below, since both want a wire-side health signal that does not depend on the user issuing a command. Deliberately out of scope for v0.6.4, which is a no-backend release.

Revisit when dogfooding shows the softened wording is not enough - i.e. users are misreading "unreachable" for a speaker that is genuinely off, or vice versa.

### Post-1.0 polish - alternative SubscriptionError strategies

v0.5 ships the **reactive strategy** (emit on command-dispatch failure): a speaker is marked unreachable only when the user's next command to it fails with a network error. That misses a speaker that goes silent while idle (no command to observe). Two richer strategies are recorded post-1.0 candidates per [v1.0 polish](sonos-notes.md) - pursue only if real-world dogfooding surfaces "silent speaker" complaints that command-time emission misses:

- **Approach B - tracing capture.** Install a `tracing` layer that watches for the SDK's internal `warn!` on a swallowed `watch_property_with_subscription` failure and re-emits it as a `SubscriptionError`. Couples to SDK log strings (brittle across version bumps).
- **Approach C - heartbeat probe.** A wire-side timer that periodically checks each speaker's last-NOTIFY age (or a cheap SOAP ping) and emits `SubscriptionError` for ones gone quiet past a threshold, `SubscriptionRecovered` when they return. More code + a polling loop (weigh against the LAN-politeness principle).

### Upstream multi-NIC SSDP PR

`oto-wire/src/ssdp.rs` is a near-drop-in better implementation of `sonos-sdk-discovery`'s `SsdpClient`. The fix is localized - enumerate interfaces, per-NIC bind, `set_multicast_if_v4` - and need not change the public `DiscoveryIterator` API.

**Status:** upstream closed #76 in SDK 0.5.3 by probing interfaces concurrently. SDK 0.8 still lacks oto's explicit `set_multicast_if_v4` egress selection and absolute receive deadline; oto retains both. The egress pin was hardware-validated non-regressive on the dev LAN, where the LAN NIC is already the default multicast interface. Remaining upstream work is offering those two safeguards and validating a non-default-NIC setup.

Use [#76](https://github.com/tatimblin/sonos-sdk/issues/76) as background for a follow-up. Replacing oto's SSDP is conditional on equivalent safeguards and hardware validation; no discovery replacement is part of the SDK 0.8 migration.

### Upstream TLS-feature cleanup

Resolved by the aligned SDK 0.8 upgrade. Upstream [#107](https://github.com/tatimblin/sonos-sdk/pull/107) removed the affected HTTP dependencies; oto now resolves from crates.io and retires its TLS fork ([LOCAL_PATCHES.md](../LOCAL_PATCHES.md) #2). No upstream TLS patch remains to file.

### IPv6 SSDP coverage

`oto-wire/src/ssdp.rs` enumerates IPv4 interfaces only and joins `239.255.255.250:1900`. Sonos S2 devices also advertise on `[FF02::C]:1900`. An IPv6-only LAN - or one where the v4 path is blocked/firewalled per-NIC - would currently see zero speakers.

Hypothetical today: oto's two targets (Windows, Android) default to dual-stack with v4 reachable to the speaker's `/24`. Worth recording. Revisit when:

- A real user reports a v6-only or v4-broken-per-NIC failure, **or**
- The upstream PR above asks about dual-stack shape (drives whether the v4-only fix is the right upstream PR shape).
