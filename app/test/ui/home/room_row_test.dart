import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/ui/home/room_row.dart';
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
}
