# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog][kac]; the project follows
[Semantic Versioning][semver]. While pre-1.0 (`0.y.z`), the public surface
and behavior may change between any releases.

## [Unreleased]

### Added

- `oto-core`: pure-Rust domain types — `Speaker`, `Group`,
  `TransportState`, `Track`, `Volume`, and typed identifiers.
- `oto-wire`: skeleton crate; `tatimblin/sonos-sdk` pinned at `=0.5.2`.
- `docs/ARCHITECTURE.md` — system design (layers, state ownership,
  command/event flow) — and the discovery spike findings.

[Unreleased]: https://github.com/Oszkar/oto/commits/main
[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
