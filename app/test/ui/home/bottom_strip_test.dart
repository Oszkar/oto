import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/source.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/ui/home/bottom_strip.dart';

import '_fixtures.dart';

/// A household with [active] playing groups (`A0`..`A{n-1}`) plus one idle
/// group `IDLE`. Each active group is a solo room whose name sorts in id order
/// ("Alpha", "Bravo", "Charlie", ...) so the rendered source order is
/// deterministic. The idle group is stopped with no track, so it is NOT a
/// source and must not appear in the strip.
Household sourcesHousehold(int active) {
  const names = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo'];
  final rooms = <String, RoomState>{
    'IR': const RoomState(
      id: 'IR',
      name: 'Idle Room',
      kind: RoomKind.speaker,
      volume: 10,
      groupId: 'IDLE',
    ),
  };
  final groups = <String, GroupState>{
    'IDLE': const GroupState(
      id: 'IDLE',
      coordinatorId: 'IR',
      memberIds: ['IR'],
      transport: PlaybackState.stopped,
    ),
  };
  for (var i = 0; i < active; i++) {
    final rid = 'R$i';
    final gid = 'A$i';
    rooms[rid] = RoomState(
      id: rid,
      name: names[i],
      kind: RoomKind.speaker,
      volume: 30 + i,
      groupId: gid,
    );
    groups[gid] = GroupState(
      id: gid,
      coordinatorId: rid,
      memberIds: [rid],
      transport: PlaybackState.playing,
      track: Track(title: 'Track $i', artist: 'Artist $i'),
    );
  }
  return Household(rooms: rooms, groups: groups);
}

void main() {
  testWidgets('0 active sources -> renders nothing visible', (t) async {
    final h = wrap(
      BottomStrip(onTapSource: (_) {}),
      household: sourcesHousehold(0),
    );
    await t.pumpWidget(h.widget);

    // The widget is present but collapses to an empty box: no source rows.
    expect(find.byType(BottomStrip), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('strip-play-'),
      ),
      findsNothing,
    );
    // No play key for the idle group either.
    expect(find.byKey(const Key('strip-play-IDLE')), findsNothing);
  });

  testWidgets('1 active source -> exactly one mini-player row', (t) async {
    final h = wrap(
      BottomStrip(onTapSource: (_) {}),
      household: sourcesHousehold(1),
    );
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('strip-play-A0')), findsOneWidget);
    expect(find.text('Track 0'), findsOneWidget);
  });

  testWidgets('3 active sources -> three rows, uncapped, no "+N more"', (
    t,
  ) async {
    final h = wrap(
      BottomStrip(onTapSource: (_) {}),
      household: sourcesHousehold(3),
    );
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('strip-play-A0')), findsOneWidget);
    expect(find.byKey(const Key('strip-play-A1')), findsOneWidget);
    expect(find.byKey(const Key('strip-play-A2')), findsOneWidget);
    // All three play keys present (uncapped).
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('strip-play-'),
      ),
      findsNWidgets(3),
    );
    // No "+N more"/"manage" overflow affordance.
    expect(find.textContaining('more'), findsNothing);
    expect(find.textContaining('manage'), findsNothing);
  });

  testWidgets('tapping a row body fires onTapSource with that Source', (
    t,
  ) async {
    Source? tapped;
    final h = wrap(
      BottomStrip(onTapSource: (s) => tapped = s),
      household: sourcesHousehold(3),
    );
    await t.pumpWidget(h.widget);

    // Tap the body of the second row (Bravo / Track 1).
    await t.tap(find.text('Track 1'));
    await t.pump();

    expect(tapped, isNotNull);
    expect(tapped!.id, 'A1');
    expect(tapped!.label, 'Bravo');
  });

  testWidgets('tapping the play button does NOT fire onTapSource', (t) async {
    Source? tapped;
    final h = wrap(
      BottomStrip(onTapSource: (s) => tapped = s),
      household: sourcesHousehold(3),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('strip-play-A1')));
    await t.pump();

    expect(tapped, isNull, reason: 'play button absorbs its own tap');
  });

  testWidgets('tapping a row play button calls togglePlay(sourceId)', (
    t,
  ) async {
    final h = wrap(
      BottomStrip(onTapSource: (_) {}),
      household: sourcesHousehold(3),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('strip-play-A1')));
    await t.pump();

    expect(h.calls, contains('togglePlay(A1,playing)'));
  });

  testWidgets('single-source mini-player play button calls togglePlay', (
    t,
  ) async {
    final h = wrap(
      BottomStrip(onTapSource: (_) {}),
      household: sourcesHousehold(1),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('strip-play-A0')));
    await t.pump();

    expect(h.calls, contains('togglePlay(A0,playing)'));
  });

  testWidgets('offline-coordinator source disables the strip play button', (
    t,
  ) async {
    // `offlineWithStreamHousehold` (OS) is a source whose coordinator dropped
    // offline mid-stream: the group still reads active, but the speaker is
    // unreachable, so the play button must be disabled (onPressed null).
    final h = wrap(
      BottomStrip(onTapSource: (_) {}),
      household: offlineWithStreamHousehold(),
    );
    await t.pumpWidget(h.widget);

    final btn = t.widget<IconButton>(find.byKey(const Key('strip-play-G_OS')));
    expect(
      btn.onPressed,
      isNull,
      reason: 'coordinator offline -> control disabled, not a dead button',
    );
  });
}
