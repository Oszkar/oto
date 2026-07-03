/// Fixture data + provider test-doubles for the showcase (`main.dart`).
///
/// Everything here is deterministic and backend-free: hand-authored
/// [Household]s and notifier/API subclasses that seed the real providers with
/// fixtures so screens render exactly as they would against a live system -
/// with **zero Rust FFI** (see the override set in `showcase_app.dart`).
///
/// This lives under `lib/` (not `test/`) because the showcase is a runnable
/// `flutter run -t lib/showcase/main.dart` target, but it is dev-only tooling:
/// nothing in the shipped app imports it.
library;

import 'package:flutter/material.dart' show ThemeMode;

import '../src/rust/api.dart' as rust_api;
import '../src/state/commands.dart';
import '../src/state/discovery.dart';
import '../src/state/household.dart';
import '../src/state/model/group_state.dart';
import '../src/state/model/household.dart';
import '../src/state/model/room_state.dart';
import '../src/state/model/track.dart';
import '../src/state/now_playing.dart';
import '../src/state/prefs.dart';
import '../src/theme/accent.dart';

// -----------------------------------------------------------------------------
// Households
// -----------------------------------------------------------------------------

const _redbone = Track(
  title: 'Redbone',
  artist: 'Childish Gambino',
  album: 'Awaken, My Love!',
  duration: Duration(minutes: 5, seconds: 27),
  uri: 'x-sonos-http:redbone',
);

const _nightcall = Track(
  title: 'Nightcall',
  artist: 'Kavinsky',
  album: 'OutRun',
  duration: Duration(minutes: 4, seconds: 18),
  uri: 'x-sonos-http:nightcall',
);

/// A rich, representative household: one multi-room group playing, a couple of
/// solo rooms (one stopped, one paused-with-track), and one offline room. It
/// exercises the group card, solo cards, the bottom strip (two active sources),
/// and the offline presentation in a single fixture.
const demoHousehold = Household(
  rooms: {
    'RINCON_LR': RoomState(
      id: 'RINCON_LR',
      name: 'Living Room',
      model: 'One SL',
      kind: RoomKind.speaker,
      volume: 28,
      online: true,
      groupId: 'g_lr',
    ),
    'RINCON_KI': RoomState(
      id: 'RINCON_KI',
      name: 'Kitchen',
      model: 'One',
      kind: RoomKind.speaker,
      volume: 35,
      online: true,
      groupId: 'g_lr',
    ),
    'RINCON_OF': RoomState(
      id: 'RINCON_OF',
      name: 'Office',
      model: 'Move 2',
      kind: RoomKind.speaker,
      volume: 20,
      online: true,
      groupId: 'g_of',
    ),
    'RINCON_BR': RoomState(
      id: 'RINCON_BR',
      name: 'Bedroom',
      model: 'Beam',
      kind: RoomKind.soundbar,
      volume: 15,
      online: true,
      groupId: 'g_br',
    ),
    'RINCON_PA': RoomState(
      id: 'RINCON_PA',
      name: 'Patio',
      model: 'Roam',
      kind: RoomKind.speaker,
      volume: 40,
      online: false,
      groupId: 'g_pa',
    ),
  },
  groups: {
    'g_lr': GroupState(
      id: 'g_lr',
      coordinatorId: 'RINCON_LR',
      memberIds: ['RINCON_LR', 'RINCON_KI'],
      transport: PlaybackState.playing,
      track: _redbone,
      groupVolume: 30,
    ),
    'g_of': GroupState(
      id: 'g_of',
      coordinatorId: 'RINCON_OF',
      memberIds: ['RINCON_OF'],
      transport: PlaybackState.stopped,
    ),
    'g_br': GroupState(
      id: 'g_br',
      coordinatorId: 'RINCON_BR',
      memberIds: ['RINCON_BR'],
      transport: PlaybackState.paused,
      track: _nightcall,
      groupVolume: 15,
    ),
    'g_pa': GroupState(
      id: 'g_pa',
      coordinatorId: 'RINCON_PA',
      memberIds: ['RINCON_PA'],
      transport: PlaybackState.stopped,
    ),
  },
);

