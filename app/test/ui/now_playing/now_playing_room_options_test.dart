// #129: v0.6.3 folded Room detail away on wide layouts, which took its
// join/leave-group kebab with it - a solo room had no room-level affordance at
// all short of resizing the window. The kebab now lives in the Now Playing pane
// header, which is what a wide room tap selects into.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
