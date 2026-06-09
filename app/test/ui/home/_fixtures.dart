// Shared fixtures + spies for the Home leaf-widget tests.
//
// These widgets bind to `householdProvider` (seeded with a fixed `Household`
// via a fixture notifier) and `playbackControllerProvider` (a spy capturing
// command calls). The spy lets the tests assert that tapping play/pause or
// dragging the slider routes through the controller, without touching Rust.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';

/// A [HouseholdNotifier] whose `build()` returns a fixed fixture, bypassing
/// discovery/event wiring entirely.
class FixtureHousehold extends HouseholdNotifier {
  FixtureHousehold(this._fixture);
  final Household _fixture;
  @override
  Household build() => _fixture;
}

/// A [PlaybackController] that records every command instead of hitting Rust.
class SpyPlayback extends PlaybackController {
  SpyPlayback(Ref ref) : super(ref, const CommandApi());

  final calls = <String>[];

  @override
  Future<void> togglePlay(String groupId, PlaybackState current) async {
    calls.add('togglePlay($groupId,${current.name})');
  }

  @override
  void setVolume(String speakerId, int v) {
    calls.add('setVolume($speakerId,$v)');
  }

  @override
  void setVolumeEnd(String speakerId, int v) {
    calls.add('setVolumeEnd($speakerId,$v)');
  }
}

/// A playing solo room `OF` (Office) — its group `G_OF` has a track + playing
/// transport, so `hasActiveStream` is true.
Household playingHousehold() {
  return const Household(
    rooms: {
      'OF': RoomState(
        id: 'OF',
        name: 'Office',
        model: 'Move 2',
        kind: RoomKind.speaker,
        volume: 55,
        online: true,
        groupId: 'G_OF',
      ),
    },
    groups: {
      'G_OF': GroupState(
        id: 'G_OF',
        coordinatorId: 'OF',
        memberIds: ['OF'],
        transport: PlaybackState.playing,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
      ),
    },
  );
}

/// An idle solo room `BR` (Bedroom) — its group `G_BR` has no track and a
/// stopped transport, so `hasActiveStream` is false.
Household idleHousehold() {
  return const Household(
    rooms: {
      'BR': RoomState(
        id: 'BR',
        name: 'Bedroom',
        model: 'Era 100',
        kind: RoomKind.speaker,
        volume: 15,
        online: true,
        groupId: 'G_BR',
      ),
    },
    groups: {
      'G_BR': GroupState(
        id: 'G_BR',
        coordinatorId: 'BR',
        memberIds: ['BR'],
        transport: PlaybackState.stopped,
      ),
    },
  );
}

/// A powered-off (offline) solo room `PT` (Patio).
Household offlineHousehold() {
  return const Household(
    rooms: {
      'PT': RoomState(
        id: 'PT',
        name: 'Patio',
        model: 'Roam',
        kind: RoomKind.speaker,
        volume: 0,
        online: false,
        groupId: 'G_PT',
      ),
    },
    groups: {
      'G_PT': GroupState(
        id: 'G_PT',
        coordinatorId: 'PT',
        memberIds: ['PT'],
        transport: PlaybackState.stopped,
      ),
    },
  );
}

/// A multi-room household for header subtitle counting: 3 rooms, 1 group
/// playing (`hasActiveStream`), so the subtitle reads "3 rooms · 1 playing".
Household mixedHousehold() {
  return const Household(
    rooms: {
      'OF': RoomState(
        id: 'OF',
        name: 'Office',
        kind: RoomKind.speaker,
        volume: 55,
        groupId: 'G_OF',
      ),
      'BR': RoomState(
        id: 'BR',
        name: 'Bedroom',
        kind: RoomKind.speaker,
        volume: 15,
        groupId: 'G_BR',
      ),
      'PT': RoomState(
        id: 'PT',
        name: 'Patio',
        kind: RoomKind.speaker,
        volume: 0,
        online: false,
        groupId: 'G_PT',
      ),
    },
    groups: {
      'G_OF': GroupState(
        id: 'G_OF',
        coordinatorId: 'OF',
        memberIds: ['OF'],
        transport: PlaybackState.playing,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
      ),
      'G_BR': GroupState(
        id: 'G_BR',
        coordinatorId: 'BR',
        memberIds: ['BR'],
        transport: PlaybackState.stopped,
      ),
      'G_PT': GroupState(
        id: 'G_PT',
        coordinatorId: 'PT',
        memberIds: ['PT'],
        transport: PlaybackState.stopped,
      ),
    },
  );
}

/// A handle returned by [wrap]: the widget to pump, plus a `calls` getter that
/// resolves the spy lazily (the override runs on first provider read, i.e.
/// during the pump that happens after [wrap] returns).
class WrapHandle {
  WrapHandle(this.widget, this._resolveSpy);
  final Widget widget;
  final SpyPlayback Function() _resolveSpy;

  /// Recorded controller calls (`togglePlay(...)`, `setVolume(...)`, ...).
  List<String> get calls => _resolveSpy().calls;
}

/// Build the widget under test inside a [ProviderScope] seeded with [household],
/// the oto theme, and a [SpyPlayback] controller capturing command calls.
WrapHandle wrap(Widget child, {required Household household}) {
  SpyPlayback? spy;
  final widget = ProviderScope(
    overrides: [
      householdProvider.overrideWith(() => FixtureHousehold(household)),
      playbackControllerProvider.overrideWith((ref) => spy = SpyPlayback(ref)),
    ],
    child: MaterialApp(
      theme: otoTheme(Brightness.light, Accent.teal),
      home: Scaffold(body: child),
    ),
  );
  return WrapHandle(widget, () => spy!);
}
