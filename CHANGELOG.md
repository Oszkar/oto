# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog][kac]; the project follows [Semantic Versioning][semver]. While pre-1.0 (`0.y.z`), the public surface and behavior may change between any releases.

## [Unreleased]

## [0.5.0] - 2026-06-03

v0.5 — Hardening before the v0.6 UI: live topology events, subscription-failure surfacing, Android release discovery, and speaker-model names. All event additions ride the single v0.4 `Stream<ChangeEventDto>` — no stream-surface redesign.

### Added

- **Topology change events.** Grouping or ungrouping speakers in the Sonos app now updates oto live: a regroup surfaces as a `TopologyChanged` event on the existing change-event stream, and the app re-discovers to pick up the new grouping. The controller is implemented and tested but dormant until the v0.6 UI watches it. The `Wire` trait grows additively with `subscribe_topology` + `refresh_topology`.
- **Subscription-failure surfacing.** `SubscriptionError` / `SubscriptionRecovered` (on the API since v0.4 but never emitted — the SDK at `=0.5.2` swallows subscription failures) now emit when a command to a speaker fails with a network error, and again when it recovers, so the UI can show a speaker as unreachable.
- **Android release discovery.** Discovery now works in release builds on Android by holding a `WifiManager.MulticastLock` around the SSDP window — without it Android silently drops the discovery multicast, so release builds found nothing.
- **Speaker model names.** `SpeakerIdentity.model` (empty since v0.3, because the topology XML carries no model) is repopulated — e.g. "Sonos Beam" — via a best-effort per-speaker `device_description.xml` fetch during discovery.

### Changed

- The Dart event-stream provider re-subscribes only on a *successful* re-discovery, so a failed re-discover no longer tears the live stream down onto a dead receiver.

### Fixed

