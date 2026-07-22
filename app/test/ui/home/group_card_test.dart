import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/ui/group/group_editor_screen.dart';
import 'package:oto/src/ui/home/group_card.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';

import '_fixtures.dart';

/// A multi-room group `G` with [count] member rooms (coordinator `R0` first).
/// The group is playing with a known track and a group-master volume, so the
/// header renders now-playing + a resume button and the master slider is live.
///
/// The coordinator (`R0`) is named "Living Room" so the header title does not
/// collide with the per-room level labels "Room 1".."Room N-1" in finders.
Household groupHousehold(int count) {
  final rooms = <String, RoomState>{};
  for (var i = 0; i < count; i++) {
    rooms['R$i'] = RoomState(
      id: 'R$i',
      name: i == 0 ? 'Living Room' : 'Room $i',
      kind: RoomKind.speaker,
      volume: 20 + i * 5,
      groupId: 'G',
    );
  }
  return Household(
    rooms: rooms,
    groups: {
      'G': GroupState(
        id: 'G',
        coordinatorId: 'R0',
        memberIds: [for (var i = 0; i < count; i++) 'R$i'],
        transport: PlaybackState.playing,
        track: const Track(title: 'Strobe', artist: 'Deadmau5'),
        groupVolume: 40,
      ),
    },
  );
}

