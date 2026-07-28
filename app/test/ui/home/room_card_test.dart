import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/ui/home/room_card.dart';
import 'package:oto/src/ui/room/room_detail_screen.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';

import '_fixtures.dart';

void main() {
  testWidgets('idle room shows Idle and no resume action', (t) async {
    final h = wrap(const RoomCard(speakerId: 'BR'), household: idleHousehold());
    await t.pumpWidget(h.widget);

    expect(find.text('Idle'), findsOneWidget);
    expect(find.byKey(const Key('room-play-BR')), findsNothing);
  });

  testWidgets('playing room shows its track title and a pause button', (
    t,
  ) async {
    final h = wrap(
      const RoomCard(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.text('Strobe'), findsOneWidget);
    expect(find.byKey(const Key('room-play-OF')), findsOneWidget);
  });

  testWidgets('tapping the play/pause button calls togglePlay', (t) async {
    final h = wrap(
      const RoomCard(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-play-OF')));
    await t.pump();

    expect(h.calls, contains('togglePlay(G_OF,playing)'));
  });

  testWidgets('dragging the slider calls setVolume + setVolumeEnd', (t) async {
    final h = wrap(
      const RoomCard(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.drag(find.byType(OtoSlider), const Offset(40, 0));
    await t.pumpAndSettle();

    expect(
      h.calls.any((c) => c.startsWith('setVolume(OF,')),
      isTrue,
      reason: 'mid-drag setVolume routed to the controller',
    );
    expect(
      h.calls.any((c) => c.startsWith('setVolumeEnd(OF,')),
      isTrue,
      reason: 'drag release setVolumeEnd routed to the controller',
    );
  });

  testWidgets(
    'offline room is dimmed but keeps a live mute button (#104)',
    (t) async {
      final h = wrap(
        const RoomCard(speakerId: 'PT'),
        household: offlineHousehold(),
      );
      await t.pumpWidget(h.widget);

      // No transport control (nothing is playing), but the volume row -
      // the slider and the mute button - stays live: it is this card's
      // one command-issuing control, the only way an offline room's health
      // can be observed to recover in-session. A disabled OtoSlider still
      // renders, so drag it to prove it actually dispatches, not just draws.
      expect(find.byType(OtoSlider), findsOneWidget);
      expect(find.byKey(const Key('room-play-PT')), findsNothing);
      await t.drag(find.byType(OtoSlider), const Offset(40, 0));
      await t.pumpAndSettle();
      expect(h.calls.any((c) => c.startsWith('setVolume(PT,')), isTrue);
      expect(h.calls.any((c) => c.startsWith('setVolumeEnd(PT,')), isTrue);
      await t.tap(find.byKey(const Key('room-mute-PT')));
      expect(h.calls, contains('setMute(PT,true)'));
      expect(
        find.byType(Opacity),
        findsWidgets,
        reason: 'offline room is rendered dimmed',
      );
    },
  );

  testWidgets(
    'offline room with a stale active stream shows no play button but keeps its slider',
    (t) async {
      final h = wrap(
        const RoomCard(speakerId: 'OS'),
        household: offlineWithStreamHousehold(),
      );
      await t.pumpWidget(h.widget);

      expect(find.byKey(const Key('room-play-OS')), findsNothing);
      expect(find.byType(OtoSlider), findsOneWidget);
      expect(
        find.byType(Opacity),
        findsWidgets,
        reason: 'offline room is rendered dimmed even with a stale stream',
      );
    },
  );

  testWidgets('tapping the identity region pushes RoomDetailScreen', (t) async {
    final h = wrap(
      const RoomCard(speakerId: 'OF'),
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
      const RoomCard(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-play-OF')));
    await t.pump();

    expect(find.byType(RoomDetailScreen), findsNothing);
    expect(h.calls, contains('togglePlay(G_OF,playing)'));
  });

  testWidgets('offline room identity tap does not navigate', (t) async {
    // Offline rooms are non-interactive (dimmed, no controls); the identity tap
    // is disabled to match, so it must not open room detail.
    final h = wrap(
      const RoomCard(speakerId: 'PT'),
      household: offlineHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-open-PT')));
    await t.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsNothing);
  });

  testWidgets('tapping the volume icon mutes the room', (t) async {
    final h = wrap(
      const RoomCard(speakerId: 'OF'),
      household: playingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-mute-OF')));

    expect(h.calls, contains('setMute(OF,true)'));
  });

  testWidgets('a muted room unmutes on tap', (t) async {
    final h = wrap(
      const RoomCard(speakerId: 'OF'),
      household: mutedHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('room-mute-OF')));

    expect(h.calls, contains('setMute(OF,false)'));
  });
}
