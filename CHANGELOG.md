# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog][kac]; the project follows [Semantic Versioning][semver]. While pre-1.0 (`0.y.z`), the public surface and behavior may change between any releases.

## [Unreleased]

### Fixed

Post-v0.3 review batch (second tranche). Discovery robustness + doc drift cleanup.

- **SSDP starvation under many quiet sockets:** `collect_until` now multiplexes on `mio::Poll`, so the Phase-2 wait is collective. The previous per-socket 250 ms read timeout could let 12+ quiet adapters (the multi-NIC Windows worst case: VPN/Hyper-V/WSL/Docker vEthernet enumerated ahead of the LAN) consume the full 3 s bounded window before reaching a responder. Adds a regression test with 13 quiet sockets ahead of the responder. `mio` was already a transitive dep; promoted to a direct one.
- **All-NIC-fail diagnostic:** when every usable IPv4 interface fails bind/send/register, `discover_locations` now returns `WireError::Network` with the last underlying cause instead of `Ok(vec![])`. The old path mapped that to `NoDevicesFound`, which falsely implied an empty LAN when the real cause was a local socket-stack failure.
- **Concurrent `discover_with` race:** added a `DISCOVER_LOCK` in `oto-app` that serialises overlapping discoveries end-to-end (make + `wire.discover()` + slot replacement). The slot lock is unchanged; playback commands are still independent of discovery duration. Prevents a slower-but-older `discover_with` from last-writer-wins overwriting a faster newer one.

### Changed

- `app/integration_test/simple_test.dart`: retargeted from the removed v0.1 `greet` scaffold onto the current placeholder `HomePage`. New `just test-integration` recipe (mirrored in `Makefile`) for the manual bridge smoke — not gated by CI yet (Flutter `integration_test` needs a display target).
- README's `flutter_rust_bridge_codegen` install command pinned to `2.12.0` (matches CI / `native/Cargo.toml` / `CONTRIBUTING.md`'s alignment mandate).
- Stale `v0.4` UI references swept to `v0.5` (UI = v0.5, events = v0.4) across `app/lib/main.dart`, `app/lib/src/state/playback.dart`, `app/test/playback_provider_test.dart`. `api.rs::discover` doc updated — the snapshot is no longer "identity-only" since v0.3 added groups + coordinators. Generated source refreshed via `just gen`.

## [0.3.0] - 2026-05-20

### Added

v0.3 — Real ZoneGroupTopology grouping. Multi-room groups and coordinator election — delivered via direct `sonos_api` SOAP with no `SonosSystem` dependency.

- **Grouping — D1 (speakers from topology):** `discover()` reads `ZoneGroupTopology` directly from a responding speaker; speakers are built from topology members (`model: None` — ZoneGroupTopology carries no model; `TODO(v0.5)` to repopulate). Bonded satellites (`Invisible="1"` child nodes) are folded into their primary and never surfaced as standalone speakers (Open Q4 resolved).
- **Grouping — D2 (transport at coordinator, `Wire` signature unchanged):** `speaker_state` reads volume/mute per-speaker and transport at the group coordinator via the `speaker_to_coordinator` cache. `Wire` signatures are identical to v0.2 — the addressing seam was designed for this swap.
- **Grouping — D3 (refresh = re-discover; stale `GroupId` → `NotFound`):** `oto-wire` populates its group→coordinator/speaker→coordinator caches on every `discover()` call; there is no incremental refresh. A `GroupId` that was valid before a re-discover but is absent from the new topology returns `WireError::NotFound` (`TODO(v0.5)` miss-retry).
- **Open Q1 resolved (v0.3):** real ZoneGroupTopology via direct-SOAP `GetZoneGroupState`; `SonosSystem` / `from_discovered_devices` not needed and never called.
- **Open Q4 resolved (v0.3):** bonded satellites folded into the primary speaker; not surfaced as standalone players (was the documented v0.1/v0.2 limitation).
- **Open Q5 closed (v0.3):** `sonos-sdk` umbrella crate (`test-support` feature, `sonos_discovery::DeviceDescription`) removed; `oto-wire` now depends only on `sonos-api =0.5.2` (already a direct dep for v0.2 playback). `quick-xml` (=0.31.0) retained for DIDL-Lite parsing.

## [0.2.0] - 2026-05-18

### Added

v0.2 — Playback control + one-shot state read. Proven end-to-end through the Rust↔Dart bridge, verifiable LAN-free (stateful mock) and verified against real hardware on Windows.

- `oto-core`: `SpeakerState { volume: Option<Volume>, muted: Option<bool>, transport: Option<TransportState> }` — the v0.2 state DTO (`Option<T>` fields: honest partial failure across ~4 SOAP reads, matches SDK `get()` and the v0.3 cold cache). `WireError::NotFound(String)` variant — unknown speaker/group id or pre-discovery call (precondition error, distinct from transport failures). `Wire` trait grown to 8 methods: discovery (unchanged)
  + 4 playback commands (`play/pause/next/previous` addressed by `GroupId`)
  + 2 per-speaker controls (`set_volume`, `set_mute`) + one-shot state read (`speaker_state`).
