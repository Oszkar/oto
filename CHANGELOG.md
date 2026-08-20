# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog][kac]; the project follows [Semantic Versioning][semver]. While pre-1.0 (`0.y.z`), the public surface and behavior may change between any releases.

## [Unreleased]

### Fixed

- Malformed track times reported by a speaker no longer produce a wrong or
  overflowing position; they are now discarded. A discovery run whose network
  poller fails is reported as a network error instead of as "no speakers
  found."
- The wide layout's pinned room/group selection survives resizing the window
  down to phone width and back.
- Dragging a per-room volume slider inside a group card can no longer land on a
  different room if the group's member order changes mid-drag.
- A saved window position on a monitor that is no longer attached, or a corrupt
  saved size, now falls back to a centered default window instead of opening
  off-screen or at zero size.
- The Now Playing progress bar renders in the accent color rather than the
  default grey.
- The teal and amber accents are slightly deeper in light mode so the group
  member-count badge meets the WCAG AA contrast minimum.
- Rapid commands across room, group, and playback controls now reach each
  speaker in user-intent order. A superseded failure no longer overwrites a
  newer optimistic value or rolls back past the last successful command.

## [0.6.4] - 2026-07-28

v0.6.4 - Mute and honest failure. The v0.6 closer: mute reaches every volume surface, a failed command rolls back and explains itself instead of silently reverting, and Home offers a way back when every room looks unreachable. Also closes out the pipeline lifecycle hardening surfaced by dogfooding the v0.6 UI series.

### Added

- **Mute controls.** Every volume surface now exposes the mute capability that
  was already present end-to-end: per-room mute on cards, rows, and room
  detail; group mute on group cards and Now Playing. Muted sliders dim, and the
  controls retain accessible names.
- **Honest command failures.** Failed optimistic commands now roll back and
  explain the failure in a non-modal SnackBar, distinguishing an unreachable
  speaker, a Sonos rejection, and a stale topology identifier.
- **Recovery when every room is unreachable.** Home keeps the cached household
  visible and offers an explicit network rescan instead of leaving the user
  with no route back to discovery.
- **Room options on wide layouts.** A solo room shown in the persistent Now
  Playing pane exposes the same grouping menu that room detail provides on a
  phone.

### Changed

- Unreachable rooms are labelled "Unreachable," not "Powered off." A failed
  network command does not reveal the device's power state.
- User-requested scans clear carried health errors; automatic topology
  refreshes preserve them until the relevant speaker actually recovers.
- Commands to the same target are serialized, preventing an older failed
  request from racing a newer successful one and leaving false unreachable
  state behind.
- Settings' "Default home layout" now sets only the startup default. The Home
  header's Cards/Stack toggle changes the current session and no longer
  overwrites that persisted default.

### Fixed

- Closed event-pipeline lifecycle races across wire replacement: receivers are
  paired atomically with their wire generation, stale consumers cannot drain
  current events, and old-wire events no longer reach the new Rust cache or
  Dart household.
- Event-pump teardown now explicitly shuts down the SDK event manager before
  stopping and joining oto's pump thread, breaking the SDK worker's self-owned
  reference cycle.
- Topology refresh has a bounded retry budget, does not mutate the installed
  wire before replacement succeeds, and releases the global slot before the
  replaced wire performs blocking teardown.
- Topology seed suppression is time-bounded, and stale group-event filtering
  self-heals if both fast refresh and full rediscovery fail.

## [0.6.3] - 2026-07-22

v0.6.3 - Responsive layouts. oto now fills the window it is given: a tablet gets a master-detail layout and a Windows desktop a three-pane one, so the controls stop being phone-shaped on a large screen. The final originally planned phase of the v0.6 UI.

### Added

- **Tablet and desktop layouts.** On a wider window the room grid keeps its place and a persistent Now Playing pane sits beside it, in place of the phone's floating strip. Desktop adds a slim navigation rail, for a three-pane layout. Picking a room or group shows it in the pane in place, with no full-screen jump.
- **Dialogs on wide.** Settings and the group editor open as centered dialogs over the layout on a wide window, rather than taking over the whole screen; on a phone they stay full-screen.
- **The window remembers its size.** On Windows, oto reopens at the size and position you left it (centered on first run).

### Changed

- On a wide window, tapping a room shows it in the Now Playing pane instead of opening the separate room screen - that screen stays the phone experience.

### Fixed

