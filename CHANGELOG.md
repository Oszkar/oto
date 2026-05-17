# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog][kac]; the project follows
[Semantic Versioning][semver]. While pre-1.0 (`0.y.z`), the public surface
and behavior may change between any releases.

## [Unreleased]

## [0.1.0] - 2026-05-17

### Added

v0.1 — Foundation + LAN discovery. Identity-only discovery proven
end-to-end through the Rust↔Dart bridge, verifiable without a LAN.

- `oto-core`: pure-Rust domain types — `Speaker`, `Group`,
  `TransportState`, `Track`, `Volume`, typed identifiers — plus the v0.1
  identity projections (`SpeakerIdentity`, `GroupIdentity`,
  `DiscoverySnapshot`) and the `Wire` trait + `WireError`. No
  networking, async, or third-party deps.
- `oto-wire`: production `Wire` — own multi-interface SSDP (works around
  `sonos-sdk`'s `0.0.0.0` bind that fails on multi-NIC hosts, upstream
  `tatimblin/sonos-sdk#76`), `ureq` device-description fetch
  (HTTP/1.1-chunked-safe), and the `sonos_discovery::DeviceDescription`
  adapter. `tatimblin/sonos-sdk` pinned at `=0.5.2` (`test-support`).
- `oto-mock`: deterministic in-memory `Wire`, so discovery is provable
  without real hardware.
- `oto-app`: owns runtime state (the process-global active `Wire`,
  replace-on-success) and routes the `discover` command.
- `oto_native`: FRB `discover()` deferred-warm-up command + identity
  DTOs (`Topology`, `DiscoveredSpeaker`, `DiscoveredGroup`,
  `DiscoveryError`); representational map covered LAN-free by the
  `native/tests/` e2e.
- Flutter app: Riverpod `discovery` `FutureProvider` wired to the FRB
  binding; app scaffold (`ProviderScope`, demo `greet` surface — removed
  in v0.2).
- `docs/ARCHITECTURE.md` — system design (layers, state ownership,
  command/event flow, open questions) — the discovery spike findings,
  and the discover-command design + implementation plans.
- Project infrastructure: versioning/release process (`RELEASING.md`),
  this changelog, CI (generated-source freshness, lint, tests),
  Android debug-build workflow, and the `AGENTS.md` operational
  contract.

Known v0.1 limitations: discovery is identity-only (bonded
surrounds/stereo pairs appear as standalone players — real
ZoneGroupTopology is v0.3); verified on Windows — Android **release**
discovery needs a `WifiManager.MulticastLock` (`TODO(v0.4)`).

[Unreleased]: https://github.com/Oszkar/oto/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Oszkar/oto/releases/tag/v0.1.0
[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
