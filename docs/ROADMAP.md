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
| v0.7.0 | planned | **Hardening + test distribution** - discovery and event recovery, polish, persistent Android and Windows downloads |
| v1.0   | future | Stable - externally tested, packaged |

## v0.7 - Hardening + test distribution

Deliver in this order, keeping the existing core types, `Wire` trait, and FRB surface:

1. **Bound and validate discovery.** Require status `200`, the expected `ST`, and a `LOCATION` host matching the responder IP. Cap distinct candidate hosts and follow-up SOAP attempts. Check the receive deadline inside socket draining as well as around polling so continuous traffic cannot extend discovery indefinitely. Preserve explicit multicast egress and multi-interface discovery. Test malformed responses, duplicates, candidate limits, sustained traffic, and quiet-interface fairness; revalidate on hardware. See [known constraints](ARCHITECTURE.md#known-constraints).
2. **Make event-stream failure recoverable.** Close [the silent Dart stream-error gap](https://github.com/Oszkar/oto/issues/148): preserve cached rooms, indicate that live updates stopped, and offer an explicit rescan through existing discovery orchestration. Do not blindly retry subscription on the same wire, whose receiver is single-use. Any automatic recovery must have a bounded retry budget and preserve wire-generation protections.
3. **Resolve targeted cleanup.** Keep the debug FRB mock-injection seam required by the Windows integration gate and correct its stale removal TODO. Verify SOAP rejection/unreachability mapping against pinned SDK 0.8; retain string matching if no suitable structured discriminator exists. Reassess XML advisory exceptions alongside SSDP hardening: matching the sender does not authenticate a LAN peer. Defer exact multi-monitor bounds unless dogfooding establishes a need for the additional dependency.
4. **Provide persistent test downloads.** Attach a release-mode Android APK signed with a stable, dedicated test-distribution key and an unsigned Windows x64 portable release ZIP to a draft GitHub Release. Include versioned filenames, SHA-256 checksums, source commit/build provenance, and installation instructions. Android test distribution uses a separate application identity from future Play distribution. See the [planned release process](../RELEASING.md#planned-v070-test-distribution).
5. **Dogfood and accept the final candidate.** Exercise active playback, rapid volume/mute commands, regrouping, failed discovery, event recovery, resume after sleep, and desktop resizing on Windows and Android. Include real multi-NIC discovery and subscription renewal. Fix reproducible issues in existing functionality.

### Release acceptance

- `just check`, `just test`, Windows FRB integration, and both platform release builds pass for the final tagged candidate. Record the tested commit and workflow runs.
- Hardware validation covers the changed SSDP behavior and active playback; mock integration alone is insufficient.
- Install and smoke-test the exact APK and complete Windows ZIP intended for publication. Confirm Android upgrade continuity between builds signed with the test key, and Windows launch on a clean machine without development tooling.
- Publish the already-tested draft assets without rebuilding. GitHub Release assets provide persistence beyond Actions artifact retention.
- Update versions, changelog, installation instructions, and release status. The expected version is `0.7.0+12` if no intervening release increments the build number.

### Outside this milestone

Google Play publishing, production Android signing, Windows installers/code signing, new playback features, and the coordinated [Flutter/Riverpod/FRB toolchain upgrade](https://github.com/Oszkar/oto/issues/168). Google Play is a future distribution preference; an approved Play account is not a prerequisite for v0.7.0 test downloads.

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