- **Keyboard focus and tap targets.** Cards and list rows are keyboard-focusable, have correctly sized touch targets, and no longer overlap adjacent controls (a room card's tap area no longer stole taps from its own volume slider).
- **Independent scrollbars.** Each scrollable pane on desktop gets its own scrollbar, and hovering shows the desktop pointing-hand cursor where appropriate.
- **Wide dialogs collapse cleanly on resize.** Settings and the group editor now fall back to the phone's full-screen presentation automatically if the window is resized narrow while they're open, instead of leaving a stray dialog behind.
- **Wide pane selection no longer dangles.** If the room or group currently shown in the Now Playing pane disappears (regroup, going offline), the pane falls back cleanly instead of holding a stale selection.

Validated on a Windows desktop across phone, tablet, and desktop widths; the phone layout is unchanged.

## [0.6.2] - 2026-07-01

v0.6.2 - Settings and honest states. A real Settings screen replaces the placeholder, and Home now presents explicit loading, empty, discovery-error, and cached-error states instead of assuming the happy path.

### Added

- **Settings.** New appearance controls, a read-only devices list, "about" information section.
- **Home states.** Added explicit loading, empty, discovery-error, and cached-error states, with offline room and device presentation kept inline.

### Fixed

- **Android builds no longer require WSL/Linux/macOS.** Dropped an unused `native-tls` TLS backend that three `sonos-sdk` dependencies pulled in by default (two never referenced it in source at all) - it forced  vendored, Perl-driven OpenSSL build on Android for HTTPS calls the app never makes. `just build-apk` now builds natively on Windows.

### Known issues

- **Settings' "Default home layout" mirrors the live Home toggle** rather than acting as an independent startup default - changing Home's Cards/Stack view updates what Settings shows, and vice versa. Splitting the persisted default from the current session's layout is deferred.

## [0.6.1] - 2026-06-20

v0.6.1 - Room management. The Now Playing progress bar (deferred from v0.6.0) arrives, and you can now group and ungroup rooms and open a focused per-room screen. The second slice of the phased v0.6 UI; settings and responsive layouts follow in v0.6.2-.3.

### Added

- **Now Playing progress bar.** A live position-and-duration bar that shows where you are in the track and ticks as it plays. Read-only - there is no seek (the backend exposes none).
- **Group rooms.** A group editor to pick which rooms play together: join rooms in, leave them out, or ungroup the whole set. Rooms already playing their own source are flagged before you interrupt them. Open it from any group card or from a room's detail screen.
- **Room detail.** Tap a room to open a focused view - what its group is playing with transport controls, its own volume, and a menu to group or ungroup it.

### Known issues

- Controls the backend can't drive yet (shuffle/repeat/seek, queue, EQ/sound) remain intentionally hidden rather than faked.
- Settings screen and responsive tablet/desktop layouts are still to come (v0.6.2-.3).

## [0.6.0] - 2026-06-11

v0.6.0 - The first real interface. Until now oto was a proven backend behind a test scaffold; this release ships the designed Flutter UI - Home and Now Playing - on the existing capability layers. Phased: room management, settings, and responsive layouts follow in v0.6.1-.3.

### Added

- **Home screen.** Your rooms and groups at a glance, in a Cards or Stack layout (toggle in the header). Each shows what's playing with album art, online/offline state, a master volume, and per-room levels inside a group. Play or pause any active source straight from an adaptive bottom strip.
- **Now Playing screen.** A full-screen view of a group's current track - art, title and artist, and transport controls.
- **Theming.** Light and dark themes with a user-selectable accent colour, on the bundled Geist typeface and the design-system tokens.
- **Persistent preferences.** Theme, accent, and default Home layout are remembered across launches.
- **Live, optimistic UI.** The interface follows the live event stream - volume, playback, track, and grouping changes made elsewhere (the Sonos app, another controller) show up without a refresh - and your own actions apply instantly, then reconcile.

### Known issues

- **Now Playing has no progress bar yet** - the track position/duration path lands in v0.6.1.
- Controls the backend can't drive yet (shuffle/repeat/seek, queue, EQ/sound) are intentionally not shown rather than faked; they arrive with their backend in later milestones.
- Room management (group editor, room detail) is v0.6.1; the settings screen and responsive tablet/desktop layouts are v0.6.2-.3.

## [0.5.1] - 2026-06-05

v0.5.1 - Group operations: form/break, group volume/mute, and a much faster regroup refresh. The last capability release before the v0.6 UI; all event additions ride the existing single change-event stream.

### Added

- **Group form/break.** Group and ungroup rooms from oto - join a speaker into another room's group, or split one out to play on its own. The view updates live afterward, the same way an app-side regroup does.
- **Group volume and mute.** Set a whole group's volume or mute (proportional across its rooms), and read the current group volume/mute live as it changes.

### Changed

- **Regrouping is now fast.** A regroup updates oto in ~tens of milliseconds via a SOAP-only refresh, instead of the ~3–5 s full re-discovery v0.5 used - resolving the v0.5 known issue early.

### Known issues

- Leaving the coordinator of a 3+-room group relies on Sonos's own coordinator re-election (oto issues the standard "become standalone" command and re-reads the result); this path wasn't exercised on the 2-zone dev LAN.

## [0.5.0] - 2026-06-03

v0.5 - Hardening before the v0.6 UI: live topology events, subscription-failure surfacing, Android release discovery, and speaker-model names. All event additions ride the single v0.4 `Stream<ChangeEventDto>` - no stream-surface redesign.

### Added

- **Topology change events.** Grouping or ungrouping speakers in the Sonos app now updates oto live: a regroup surfaces as a `TopologyChanged` event on the existing change-event stream, and the app re-discovers to pick up the new grouping. The controller is implemented and tested but dormant until the v0.6 UI watches it. The `Wire` trait grows additively with `subscribe_topology` + `refresh_topology`.
- **Subscription-failure surfacing.** `SubscriptionError` / `SubscriptionRecovered` (on the API since v0.4 but never emitted - the SDK at `=0.5.2` swallows subscription failures) now emit when a command to a speaker fails with a network error, and again when it recovers, so the UI can show a speaker as unreachable.
- **Android release discovery.** Discovery now works in release builds on Android by holding a `WifiManager.MulticastLock` around the SSDP window - without it Android silently drops the discovery multicast, so release builds found nothing.
- **Speaker model names.** `SpeakerIdentity.model` (empty since v0.3, because the topology XML carries no model) is repopulated - e.g. "Sonos Beam" - via a best-effort per-speaker `device_description.xml` fetch during discovery.

### Changed

- The Dart event-stream provider re-subscribes only on a _successful_ re-discovery, so a failed re-discover no longer tears the live stream down onto a dead receiver.

### Fixed

- **SSDP multicast egress on multi-NIC hosts** ([tatimblin/sonos-sdk#76](https://github.com/tatimblin/sonos-sdk/issues/76)): discovery now pins each socket's outgoing multicast interface, so the M-SEARCH leaves the right NIC instead of whatever the OS routing table picks. Hardware-validated non-regressive.
- Hardened the live event/topology path: a regroup-triggered re-discover loop, stale event routing after a regroup, a failed-rediscover event-stranding case, and several discovery/subscription races found in review.

### Known issues

- A speaker that goes silent _while idle_ isn't flagged until the next command to it fails (richer detection is a post-1.0 candidate).
- A regroup triggers a full ~3–5 s re-discover; the fast SOAP-only refresh lands in v0.6.
- **Group form/break** commands are deferred to v0.5.1.

### Housekeeping

- CI compile-guards the hardware-gated live tests so they can't bit-rot (never runs them - the LAN is untouched). Dependabot tuned for the pinned `sonos-api` / `quick-xml` / `socket2` deps.

Validated on real hardware: a 2-speaker LAN (Sonos Beam + Sonos One) and a real Android device. Evidence under [`docs/evidence/v0.5-release/`](docs/evidence/v0.5-release/README.md).

## [0.4.0] - 2026-05-26

v0.4 - Live property events. Reactive state via GENA: a Rust → Dart event stream with no oto-owned polling. Property events only - volume, mute, transport state, current track; topology change events and group form/break stay v0.5.

### Added

- **Live event stream.** A new FRB `subscribe_change_events` surface delivers a single `Stream<ChangeEventDto>` (`Volume`, `Mute`, `Playback`, `Track`, plus the forward-looking `SubscriptionError` / `SubscriptionRecovered`). One multiplexed event-pump thread per wire in `oto-wire` wraps the upstream reactive SDK stack (all pinned `=0.5.2`); volume/mute are per-speaker, transport/track per group coordinator.
- **Event-fed state cache.** `oto-app` now holds an event-fed `StateManager` cache (per-speaker volume/mute, per-group playback/track), so `speaker_state` reads the cache instead of issuing a SOAP call per read. State lives in Rust and survives Flutter hot reload.
- **`native/examples/event-tail.rs`** - a dogfood binary that subscribes to the stream and prints changes (not a user-facing CLI).
- **Hardware-gated live tests** (`--features live-tests`): seed events, operator volume change, per-group play/pause, a double-discover regression, and a ~28 min renewal-cycle observation.

### Changed

- `speaker_state` is now a cache read, not a SOAP read - implementation only; the public signature is unchanged.
- Discovery auto-subscribes the new wire's speakers, so a Dart consumer sees seed events without driving subscription itself.
- "Watch-after-fetch event suppression" moved from open constraint to resolved (a bare `.watch()` is its own seed probe).

### Fixed

- **SSDP starvation under many quiet sockets:** the discovery wait is now collective (multiplexed), so a dozen idle adapters (VPN / Hyper-V / WSL / Docker on Windows) can't consume the whole bounded window before a real responder is reached.
- **All-NIC-fail diagnostic:** when every interface fails to bind/send, discovery returns a network error with the underlying cause instead of falsely reporting an empty LAN.
- **Concurrent discovery race:** overlapping discoveries are serialized end-to-end so a slower-older one can't overwrite a faster-newer one.

### Known issues

- Per-speaker subscription failures aren't surfaced yet - the SDK swallows them, so the `SubscriptionError` variants exist but production never emits them (addressed in v0.5).
- `speaker_state` returns honest-partial state in the first ~1 s after discovery while the cache seeds.

Validated on real hardware (2-speaker LAN, Windows); evidence under [`docs/evidence/v0.4-release/`](docs/evidence/v0.4-release/README.md).

## [0.3.0] - 2026-05-20

v0.3 - Real ZoneGroupTopology grouping. Multi-room groups and coordinator election via direct `sonos_api` SOAP, with no `SonosSystem` dependency.

### Added

- **Topology-driven discovery.** `discover()` reads `ZoneGroupTopology` directly from a responding speaker and builds groups from topology members. Bonded satellites (surrounds, stereo pairs) are folded into their primary and no longer surface as standalone speakers - fixing the v0.1 bug by construction.
- **Group-coordinator addressing.** `speaker_state` reads volume/mute per-speaker and transport at the group coordinator. `Wire` signatures are unchanged from v0.2 - the addressing seam was designed for this swap.
- **Refresh = re-discover.** Caches are repopulated on every `discover()`; a `GroupId` that's gone after a regroup returns `WireError::NotFound`.
- Dropped the `sonos-sdk` umbrella crate - `oto-wire` now depends only on `sonos-api =0.5.2` (plus `quick-xml` for track metadata).

## [0.2.0] - 2026-05-18

v0.2 - Playback control + one-shot state read. Verifiable LAN-free via a stateful mock, and verified against real hardware on Windows.

### Added

- **Playback, volume, and state.** `play` / `pause` / `next` / `previous` (addressed by group), `set_volume` / `set_mute` (per speaker), and a one-shot `speaker_state` read - all via direct `sonos_api` SOAP. New playback/state DTOs and a `CommandError` enum on the FRB surface.
- `oto-mock` is now stateful: commands mutate an in-memory model that `speaker_state` reflects, proving command→state round-trips with zero LAN.
- Riverpod providers for state and playback commands, with headless tests proving each crosses the bridge.

### Changed

- **Commands are non-sync Dart `Future`s** - hardware proved every command is a blocking SOAP round-trip (discovery was already non-sync in v0.1).
- Removed the `greet` demo scaffolding.

Known v0.2 limitations: group-of-one only (real multi-room topology is v0.3); live event streams are v0.4; Android release discovery still needs a `WifiManager.MulticastLock` (added in v0.5).

## [0.1.0] - 2026-05-17

v0.1 - Foundation + LAN discovery. Identity-only discovery proven end-to-end through the Rust↔Dart bridge, verifiable without a LAN.

### Added

- `oto-core`: pure-Rust domain types (`Speaker`, `Group`, `Volume`, typed identifiers, identity projections) plus the `Wire` trait and `WireError`. No networking, async, or third-party deps.
- `oto-wire`: the production `Wire` - own multi-interface SSDP (works around `sonos-sdk`'s `0.0.0.0` bind that fails on multi-NIC hosts, [tatimblin/sonos-sdk#76](https://github.com/tatimblin/sonos-sdk/issues/76)) plus a device-description fetch.
- `oto-mock`: a deterministic in-memory `Wire`, so discovery is provable without real hardware.
- `oto-app` owns the process-global active `Wire` and routes the `discover` command; `oto_native` exposes the FRB `discover()` and identity DTOs.
- Flutter app scaffold with a Riverpod discovery provider wired to the bridge.
- Project infrastructure: the release process, this changelog, CI (generated-source freshness, lint, tests), an Android debug-build workflow, and the `AGENTS.md` contract.

Known v0.1 limitations: discovery is identity-only (bonded speakers appear standalone - fixed in v0.3); verified on Windows; Android release discovery needs a `WifiManager.MulticastLock` (added in v0.5).

[Unreleased]: https://github.com/Oszkar/oto/compare/v0.6.4...HEAD
[0.6.4]: https://github.com/Oszkar/oto/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/Oszkar/oto/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/Oszkar/oto/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/Oszkar/oto/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/Oszkar/oto/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/Oszkar/oto/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/Oszkar/oto/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Oszkar/oto/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Oszkar/oto/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Oszkar/oto/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Oszkar/oto/releases/tag/v0.1.0
[kac]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
