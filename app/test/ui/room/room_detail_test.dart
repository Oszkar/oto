import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/ui/room/room_detail_screen.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';

import '../home/_fixtures.dart';

void main() {
  testWidgets('play routes to the group; next routes to the group', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    await t.tap(find.byKey(const Key('room-detail-play-OF')));
    expect(h.calls, contains('togglePlay(G_OF,playing)'));
    await t.tap(find.byKey(const Key('room-detail-next-OF')));
    expect(h.calls, contains('next(G_OF)'));
  });

  testWidgets('prev routes to the group', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    await t.tap(find.byKey(const Key('room-detail-prev-OF')));
    expect(h.calls, contains('previous(G_OF)'));
  });

  testWidgets('idle room: play still routes to the group (starts it)', (t) async {
    // BR is in a stopped solo group G_BR; tapping play must target the group
    // with the current (stopped) transport so togglePlay starts it.
    final h = wrap(
      const RoomDetailScreen(speakerId: 'BR'),
      household: idleHousehold(),
    );
    await t.pumpWidget(h.widget);
    await t.tap(find.byKey(const Key('room-detail-play-BR')));
    expect(h.calls, contains('togglePlay(G_BR,stopped)'));
  });

  testWidgets('renders no EQ/TV/System sections', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    expect(find.text('Sound'), findsNothing);
    expect(find.text('TV & Surround'), findsNothing);
    expect(find.text('System'), findsNothing);
  });

  testWidgets('dragging the slider calls setVolume + setVolumeEnd', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.drag(find.byType(OtoSlider), const Offset(40, 0));
    await t.pumpAndSettle();

    expect(h.calls.any((c) => c.startsWith('setVolume(OF,')), isTrue);
    expect(h.calls.any((c) => c.startsWith('setVolumeEnd(OF,')), isTrue);
  });

  testWidgets('header shows room name and model', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Move 2'), findsOneWidget);
  });

  testWidgets('kebab button is present', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    expect(find.byKey(const Key('room-kebab-OF')), findsOneWidget);
  });

  testWidgets('kebab shows Group rooms; no Ungroup for solo room', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    await t.tap(find.byKey(const Key('room-kebab-OF')));
    await t.pumpAndSettle();
    expect(find.text('Group rooms'), findsOneWidget);
    // Solo group (1 member) - no Ungroup
    expect(find.byKey(const Key('room-kebab-ungroup-OF')), findsNothing);
  });

  testWidgets('kebab shows Ungroup when group has >1 member', (t) async {
    // Build a household where OF is in a 2-member group.
    const household = Household(
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
        'KT': RoomState(
          id: 'KT',
          name: 'Kitchen',
          model: 'Era 100',
          kind: RoomKind.speaker,
          volume: 30,
          online: true,
          groupId: 'G_OF',
        ),
      },
      groups: {
        'G_OF': GroupState(
          id: 'G_OF',
          coordinatorId: 'OF',
          memberIds: ['OF', 'KT'],
          transport: PlaybackState.playing,
          track: Track(title: 'Strobe', artist: 'Deadmau5'),
        ),
      },
    );
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: household,
    );
    await t.pumpWidget(h.widget);
    await t.tap(find.byKey(const Key('room-kebab-OF')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('room-kebab-ungroup-OF')), findsOneWidget);
  });

  testWidgets('Ungroup calls leaveGroup on the speaker', (t) async {
    const household = Household(
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
        'KT': RoomState(
          id: 'KT',
          name: 'Kitchen',
          model: 'Era 100',
          kind: RoomKind.speaker,
          volume: 30,
          online: true,
          groupId: 'G_OF',
        ),
      },
      groups: {
        'G_OF': GroupState(
          id: 'G_OF',
          coordinatorId: 'OF',
          memberIds: ['OF', 'KT'],
          transport: PlaybackState.playing,
          track: Track(title: 'Strobe', artist: 'Deadmau5'),
        ),
      },
    );
    final h = wrap(
      const RoomDetailScreen(speakerId: 'OF'),
      household: household,
    );
    await t.pumpWidget(h.widget);
    await t.tap(find.byKey(const Key('room-kebab-OF')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('room-kebab-ungroup-OF')));
    await t.pumpAndSettle();
    expect(h.groupingCalls, contains('leaveGroup(OF)'));
  });

  testWidgets('graceful fallback when room is not found', (t) async {
    final h = wrap(
      const RoomDetailScreen(speakerId: 'MISSING'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);
    // Should not throw; renders without crashing.
    expect(find.byType(RoomDetailScreen), findsOneWidget);
    // No kebab in the missing-room fallback: its actions would fire with an
    // invalid speakerId.
    expect(find.byKey(const Key('room-kebab-MISSING')), findsNothing);
  });
}
