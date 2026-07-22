// #129: v0.6.3 folded Room detail away on wide layouts, which took its
// join/leave-group kebab with it - a solo room had no room-level affordance at
// all short of resizing the window. The kebab now lives in the Now Playing pane
// header, which is what a wide room tap selects into.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/ui/group/group_editor_screen.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';

import '../home/_fixtures.dart';

void main() {
  testWidgets('a solo room source shows the room options kebab', (t) async {
    // G_OF is a single-member group whose sole member is room OF.
    final h = wrap(
      const NowPlayingBody(groupId: 'G_OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('room-kebab-OF')), findsOneWidget);
  });

  testWidgets('the kebab opens the group-rooms entry point', (t) async {
    // A solo room has nothing to ungroup, so the sheet correctly offers only
    // "Group rooms" here - RoomOptionsButton hides Ungroup at memberCount 1.
    final h = wrap(
      const NowPlayingBody(groupId: 'G_OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-kebab-OF')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('room-kebab-group-OF')), findsOneWidget);
    expect(find.byKey(const Key('room-kebab-ungroup-OF')), findsNothing);
  });

  testWidgets('a multi-room group shows no room kebab', (t) async {
    // Two members, so there is no single room to act on. Ungrouping a member is
    // reached from the group card's own "Group options" kebab, which opens the
    // group editor as a dialog on wide.
    final h = wrap(
      const NowPlayingBody(groupId: 'G_LR'),
      household: groupEditHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('room-kebab-LR')), findsNothing);
    expect(find.byKey(const Key('room-kebab-KT')), findsNothing);
  });

  testWidgets('an unknown group shows no room kebab', (t) async {
    // Stale selection: the pane can outlive its source (regroup, gone offline).
    // The header still renders, but its actions must not fire with a dead id.
    final h = wrap(
      const NowPlayingBody(groupId: 'G_GONE'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('room-kebab-OF')), findsNothing);
  });

  testWidgets('a sole member that has moved to another group shows no kebab', (
    t,
  ) async {
    // The group still claims one member, but that room's own groupId says it
    // belongs elsewhere. The control dispatches commands against the member id,
    // so a disagreement between the two sides must hide it rather than act on
    // a stale room.
    const household = Household(
      rooms: {
        'OF': RoomState(
          id: 'OF',
          name: 'Office',
          kind: RoomKind.speaker,
          groupId: 'G_OTHER',
        ),
      },
      groups: {
        'G_OF': GroupState(
          id: 'G_OF',
          coordinatorId: 'OF',
          memberIds: ['OF'],
          transport: PlaybackState.stopped,
        ),
      },
    );
    final h = wrap(const NowPlayingBody(groupId: 'G_OF'), household: household);
    await t.pumpWidget(h.widget);

    expect(find.byKey(const Key('room-kebab-OF')), findsNothing);
  });

  testWidgets('on a wide window, Group rooms opens the editor as a dialog', (
    t,
  ) async {
    // The #129 acceptance criterion end to end: on a wide window a solo room's
    // join/leave actions are reachable WITHOUT resizing to phone width. The
    // kebab itself is not width-gated, so this also pins that the wide path
    // opens the dialog-hosted editor rather than pushing a full-screen route.
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final h = wrap(
      const NowPlayingBody(groupId: 'G_OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-kebab-OF')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('room-kebab-group-OF')));
    await t.pumpAndSettle();

    expect(find.byType(GroupEditorBody), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('on a phone window, Group rooms pushes the full-screen route', (
    t,
  ) async {
    // The discriminator for the wide test above: GroupEditorBody renders in
    // BOTH presentations, so only the Dialog tells them apart. Pinning the
    // phone branch here proves the wide assertion is not vacuous.
    //
    // Note this also documents a deliberate consequence of putting the kebab in
    // NowPlayingBody: the phone Now Playing screen (reachable from the bottom
    // strip) now offers room options for a solo room too, consistent with Room
    // detail.
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final h = wrap(
      const NowPlayingBody(groupId: 'G_OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-kebab-OF')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('room-kebab-group-OF')));
    await t.pumpAndSettle();

    expect(find.byType(GroupEditorScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