/// A sample discovery failure, for the error/cached-error home states. A
/// Dart-side FRB value - constructing it does not touch Rust.
final sampleDiscoveryError = rust_api.DiscoveryError.noDevicesFound();

// -----------------------------------------------------------------------------
// Provider test-doubles
// -----------------------------------------------------------------------------

/// Seeds [householdProvider] with a fixed [Household] and skips the real
/// build() (which watches discovery + the event stream). The inherited
/// optimistic setters still work, so command controllers mutate this in place -
/// which is what keeps the board interactive (a volume drag sticks).
class FixtureHousehold extends HouseholdNotifier {
  FixtureHousehold(this._seed);
  final Household _seed;
  @override
  Household build() => _seed;
}

/// Inert [Discovery]: `build()` and `rediscover()` resolve to a fixed topology
/// with no SSDP/FFI. The home states are forced via a `homeViewStateProvider`
/// override, so this only needs to keep the "Scan network" button harmless.
class InertDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async =>
      const rust_api.Topology(speakers: [], groups: []);
}

/// A [CommandApi] whose every method is a no-op success. Command controllers
/// run their optimistic update and then "succeed" against this, so the change
/// stays on screen (no rollback, no FFI).
class InertCommandApi extends CommandApi {
  const InertCommandApi();
  @override
  Future<void> play(String groupId) async {}
  @override
  Future<void> pause(String groupId) async {}
  @override
  Future<void> next(String groupId) async {}
  @override
  Future<void> previous(String groupId) async {}
  @override
  Future<void> setVolume(String speakerId, int v) async {}
  @override
  Future<void> setMute(String speakerId, bool m) async {}
  @override
  Future<void> joinGroup(String speakerId, String coordinatorId) async {}
  @override
  Future<void> leaveGroup(String speakerId) async {}
  @override
  Future<void> setGroupVolume(String groupId, int v) async {}
  @override
  Future<void> setGroupMute(String groupId, bool m) async {}
}

/// Seeds [settingsProvider] from the board's current toggles, with setters that
/// update state only (no `SharedPreferences`, so `prefsRepositoryProvider` is
/// never read and can't throw). The preview's `MaterialApp` reads this for its
/// theme, so the Settings screen's own toggles also drive the preview live.
class SeededSettings extends SettingsNotifier {
  SeededSettings(this._seed);
  final ({ThemeMode mode, Accent accent, HomeLayout layout}) _seed;

  @override
  ({ThemeMode mode, Accent accent, HomeLayout layout}) build() => _seed;

  @override
  Future<void> setThemeMode(ThemeMode m) async =>
      state = (mode: m, accent: state.accent, layout: state.layout);

  @override
  Future<void> setAccent(Accent a) async =>
      state = (mode: state.mode, accent: a, layout: state.layout);

  @override
  Future<void> setHomeLayout(HomeLayout l) async =>
      state = (mode: state.mode, accent: state.accent, layout: l);
}

/// A [PositionApi] that returns a fixed position without the `track_position`
/// SOAP read. Installed globally so a `NowPlayingScreen` reached by *navigation*
/// (e.g. tapping a Home bottom-strip source) - where there is no entry-specific
/// `nowPlayingPositionProvider` override - still never touches Rust.
class InertPositionApi extends PositionApi {
  const InertPositionApi();
  @override
  Future<rust_api.TrackPositionDto> trackPosition(String groupId) async =>
      rust_api.TrackPositionDto(
        positionSecs: BigInt.from(74),
        durationSecs: BigInt.from(327),
      );
}

/// Build a fixed [NowPlayingProgress] for the Now Playing preview, bypassing the
/// SOAP position read and its ~500 ms ticker.
NowPlayingProgress progress(Duration position, Duration duration) =>
    NowPlayingProgress(position, duration);