- **SSDP multicast egress on multi-NIC hosts** ([tatimblin/sonos-sdk#76](https://github.com/tatimblin/sonos-sdk/issues/76)): discovery now pins each socket's outgoing multicast interface, so the M-SEARCH leaves the right NIC instead of whatever the OS routing table picks. Hardware-validated non-regressive.
- Hardened the live event/topology path: a regroup-triggered re-discover loop, stale event routing after a regroup, a failed-rediscover event-stranding case, and several discovery/subscription races found in review.

### Known issues

- A speaker that goes silent *while idle* isn't flagged until the next command to it fails (richer detection is a post-1.0 candidate).
- A regroup triggers a full ~3–5 s re-discover; the fast SOAP-only refresh lands in v0.6.
- **Group form/break** commands are deferred to v0.5.1.

### Housekeeping

- CI compile-guards the hardware-gated live tests so they can't bit-rot (never runs them — the LAN is untouched). Dependabot tuned for the pinned `sonos-api` / `quick-xml` / `socket2` deps.

Validated on real hardware: a 2-speaker LAN (Sonos Beam + Sonos One) and a real Android device. Evidence under [`docs/evidence/v0.5-release/`](docs/evidence/v0.5-release/README.md).

## [0.4.0] - 2026-05-26

v0.4 — Live property events. Reactive state via GENA: a Rust → Dart event stream with no oto-owned polling. Property events only — volume, mute, transport state, current track; topology change events and group form/break stay v0.5.

### Added

- **Live event stream.** A new FRB `subscribe_change_events` surface delivers a single `Stream<ChangeEventDto>` (`Volume`, `Mute`, `Playback`, `Track`, plus the forward-looking `SubscriptionError` / `SubscriptionRecovered`). One multiplexed event-pump thread per wire in `oto-wire` wraps the upstream reactive SDK stack (all pinned `=0.5.2`); volume/mute are per-speaker, transport/track per group coordinator.
- **Event-fed state cache.** `oto-app` now holds an event-fed `StateManager` cache (per-speaker volume/mute, per-group playback/track), so `speaker_state` reads the cache instead of issuing a SOAP call per read. State lives in Rust and survives Flutter hot reload.
- **`native/examples/event-tail.rs`** — a dogfood binary that subscribes to the stream and prints changes (not a user-facing CLI).
- **Hardware-gated live tests** (`--features live-tests`): seed events, operator volume change, per-group play/pause, a double-discover regression, and a ~28 min renewal-cycle observation.

### Changed

- `speaker_state` is now a cache read, not a SOAP read — implementation only; the public signature is unchanged.
- Discovery auto-subscribes the new wire's speakers, so a Dart consumer sees seed events without driving subscription itself.
- "Watch-after-fetch event suppression" moved from open constraint to resolved (a bare `.watch()` is its own seed probe).

### Fixed

- **SSDP starvation under many quiet sockets:** the discovery wait is now collective (multiplexed), so a dozen idle adapters (VPN / Hyper-V / WSL / Docker on Windows) can't consume the whole bounded window before a real responder is reached.
- **All-NIC-fail diagnostic:** when every interface fails to bind/send, discovery returns a network error with the underlying cause instead of falsely reporting an empty LAN.
- **Concurrent discovery race:** overlapping discoveries are serialized end-to-end so a slower-older one can't overwrite a faster-newer one.

### Known issues

- Per-speaker subscription failures aren't surfaced yet — the SDK swallows them, so the `SubscriptionError` variants exist but production never emits them (addressed in v0.5).
- `speaker_state` returns honest-partial state in the first ~1 s after discovery while the cache seeds.

Validated on real hardware (2-speaker LAN, Windows); evidence under [`docs/evidence/v0.4-release/`](docs/evidence/v0.4-release/README.md).

## [0.3.0] - 2026-05-20

v0.3 — Real ZoneGroupTopology grouping. Multi-room groups and coordinator election via direct `sonos_api` SOAP, with no `SonosSystem` dependency.

### Added

- **Topology-driven discovery.** `discover()` reads `ZoneGroupTopology` directly from a responding speaker and builds groups from topology members. Bonded satellites (surrounds, stereo pairs) are folded into their primary and no longer surface as standalone speakers — fixing the v0.1 bug by construction.
- **Group-coordinator addressing.** `speaker_state` reads volume/mute per-speaker and transport at the group coordinator. `Wire` signatures are unchanged from v0.2 — the addressing seam was designed for this swap.
- **Refresh = re-discover.** Caches are repopulated on every `discover()`; a `GroupId` that's gone after a regroup returns `WireError::NotFound`.
- Dropped the `sonos-sdk` umbrella crate — `oto-wire` now depends only on `sonos-api =0.5.2` (plus `quick-xml` for track metadata).

## [0.2.0] - 2026-05-18

v0.2 — Playback control + one-shot state read. Verifiable LAN-free via a stateful mock, and verified against real hardware on Windows.

### Added

- **Playback, volume, and state.** `play` / `pause` / `next` / `previous` (addressed by group), `set_volume` / `set_mute` (per speaker), and a one-shot `speaker_state` read — all via direct `sonos_api` SOAP. New playback/state DTOs and a `CommandError` enum on the FRB surface.
- `oto-mock` is now stateful: commands mutate an in-memory model that `speaker_state` reflects, proving command→state round-trips with zero LAN.
- Riverpod providers for state and playback commands, with headless tests proving each crosses the bridge.

### Changed

- **Commands are non-sync Dart `Future`s** — hardware proved every command is a blocking SOAP round-trip (discovery was already non-sync in v0.1).
- Removed the `greet` demo scaffolding.

Known v0.2 limitations: group-of-one only (real multi-room topology is v0.3); live event streams are v0.4; Android release discovery still needs a `WifiManager.MulticastLock` (added in v0.5).

## [0.1.0] - 2026-05-17

v0.1 — Foundation + LAN discovery. Identity-only discovery proven end-to-end through the Rust↔Dart bridge, verifiable without a LAN.

### Added

- `oto-core`: pure-Rust domain types (`Speaker`, `Group`, `Volume`, typed identifiers, identity projections) plus the `Wire` trait and `WireError`. No networking, async, or third-party deps.
- `oto-wire`: the production `Wire` — own multi-interface SSDP (works around `sonos-sdk`'s `0.0.0.0` bind that fails on multi-NIC hosts, [tatimblin/sonos-sdk#76](https://github.com/tatimblin/sonos-sdk/issues/76)) plus a device-description fetch.
- `oto-mock`: a deterministic in-memory `Wire`, so discovery is provable without real hardware.
- `oto-app` owns the process-global active `Wire` and routes the `discover` command; `oto_native` exposes the FRB `discover()` and identity DTOs.
- Flutter app scaffold with a Riverpod discovery provider wired to the bridge.
- Project infrastructure: the release process, this changelog, CI (generated-source freshness, lint, tests), an Android debug-build workflow, and the `AGENTS.md` contract.

Known v0.1 limitations: discovery is identity-only (bonded speakers appear standalone — fixed in v0.3); verified on Windows; Android release discovery needs a `WifiManager.MulticastLock` (added in v0.5).

[Unreleased]: https://github.com/Oszkar/oto/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Oszkar/oto/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Oszkar/oto/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Oszkar/oto/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Oszkar/oto/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Oszkar/oto/releases/tag/v0.1.0
[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