void main() {
  testWidgets('6-member group renders exactly 4 level rows + "+2 more"', (
    t,
  ) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(6));
    await t.pumpWidget(h.widget);

    // 4 per-room level rows + the group-master = 5 sliders total.
    expect(find.byType(OtoSlider), findsNWidgets(5));
    // First 4 rooms visible (coordinator "Living Room" + Room 1..3), the last
    // 2 (Room 4, Room 5) hidden behind the overflow.
    expect(find.text('Room 1'), findsOneWidget);
    expect(find.text('Room 3'), findsOneWidget);
    expect(find.text('Room 4'), findsNothing);
    expect(find.text('Room 5'), findsNothing);

    // The overflow button, keyed and reading "+2 more".
    expect(find.byKey(const Key('group-more-G')), findsOneWidget);
    expect(
      find.textContaining('2 more'),
      findsOneWidget,
      reason: '6 - 4 = 2 hidden rooms',
    );
  });

  testWidgets('4-member group renders 4 level rows and no overflow', (t) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(4));
    await t.pumpWidget(h.widget);

    // 4 per-room level rows + the group-master = 5 sliders total.
    expect(find.byType(OtoSlider), findsNWidgets(5));
    expect(find.text('Room 3'), findsOneWidget);
    expect(find.byKey(const Key('group-more-G')), findsNothing);
  });

  testWidgets('group play button is keyed and present when active', (t) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(2));
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('group-play-G')), findsOneWidget);
    // Now-playing line combines title + artist into one Text ("Strobe - ...").
    expect(find.textContaining('Strobe'), findsOneWidget);
  });

  testWidgets('tapping the group play button calls togglePlay(groupId)', (
    t,
  ) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(2));
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('group-play-G')));
    await t.pump();

    expect(h.calls, contains('togglePlay(G,playing)'));
  });

  testWidgets('dragging the group-master slider calls the GroupingController', (
    t,
  ) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(2));
    await t.pumpWidget(h.widget);

    await t.drag(find.byKey(const Key('group-volume-G')), const Offset(40, 0));
    await t.pumpAndSettle();

    expect(
      h.groupingCalls.any((c) => c.startsWith('setGroupVolume(G,')),
      isTrue,
      reason: 'mid-drag setGroupVolume routed to the grouping controller',
    );
    expect(
      h.groupingCalls.any((c) => c.startsWith('setGroupVolumeEnd(G,')),
      isTrue,
      reason:
          'drag release setGroupVolumeEnd routed to the grouping controller',
    );
    // The group-master must NOT route through the per-room playback path.
    expect(h.calls.any((c) => c.startsWith('setVolume(')), isFalse);
  });

  testWidgets('dragging a per-room level slider calls setVolume for that room', (
    t,
  ) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(2));
    await t.pumpWidget(h.widget);

    // Sliders in order: [group-master, R0 level, R1 level]. Drag the R1 level.
    final sliders = find.byType(OtoSlider);
    await t.drag(sliders.at(2), const Offset(40, 0));
    await t.pumpAndSettle();

    expect(
      h.calls.any((c) => c.startsWith('setVolume(R1,')),
      isTrue,
      reason: 'per-room level slider routes to that room id via setVolume',
    );
    expect(h.calls.any((c) => c.startsWith('setVolumeEnd(R1,')), isTrue);
  });

  testWidgets('offline group member has a disabled level slider', (t) async {
    // 2-member group: R0 (coordinator) online, R1 offline. R1 can carry a
    // stale last-known volume, but its speaker is unreachable -> its level
    // slider must be disabled (mirrors RoomCard/RoomRow's online gate).
    final household = Household(
      rooms: {
        'R0': const RoomState(
          id: 'R0',
          name: 'Living Room',
          kind: RoomKind.speaker,
          volume: 20,
          groupId: 'G',
        ),
        'R1': const RoomState(
          id: 'R1',
          name: 'Room 1',
          kind: RoomKind.speaker,
          volume: 25,
          online: false,
          groupId: 'G',
        ),
      },
      groups: {
        'G': const GroupState(
          id: 'G',
          coordinatorId: 'R0',
          memberIds: ['R0', 'R1'],
          transport: PlaybackState.playing,
          track: Track(title: 'Strobe', artist: 'Deadmau5'),
          groupVolume: 40,
        ),
      },
    );
    final h = wrap(const GroupCard(groupId: 'G'), household: household);
    await t.pumpWidget(h.widget);

    // Sliders in order: [group-master, R0 level, R1 level].
    final sliders = find.byType(OtoSlider);
    expect(
      t.widget<OtoSlider>(sliders.at(1)).onChanged,
      isNotNull,
      reason: 'online member R0 stays enabled',
    );
    expect(
      t.widget<OtoSlider>(sliders.at(2)).onChanged,
      isNull,
      reason: 'offline member R1 slider disabled',
    );
  });

  testWidgets('unknown group id renders nothing', (t) async {
    final h = wrap(
      const GroupCard(groupId: 'NOPE'),
      household: groupHousehold(2),
    );
    await t.pumpWidget(h.widget);

    expect(find.byType(OtoSlider), findsNothing);
    expect(find.byKey(const Key('group-play-NOPE')), findsNothing);
  });

  testWidgets(
    'tapping group-more affordance pushes GroupEditorScreen with coordinator',
    (t) async {
      // 6-member group: coordinator is R0. The overflow button appears because
      // 6 > _maxLevels (4).
      final h = wrap(
        const GroupCard(groupId: 'G'),
        household: groupHousehold(6),
      );
      await t.pumpWidget(h.widget);

      expect(find.byKey(const Key('group-more-G')), findsOneWidget);

      await t.tap(find.byKey(const Key('group-more-G')));
      await t.pumpAndSettle();

      expect(find.byType(GroupEditorScreen), findsOneWidget);
    },
  );

  testWidgets('header menu opens the editor for a small (no-overflow) group', (
    t,
  ) async {
    // 2-member group: no overflow button, so the always-present header menu is
    // the only path to the editor (and thus Ungroup all). Regression for the
    // QA gap where a small group could not be ungrouped.
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(2));
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('group-more-G')), findsNothing);

    await t.tap(find.byKey(const Key('group-open-G')));
    await t.pumpAndSettle();

    expect(find.byType(GroupEditorScreen), findsOneWidget);
  });

  testWidgets(
    'tapping group play button does NOT navigate to GroupEditorScreen',
    (t) async {
      final h = wrap(
        const GroupCard(groupId: 'G'),
        household: groupHousehold(6),
      );
      await t.pumpWidget(h.widget);

      await t.tap(find.byKey(const Key('group-play-G')));
      await t.pump();

      expect(find.byType(GroupEditorScreen), findsNothing);
      expect(h.calls, contains('togglePlay(G,playing)'));
    },
  );

  testWidgets(
    'tapping the volume section on phone does not navigate to Now Playing',
    (t) async {
      // Regression: the header's select/open InkWell must not extend over the
      // volume section, or a tap meant for a slider (or a miss next to one)
      // pushes NowPlayingScreen instead of adjusting volume.
      final h = wrap(
        const GroupCard(groupId: 'G'),
        household: groupHousehold(2),
      );
      await t.pumpWidget(h.widget);

      await t.tap(find.text('ROOM LEVELS'));
      await t.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsNothing);
    },
  );

  testWidgets('tapping the group volume icon mutes the group', (t) async {
    final h = wrap(const GroupCard(groupId: 'G'), household: groupHousehold(3));
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('group-mute-G')));

    expect(h.groupingCalls, contains('setGroupMute(G,true)'));
  });

  testWidgets('group mute is disabled when the coordinator is unreachable', (
    t,
  ) async {
    // A group command is dispatched to its coordinator; offering a control
    // that is known to fail would contradict the per-room controls, which
    // already gate on `online`.
    final base = groupHousehold(3);
    final offline = Household(
      rooms: {
        ...base.rooms,
        'R0': base.rooms['R0']!.copyWith(online: false),
      },
      groups: base.groups,
    );
    final h = wrap(const GroupCard(groupId: 'G'), household: offline);
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('group-mute-G')), warnIfMissed: false);

    expect(h.groupingCalls, isEmpty);
  });
}
