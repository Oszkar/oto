# Roadmap

Milestone status and forward scope. [Architecture](ARCHITECTURE.md) describes the current system; [Sonos notes](sonos-notes.md) preserves protocol constraints; [Changelog](../CHANGELOG.md) owns release history. The status below describes releases, not every change already on `main`.

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

## v0.7 - Hardening + polish

- Harden SSDP response validation: status `200`, expected `ST`, `LOCATION` host matching the responder, and a candidate-count cap. See [known constraints](ARCHITECTURE.md#known-constraints) and the TODO in `native/crates/wire/src/ssdp.rs`.
- Review cleanup TODOs, including stale source comments and the debug FRB mock-injection seam. The Windows integration gate currently depends on that seam; removing it needs equivalent test coverage and approval for the bridge change.
- Replace SOAP error-message matching if upstream exposes a structured error that distinguishes rejection from unreachability.
- Fix issues found while using the app and polish the existing UI.

## v1.0 - Stable

Externally tested and packaged for signed Android and Windows distribution. After v1.0, the intended scope is maintenance: bug fixes and security updates, without new milestone-scale features.

## Project-bound open items

### Speaker health

Command failures reveal network unreachability, not power state. The UI uses "Unreachable" and offers rescanning. A speaker that goes silent while idle may remain apparently healthy until a command fails.

Revisit only if real use shows that command-time health is insufficient. Possible post-1.0 fixes are SDK subscription-failure reporting, a tracing adapter (brittle if tied to log strings), or a bounded heartbeat/last-NOTIFY check (additional traffic and false-positive risk). None can infer power state from silence alone.

### Upstream SSDP safeguards

oto retains explicit multicast egress selection and an absolute receive deadline. Offering those safeguards upstream and validating a non-default LAN interface remain useful follow-ups. Replace oto's implementation only after equivalent behavior and hardware validation; see [SSDP discovery](sonos-notes.md#ssdp-discovery).

### IPv6 SSDP coverage

Discovery currently enumerates IPv4 interfaces only. Revisit IPv6 when a real IPv6-only or broken-IPv4 setup needs it, or when upstream discovery work requires a dual-stack design.
