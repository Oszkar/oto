import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';

import '../home/_fixtures.dart';

/// A playing solo group `G_OF` (room `OF`) with a known track and a group-master
/// volume. (The track still carries a duration as a fixture for v0.6.1's
/// position work; v0.6.0 renders no progress bar.)
Household nowPlayingHousehold() {
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
        track: Track(
          id: 't1',
          title: 'Strobe',
          artist: 'Deadmau5',
          duration: Duration(minutes: 4, seconds: 8),
        ),
        groupVolume: 36,
      ),
    },
  );
}

void main() {
  testWidgets('renders the track title and artist', (t) async {
    final h = wrap(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
    );
    await t.pumpWidget(h.widget);

    expect(find.text('Strobe'), findsOneWidget);
    expect(find.textContaining('Deadmau5'), findsOneWidget);
  });

  testWidgets('tapping play/pause calls togglePlay', (t) async {
    final h = wrap(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('np-play-G_OF')));
    await t.pump();

    expect(h.calls, contains('togglePlay(G_OF,playing)'));
  });

  testWidgets('tapping prev calls previous(groupId)', (t) async {
    final h = wrap(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('np-prev-G_OF')));
    await t.pump();

    expect(h.calls, contains('previous(G_OF)'));
  });

  testWidgets('tapping next calls next(groupId)', (t) async {
    final h = wrap(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
    );
    await t.pumpWidget(h.widget);

    await t.tap(find.byKey(const Key('np-next-G_OF')));
    await t.pump();

    expect(h.calls, contains('next(G_OF)'));
  });

  testWidgets('no progress/seek bar in v0.6.0 (deferred to v0.6.1)', (t) async {
    final h = wrap(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
    );
    await t.pumpWidget(h.widget);

    // The progress bar is intentionally absent: the backend provides neither
    // track duration nor a position anchor yet (restored in v0.6.1 via a
    // speakerState/GetPositionInfo poll). The only Slider on screen is the
    // group-volume control.
    expect(find.byKey(const Key('np-progress-G_OF')), findsNothing);
    expect(find.byType(Slider), findsOneWidget); // group volume only
  });
}