- `oto-wire`: direct `sonos_api` (=0.5.2) SOAP control and state reads — no `SonosSystem`, no topology. Interior-mutable id→addr / group→coordinator cache populated by `discover()`; commands before discovery return `WireError::NotFound`. `quick-xml` (=0.31.0) DIDL-Lite parser for track metadata (`parse_track_didl`). The `sonos-sdk` `test-support` umbrella is retained for the `sonos_discovery` discovery path (now confirmed load-bearing, not transitional).
- `oto-mock`: stateful `MockWire` — in-memory per-speaker model (commands mutate it, `speaker_state` reflects mutations); proves command→state round-trips with zero LAN. `discover()` seeds the model from the fixture.
- `oto-app`: command-routing fns (`play/pause/next/previous/set_volume/ set_mute/speaker_state`) delegating to the held `Wire`; `Mutex` held across the SOAP call (deliberate serialisation for LAN politeness).
- `oto_native`: 7 non-sync FRB fns (Dart `Future`) for the playback/state surface; `SpeakerStateDto`, `TransportDto`, `PlaybackStateDto`, `TrackDto` DTOs; `CommandError { NotFound, Network, Sonos }` enum. Representational map (`map.rs`) extended with `to_command_error` and `to_speaker_state_dto`.
- Flutter app: Riverpod `speakerStateProvider` (`FutureProvider`) and `playbackCommandsProvider` wired to the FRB bindings; headless Flutter tests proving each provider crosses the bridge.
- `docs/ARCHITECTURE.md`: non-sync command flow (v0.2 delta from v0.1's sync model); group-of-one addressing + v0.3 seam; concise state-read ADR note (A chosen, revisit v0.3); Crates table + Open Q5 updated (direct `sonos-api`); `native/Cargo.toml` and `native/deny.toml` updated; `TODO(v0.2)` markers swept.
- New `sonos-api = "=0.5.2"` and `quick-xml = "=0.31.0"` workspace deps (promoted from transitive to direct in `oto-wire`).

### Changed

- **Commands are non-sync Dart `Future`s** — v0.2's deliberate delta from the v0.1 architecture: hardware proved every command is a blocking SOAP round-trip. `discover()` was already non-sync; all playback commands are the same. There are no synchronous FRB commands in the v0.2 surface.
- `WireError::Network` and `WireError::Backend` `Display` strings generalised (no longer "discovery …" prefix — these variants now occur on commands and state reads too).
- `greet` demo removed: `api.rs` `greet` fn, `oto_core::greeting`, `app/lib/main.dart` greeting wiring, `app/lib/src/state/greeting.dart` (+ `.g.dart`), and the original smoke test scaffold.

Known v0.2 limitations: group-of-one only — real multi-room ZoneGroupTopology (coordinator election, topology-change events, bonded speakers) is v0.3; live event streams (reactive state without polling) are v0.3; Android **release** discovery still needs a `WifiManager.MulticastLock` (`TODO(v0.4)`).

## [0.1.0] - 2026-05-17

### Added

v0.1 — Foundation + LAN discovery. Identity-only discovery proven end-to-end through the Rust↔Dart bridge, verifiable without a LAN.

- `oto-core`: pure-Rust domain types — `Speaker`, `Group`, `TransportState`, `Track`, `Volume`, typed identifiers — plus the v0.1 identity projections (`SpeakerIdentity`, `GroupIdentity`, `DiscoverySnapshot`) and the `Wire` trait + `WireError`. No networking, async, or third-party deps.
- `oto-wire`: production `Wire` — own multi-interface SSDP (works around `sonos-sdk`'s `0.0.0.0` bind that fails on multi-NIC hosts, upstream `tatimblin/sonos-sdk#76`), `ureq` device-description fetch (HTTP/1.1-chunked-safe), and the `sonos_discovery::DeviceDescription` adapter. `tatimblin/sonos-sdk` pinned at `=0.5.2` (`test-support`).
- `oto-mock`: deterministic in-memory `Wire`, so discovery is provable without real hardware.
- `oto-app`: owns runtime state (the process-global active `Wire`, replace-on-success) and routes the `discover` command.
- `oto_native`: FRB `discover()` deferred-warm-up command + identity DTOs (`Topology`, `DiscoveredSpeaker`, `DiscoveredGroup`, `DiscoveryError`); representational map covered LAN-free by the `native/tests/` e2e.
- Flutter app: Riverpod `discovery` `FutureProvider` wired to the FRB binding; app scaffold (`ProviderScope`, demo `greet` surface — removed in v0.2).
- `docs/ARCHITECTURE.md` — system design (layers, state ownership, command/event flow, open questions) — the discovery spike findings, and the discover-command design + implementation plans.
- Project infrastructure: versioning/release process (`RELEASING.md`), this changelog, CI (generated-source freshness, lint, tests), Android debug-build workflow, and the `AGENTS.md` operational contract.

Known v0.1 limitations: discovery is identity-only (bonded surrounds/stereo pairs appear as standalone players — real ZoneGroupTopology is v0.3); verified on Windows — Android **release** discovery needs a `WifiManager.MulticastLock` (`TODO(v0.4)`).

[Unreleased]: https://github.com/Oszkar/oto/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Oszkar/oto/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Oszkar/oto/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Oszkar/oto/releases/tag/v0.1.0
[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
