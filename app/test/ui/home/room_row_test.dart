import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/ui/home/room_row.dart';
import 'package:oto/src/ui/room/room_detail_screen.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';

import '_fixtures.dart';

void main() {
  testWidgets('idle room shows Idle and no resume action', (t) async {
    final h = wrap(const RoomRow(speakerId: 'BR'), household: idleHousehold());
    await t.pumpWidget(h.widget);

    expect(find.textContaining('Idle'), findsOneWidget);
    expect(find.byKey(const Key('room-play-BR')), findsNothing);
  });

  testWidgets('playing room shows its track title and a pause button', (
    t,
  ) async {
    final h = wrap(
      const RoomRow(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.textContaining('Strobe'), findsOneWidget);
    expect(find.byKey(const Key('room-play-OF')), findsOneWidget);
  });

  testWidgets('tapping the play/pause button calls togglePlay', (t) async {
    final h = wrap(
      const RoomRow(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-play-OF')));
    await t.pump();

    expect(h.calls, contains('togglePlay(G_OF,playing)'));
  });

  testWidgets('dragging the slider calls setVolume + setVolumeEnd', (t) async {
    final h = wrap(
      const RoomRow(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.drag(find.byType(OtoSlider), const Offset(40, 0));
    await t.pumpAndSettle();

    expect(h.calls.any((c) => c.startsWith('setVolume(OF,')), isTrue);
    expect(h.calls.any((c) => c.startsWith('setVolumeEnd(OF,')), isTrue);
  });

  testWidgets('offline room is dimmed with no slider or controls', (t) async {
    final h = wrap(
      const RoomRow(speakerId: 'PT'),
      household: offlineHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.byType(OtoSlider), findsNothing);
    expect(find.byKey(const Key('room-play-PT')), findsNothing);
    expect(find.byType(Opacity), findsWidgets);
  });

  testWidgets(
    'offline room with a stale active stream shows no play button or slider',
    (t) async {
      final h = wrap(
        const RoomRow(speakerId: 'OS'),
        household: offlineWithStreamHousehold(),
      );
      await t.pumpWidget(h.widget);

      expect(find.byKey(const Key('room-play-OS')), findsNothing);
      expect(find.byType(OtoSlider), findsNothing);
      expect(find.byType(Opacity), findsWidgets);
    },
  );

  testWidgets('tapping the identity region pushes RoomDetailScreen', (t) async {
    final h = wrap(
      const RoomRow(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-open-OF')));
    await t.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsOneWidget);
  });

  testWidgets('tapping play button does NOT navigate to RoomDetailScreen', (
    t,
  ) async {
    final h = wrap(
      const RoomRow(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-play-OF')));
    await t.pump();

    expect(find.byType(RoomDetailScreen), findsNothing);
    expect(h.calls, contains('togglePlay(G_OF,playing)'));
  });

  testWidgets('offline room identity tap does not navigate', (t) async {
    // Offline rooms are non-interactive (no chevron, no controls); the identity
    // tap is disabled to match, so it must not open room detail.
    final h = wrap(
      const RoomRow(speakerId: 'PT'),
      household: offlineHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-open-PT')));
    await t.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsNothing);
  });
}
