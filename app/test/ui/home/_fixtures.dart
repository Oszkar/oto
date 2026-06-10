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
  Future<void> next(String groupId) async {
    calls.add('next($groupId)');
  }

  @override
  Future<void> previous(String groupId) async {
    calls.add('previous($groupId)');
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

/// A [GroupingController] that records group-volume commands instead of hitting
/// Rust. Used by the group-card test for the group-master slider.
class SpyGrouping extends GroupingController {
  SpyGrouping(Ref ref) : super(ref, const CommandApi());

  final calls = <String>[];

  @override
  void setGroupVolume(String groupId, int v) {
    calls.add('setGroupVolume($groupId,$v)');
  }

  @override
  void setGroupVolumeEnd(String groupId, int v) {
    calls.add('setGroupVolumeEnd($groupId,$v)');
  }

  @override
  Future<void> setGroupMute(String groupId, bool muted) async {
    calls.add('setGroupMute($groupId,$muted)');
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

/// An offline solo room `OS` (Outside) whose group `G_OS` still reports an
/// active stream (track + playing transport). Models the reachable edge case
/// where a room drops offline mid-stream: a `SubscriptionError` clears
/// `online` without clearing the group's transport/track, so `hasActiveStream`
/// stays true while `online` is false.
Household offlineWithStreamHousehold() {
  return const Household(
    rooms: {
      'OS': RoomState(
        id: 'OS',
        name: 'Outside',
        model: 'Move 2',
        kind: RoomKind.speaker,
        volume: 40,
        online: false,
        groupId: 'G_OS',
      ),
    },
    groups: {
      'G_OS': GroupState(
        id: 'G_OS',
        coordinatorId: 'OS',
        memberIds: ['OS'],
        transport: PlaybackState.playing,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
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

/// A handle returned by [wrap]: the widget to pump, plus `calls` getters that
/// resolve the spies lazily (the overrides run on first provider read, i.e.
/// during the pump that happens after [wrap] returns).
class WrapHandle {
  WrapHandle(this.widget, this._resolvePlayback, this._resolveGrouping);
  final Widget widget;
  final SpyPlayback Function() _resolvePlayback;
  final SpyGrouping Function() _resolveGrouping;

  /// Recorded playback-controller calls (`togglePlay(...)`, `setVolume(...)`).
  List<String> get calls => _resolvePlayback().calls;

  /// Recorded grouping-controller calls (`setGroupVolume(...)`, ...).
  List<String> get groupingCalls => _resolveGrouping().calls;
}

/// Build the widget under test inside a [ProviderScope] seeded with [household],
/// the oto theme, a [SpyPlayback] and a [SpyGrouping] controller capturing
/// command calls.
WrapHandle wrap(Widget child, {required Household household}) {
  SpyPlayback? playback;
  SpyGrouping? grouping;
  final widget = ProviderScope(
    overrides: [
      householdProvider.overrideWith(() => FixtureHousehold(household)),
      playbackControllerProvider.overrideWith(
        (ref) => playback = SpyPlayback(ref),
      ),
      groupingControllerProvider.overrideWith(
        (ref) => grouping = SpyGrouping(ref),
      ),
    ],
    child: MaterialApp(
      theme: otoTheme(Brightness.light, Accent.teal),
      home: Scaffold(body: child),
    ),
  );
  return WrapHandle(widget, () => playback!, () => grouping!);
}
