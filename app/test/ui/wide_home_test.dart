// Wide Home shell (Task 5): at >=840 Home is a master-detail layout - the room
// grid on the left, a persistent NowPlayingPane on the right - and the floating
// BottomStrip is suppressed. Below 840 it stays exactly today's phone behavior
// (floating strip, no pane). Tapping a group card selects it into the pane.
//
// The tier is read from `MediaQuery.sizeOf`, so these tests force the view size
// (mirroring showcase_smoke_test) before pumping so `context.isWide` sees it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/state/selected_source.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/home/bottom_strip.dart';
import 'package:oto/src/ui/home/group_card.dart';
import 'package:oto/src/ui/home/home_screen.dart';
import 'package:oto/src/ui/now_playing/now_playing_pane.dart';
import 'package:oto/src/ui/widgets/album_art.dart';

import 'home/_fixtures.dart';

/// A 2-room group (Living Room + Kitchen, coordinator LR, playing) - an active
/// source, so the strip WOULD show on phone and the group renders as a
/// GroupCard that select-in-place targets on wide.
Household _activeGroupHousehold() {
  return const Household(
    rooms: {
      'LR': RoomState(
        id: 'LR',
        name: 'Living Room',
        kind: RoomKind.speaker,
        volume: 40,
        groupId: 'G_LR',
      ),
      'KT': RoomState(
        id: 'KT',
        name: 'Kitchen',
        kind: RoomKind.speaker,
        volume: 30,
        groupId: 'G_LR',
      ),
    },
    groups: {
      'G_LR': GroupState(
        id: 'G_LR',
        coordinatorId: 'LR',
        memberIds: ['LR', 'KT'],
        transport: PlaybackState.playing,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
        groupVolume: 35,
      ),
    },
  );
}

/// One solo idle room - no active stream, so there is no source and the pane
/// falls back to its empty placeholder.
Household _idleHousehold() {
  return const Household(
    rooms: {
      'OF': RoomState(
        id: 'OF',
        name: 'Office',
        kind: RoomKind.speaker,
        volume: 20,
        groupId: 'G_OF',
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
}

// A non-empty topology so `homeViewStateProvider` resolves to a household-
// bearing state (HomeReady) rather than HomeEmpty; the exact speakers are
// irrelevant (only empty-vs-nonempty matters).
const _topology = rust_api.Topology(
  speakers: [
    rust_api.DiscoveredSpeaker(
      id: 'LR',
      roomName: 'Living Room',
      ip: '10.0.0.10',
      model: 'Beam',
    ),
  ],
  groups: [
    rust_api.DiscoveredGroup(id: 'G_LR', coordinator: 'LR', members: ['LR']),
  ],
);

class _DataDiscovery extends Discovery {
  _DataDiscovery(this._t);
  final rust_api.Topology _t;
  @override
  Future<rust_api.Topology> build() async => _t;
}

/// Pump [HomeScreen] at [size] inside a ProviderScope seeded with [household],
/// a loaded SharedPreferences (for the header/layout), and spy controllers.
Future<void> _pump(
  WidgetTester tester, {
  required Household household,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoveryProvider.overrideWith(() => _DataDiscovery(_topology)),
        householdProvider.overrideWith(() => FixtureHousehold(household)),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        playbackControllerProvider.overrideWith((ref) => SpyPlayback(ref)),
        groupingControllerProvider.overrideWith((ref) => SpyGrouping(ref)),
        positionApiProvider.overrideWithValue(const StubPositionApi()),
      ],
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'wide (>=840): renders the detail pane, suppresses the floating strip',
    (tester) async {
      await _pump(
        tester,
        household: _activeGroupHousehold(),
        size: const Size(1280, 800),
      );

      expect(find.byType(NowPlayingPane), findsOneWidget);
      // The active stream would float a BottomStrip on phone; wide replaces it
      // with the persistent pane.
      expect(find.byType(BottomStrip), findsNothing);
    },
  );

  testWidgets('wide: tapping a group card selects it into the pane', (
    tester,
  ) async {
    await _pump(
      tester,
      household: _activeGroupHousehold(),
      size: const Size(1280, 800),
    );

    // Tap the group card body (the header album art is inside the outer
    // select-on-wide GestureDetector and absorbs no taps of its own).
    await tester.tap(
      find.descendant(
        of: find.byType(GroupCard),
        matching: find.byType(AlbumArt),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    expect(container.read(selectedSourceProvider), 'G_LR');
    expect(container.read(resolvedSourceProvider), 'G_LR');
  });

  testWidgets('wide: empty pane placeholder when nothing is active', (
    tester,
  ) async {
    await _pump(
      tester,
      household: _idleHousehold(),
      size: const Size(1280, 800),
    );

    expect(find.byType(NowPlayingPane), findsOneWidget);
    expect(find.text('Pick a room to control'), findsOneWidget);
  });

  testWidgets(
    'phone (<840): keeps the floating strip, no detail pane (unchanged)',
    (tester) async {
      await _pump(
        tester,
        household: _activeGroupHousehold(),
        size: const Size(390, 844),
      );

      expect(find.byType(BottomStrip), findsOneWidget);
      expect(find.byType(NowPlayingPane), findsNothing);
    },
  );
}
