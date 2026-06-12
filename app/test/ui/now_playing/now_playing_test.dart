import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart'; // for OtoSlider type access

import '../home/_fixtures.dart';

/// A playing solo group `G_OF` (room `OF`) with a known track and a group-master
/// volume. Duration is set on the track so tests can assert against a known
/// total; the live position is overridden via [nowPlayingPositionProvider] in
/// the progress-bar tests.
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

    await t.ensureVisible(find.byKey(const Key('np-play-G_OF')));
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

    await t.ensureVisible(find.byKey(const Key('np-prev-G_OF')));
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

    await t.ensureVisible(find.byKey(const Key('np-next-G_OF')));
    await t.tap(find.byKey(const Key('np-next-G_OF')));
    await t.pump();

    expect(h.calls, contains('next(G_OF)'));
  });

  testWidgets('progress bar shows elapsed and total time labels', (t) async {
    // 84 s elapsed, 248 s total -> "1:24" / "4:08"
    final h = _wrapWithProgress(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
      groupId: 'G_OF',
      progress: NowPlayingProgress(
        const Duration(seconds: 84),
        const Duration(seconds: 248),
      ),
    );
    await t.pumpWidget(h);

    expect(find.text('1:24'), findsOneWidget);
    expect(find.text('4:08'), findsOneWidget);
    // Progress bar is present and non-interactive (onChanged is null -> disabled).
    expect(find.byKey(const Key('np-progress-G_OF')), findsOneWidget);
    final slider = t.widget<OtoSlider>(
      find.byKey(const Key('np-progress-G_OF')),
    );
    expect(slider.onChanged, isNull);
  });

  testWidgets('progress bar shows --:-- and zero fill when duration is unknown',
      (t) async {
    // 30 s elapsed, no duration known.
    final h = _wrapWithProgress(
      const NowPlayingScreen(groupId: 'G_OF'),
      household: nowPlayingHousehold(),
      groupId: 'G_OF',
      progress: NowPlayingProgress(
        const Duration(seconds: 30),
        null,
      ),
    );
    await t.pumpWidget(h);

    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    final slider = t.widget<OtoSlider>(
      find.byKey(const Key('np-progress-G_OF')),
    );
    expect(slider.value, 0.0);
    expect(slider.onChanged, isNull);
  });
}

/// Builds the widget under test with a fixed [NowPlayingProgress] pinned to
/// [progress] for [groupId], reusing the same theme/scaffold setup as [wrap]
/// in _fixtures.dart.
Widget _wrapWithProgress(
  Widget child, {
  required Household household,
  required String groupId,
  required NowPlayingProgress progress,
}) {
  return ProviderScope(
    overrides: [
      householdProvider.overrideWith(() => FixtureHousehold(household)),
      playbackControllerProvider.overrideWith(
        (ref) => SpyPlayback(ref),
      ),
      groupingControllerProvider.overrideWith(
        (ref) => SpyGrouping(ref),
      ),
      positionApiProvider.overrideWithValue(const StubPositionApi()),
      nowPlayingPositionProvider(groupId).overrideWithValue(progress),
    ],
    child: MaterialApp(
      theme: otoTheme(Brightness.light, Accent.teal),
      home: Scaffold(body: child),
    ),
  );
}
