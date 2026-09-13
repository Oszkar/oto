// Composition tests for the assembled HomeScreen (Task 11b).
//
// HomeScreen is the integration point: it watches `currentHomeLayoutProvider`
// for the layout and `householdProvider` for the body, then composes HomeHeader
// + the group/solo body + BottomStrip, wiring strip taps to Now Playing.
//
// The load-bearing invariant under test is the spec §6 composition rule: every
// room belongs to a group, so we iterate `household.groups` and a multi-member
// group renders ONE GroupCard while a single-member group renders a RoomCard
// (Cards) / RoomRow (Stack). A grouped room therefore NEVER appears as a
// standalone card -- no duplicates.
//
// This test owns its own `_wrap`/`_settle` helpers (rather than the leaf-widget
// `_fixtures.wrap`) because HomeScreen pulls in HomeHeader, which watches the
// current layout. It initializes from `settingsProvider`, so
// `prefsRepositoryProvider` needs a loaded SharedPreferences override. A real
// Navigator (not a bare Scaffold) lets strip taps push the Now Playing route.
import 'dart:async';

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
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/home/bottom_strip.dart';
import 'package:oto/src/ui/home/group_card.dart';
import 'package:oto/src/ui/home/home_header.dart';
import 'package:oto/src/ui/home/home_screen.dart';
import 'package:oto/src/ui/home/home_states.dart';
import 'package:oto/src/ui/home/room_card.dart';
import 'package:oto/src/ui/home/room_row.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';

import '_fixtures.dart';

/// ONE 2-room group (Living Room + Kitchen, coordinator LR, playing) plus TWO
/// solo rooms (Office playing, Bedroom idle -- each its own 1-member group).
///
/// Per the composition rule this must render exactly: one GroupCard (the LR+KT
/// group) and two solo cards/rows (Office, Bedroom). "Living Room" and
/// "Kitchen" must NOT appear as standalone room cards.
Household _twoRoomGroupPlusTwoSolos() {
  return const Household(
    rooms: {
      'LR': RoomState(
        id: 'LR',
        name: 'Living Room',
        kind: RoomKind.speaker,
        volume: 30,
        groupId: 'G_LR',
      ),
      'KT': RoomState(
        id: 'KT',
        name: 'Kitchen',
        kind: RoomKind.speaker,
        volume: 25,
        groupId: 'G_LR',
      ),
      'OF': RoomState(
        id: 'OF',
        name: 'Office',
        kind: RoomKind.speaker,
        volume: 55,
        groupId: 'G_OF',
      ),
      'BR': RoomState(
        id: 'BR',
        name: 'Bedroom',
        kind: RoomKind.speaker,
        volume: 15,
        groupId: 'G_BR',
      ),
    },
    groups: {
      // Multi-member group: coordinator LR + KT, playing.
      'G_LR': GroupState(
        id: 'G_LR',
        coordinatorId: 'LR',
        memberIds: ['LR', 'KT'],
        transport: PlaybackState.playing,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
        groupVolume: 40,
      ),
      // Solo Office, playing -> a source.
      'G_OF': GroupState(
        id: 'G_OF',
        coordinatorId: 'OF',
        memberIds: ['OF'],
        transport: PlaybackState.playing,
        track: Track(title: 'Opus', artist: 'Eric Prydz'),
      ),
      // Solo Bedroom, idle -> not a source.
      'G_BR': GroupState(
        id: 'G_BR',
        coordinatorId: 'BR',
        memberIds: ['BR'],
        transport: PlaybackState.stopped,
      ),
    },
  );
}

/// The bottom reserve Home hard-coded before the strip height was measured.
/// The two-source strip must exceed this, or the end-of-scroll test below is
/// asserting nothing.
const double _legacyFixedReserve = 96;

/// [_twoRoomGroupPlusTwoSolos] with the LR group idle, so Office is the ONLY
/// active source and the strip renders a single row. Same cards either way, so
/// a swap between the two changes the strip's height and nothing else.
Household _oneRoomGroupPlusTwoSolos() {
  return const Household(
    rooms: {
      'LR': RoomState(
        id: 'LR',
        name: 'Living Room',
        kind: RoomKind.speaker,
        volume: 30,
        groupId: 'G_LR',
      ),
      'KT': RoomState(
        id: 'KT',
        name: 'Kitchen',
        kind: RoomKind.speaker,
        volume: 25,
        groupId: 'G_LR',
      ),
      'OF': RoomState(
        id: 'OF',
        name: 'Office',
        kind: RoomKind.speaker,
        volume: 55,
        groupId: 'G_OF',
      ),
      'BR': RoomState(
        id: 'BR',
        name: 'Bedroom',
        kind: RoomKind.speaker,
        volume: 15,
        groupId: 'G_BR',
      ),
    },
    groups: {
      // Stopped -> NOT a source (see GroupState.hasActiveStream), but it keeps
      // the SAME track as the playing variant so the card renders identically.
      // Only the strip differs between the two fixtures, which is the whole
      // point: this models a stopped group being started, where the reserve
      // grows and nothing above it does.
      'G_LR': GroupState(
        id: 'G_LR',
        coordinatorId: 'LR',
        memberIds: ['LR', 'KT'],
        transport: PlaybackState.stopped,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
        groupVolume: 40,
      ),
      'G_OF': GroupState(
        id: 'G_OF',
        coordinatorId: 'OF',
        memberIds: ['OF'],
        transport: PlaybackState.playing,
        track: Track(title: 'Opus', artist: 'Eric Prydz'),
      ),
      'G_BR': GroupState(
        id: 'G_BR',
        coordinatorId: 'BR',
        memberIds: ['BR'],
        transport: PlaybackState.stopped,
      ),
    },
  );
}

const _emptyTopology = rust_api.Topology(speakers: [], groups: []);

const _oneRoomTopology = rust_api.Topology(
  speakers: [
    rust_api.DiscoveredSpeaker(
      id: 'OF',
      roomName: 'Office',
      ip: '10.0.0.10',
      model: 'Move 2',
    ),
  ],
  groups: [
    rust_api.DiscoveredGroup(id: 'G_OF', coordinator: 'OF', members: ['OF']),
  ],
);

class _LoadingDiscovery extends Discovery {
  final _completer = Completer<rust_api.Topology>();

  @override
  Future<rust_api.Topology> build() => _completer.future;
}

class _DataDiscovery extends Discovery {
  _DataDiscovery(this._topology);

  final rust_api.Topology _topology;

  @override
  Future<rust_api.Topology> build() async => _topology;
}

class _ErrorDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async =>
      throw rust_api.DiscoveryError.noDevicesFound();
}

/// Build [child] inside a ProviderScope seeded with [household] + a loaded
/// SharedPreferences (so the current layout resolves from the saved default),
/// the oto theme, and spy playback/grouping controllers. Uses a real
/// MaterialApp Navigator so a strip tap can push the Now Playing route.
///
/// [layout] seeds the persisted default (Cards vs Stack) via the prefs override
/// pattern (`prefs_test.dart`), initializing `currentHomeLayoutProvider`.
Future<void> _pump(
  WidgetTester t,
  Widget child, {
  Household household = const Household(),
  HouseholdNotifier Function()? householdNotifier,
  HomeLayout layout = HomeLayout.cards,
  Discovery Function()? discovery,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (layout == HomeLayout.stack) 'homeLayout': 'stack',
  });
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        discoveryProvider.overrideWith(
          discovery ?? () => _DataDiscovery(_oneRoomTopology),
        ),
        householdProvider.overrideWith(
          householdNotifier ?? () => FixtureHousehold(household),
        ),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        playbackControllerProvider.overrideWith((ref) => SpyPlayback(ref)),
        groupingControllerProvider.overrideWith((ref) => SpyGrouping(ref)),
        // Prevent the async SOAP read from hitting the Rust FFI when
        // NowPlayingScreen is pushed via the strip tap.
        positionApiProvider.overrideWithValue(const StubPositionApi()),
      ],
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: child,
      ),
    ),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

void main() {
  testWidgets(
    'initial discovery loading before cache exists shows loading state only',
    (t) async {
      await _pump(
        t,
        const HomeScreen(),
        discovery: _LoadingDiscovery.new,
        settle: false,
      );

      expect(find.byType(HomeLoadingState), findsOneWidget);
      expect(find.text('Scanning your network'), findsOneWidget);
      expect(find.byType(BottomStrip), findsNothing);
    },
  );

  testWidgets('empty discovery shows empty state', (t) async {
    await _pump(
      t,
      const HomeScreen(),
      discovery: () => _DataDiscovery(_emptyTopology),
    );

    expect(find.byType(HomeEmptyState), findsOneWidget);
    expect(find.text('No speakers yet'), findsOneWidget);
    expect(find.byType(BottomStrip), findsNothing);
  });

  testWidgets('discovery error with no cache shows error state', (t) async {
    await _pump(t, const HomeScreen(), discovery: _ErrorDiscovery.new);

    expect(find.byType(HomeErrorState), findsOneWidget);
    expect(find.text('Could not find your system'), findsOneWidget);
    expect(find.byType(BottomStrip), findsNothing);
  });

  /// Before v0.6.4 none of these no-cache states built HomeHeader (the
  /// gear's only other home) or _HomeContent (the other gear owner), so a
  /// user whose first scan failed had no way to reach theme/accent/the
  /// version string (#104). Asserted per-state (not looped in one test) so
  /// each gets its own fresh tester/ProviderScope/Navigator, matching every
  /// other test in this file.
  Future<void> expectSettingsReachable(
    WidgetTester t, {
    required Discovery Function() discovery,
    bool settle = true,
  }) async {
    await _pump(t, const HomeScreen(), discovery: discovery, settle: settle);

    expect(find.byKey(const Key('centered-state-settings')), findsOneWidget);
    await t.tap(find.byKey(const Key('centered-state-settings')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  }

  testWidgets('Settings is reachable from the initial loading state (#104)', (
    t,
  ) async {
    await expectSettingsReachable(
      t,
      discovery: _LoadingDiscovery.new,
      settle: false,
    );
  });

  testWidgets('Settings is reachable from the empty state (#104)', (
    t,
  ) async {
    await expectSettingsReachable(
      t,
      discovery: () => _DataDiscovery(_emptyTopology),
    );
  });

  testWidgets('Settings is reachable from the no-cache error state (#104)', (
    t,
  ) async {
    await expectSettingsReachable(t, discovery: _ErrorDiscovery.new);
  });

  testWidgets(
    'discovery error with cache keeps Home content and shows status banner',
    (t) async {
      await _pump(
        t,
        const HomeScreen(),
        household: _twoRoomGroupPlusTwoSolos(),
        discovery: _ErrorDiscovery.new,
      );

      expect(find.byType(HomeStatusBanner), findsOneWidget);
      expect(
        find.text('Refresh failed. Showing cached state.'),
        findsOneWidget,
      );
      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.byType(GroupCard), findsOneWidget);
      expect(find.byType(RoomCard), findsNWidgets(2));
      expect(find.byType(BottomStrip), findsOneWidget);
    },
  );

  testWidgets(
    'every room unreachable keeps Home content and offers a rescan',
    (t) async {
      // Discovery itself succeeded, so the full-screen error state never
      // fires - without the all-unreachable banner the user would be left
      // with a healthy-looking Home and no way to trigger a scan (#104).
      final offline = Household(
        rooms: {
          for (final e in _twoRoomGroupPlusTwoSolos().rooms.entries)
            e.key: e.value.copyWith(online: false),
        },
        groups: _twoRoomGroupPlusTwoSolos().groups,
      );

      await _pump(
        t,
        const HomeScreen(),
        household: offline,
        discovery: () => _DataDiscovery(_oneRoomTopology),
      );

      expect(find.byType(HomeStatusBanner), findsOneWidget);
      expect(
        find.text('No speakers are responding. Showing the last known state.'),
        findsOneWidget,
      );
      // The rescan affordance is the whole point of the state.
      expect(find.text('Retry'), findsOneWidget);
      // The cached rooms still render - last known state beats a blank screen.
      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.byType(GroupCard), findsOneWidget);
    },
  );

  testWidgets(
    'one unreachable room among several offers a rescan too (#104)',
    (t) async {
      // A partial outage doesn't qualify for HomeAllUnreachable (not every
      // room is down), but a user with one dead speaker among four still
      // needs a way to trigger a rediscover - not just the per-room mute
      // button - so HomeReady grows the same banner.
      final base = _twoRoomGroupPlusTwoSolos();
      final partial = Household(
        rooms: {
          ...base.rooms,
          'BR': base.rooms['BR']!.copyWith(online: false),
        },
        groups: base.groups,
      );

      await _pump(
        t,
        const HomeScreen(),
        household: partial,
        discovery: () => _DataDiscovery(_oneRoomTopology),
      );

      expect(find.byType(HomeStatusBanner), findsOneWidget);
      expect(find.text("Some rooms aren't responding."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(HomeHeader), findsOneWidget);
    },
  );

  testWidgets(
    'groups render as one group card, solo rooms as room cards (no dupes)',
    (t) async {
      await _pump(
        t,
        const HomeScreen(),
        household: _twoRoomGroupPlusTwoSolos(),
      );

      // Multi-member group -> exactly one merged GroupCard.
      expect(find.byType(GroupCard), findsOneWidget);
      // Two solo rooms (Office, Bedroom) -> two RoomCards.
      expect(find.byType(RoomCard), findsNWidgets(2));
      // The grouped rooms must NOT appear as standalone room cards.
      expect(
        find.widgetWithText(RoomCard, 'Living Room'),
        findsNothing,
        reason: 'a grouped room renders only inside its group card, not a card',
      );
      expect(find.widgetWithText(RoomCard, 'Kitchen'), findsNothing);
      // No RoomRows in Cards layout.
      expect(find.byType(RoomRow), findsNothing);
      // The header is composed on top.
      expect(find.byType(HomeHeader), findsOneWidget);
    },
  );

  testWidgets('Stack layout renders RoomRows + the group card (no RoomCards)', (
    t,
  ) async {
    await _pump(
      t,
      const HomeScreen(),
      household: _twoRoomGroupPlusTwoSolos(),
      layout: HomeLayout.stack,
    );

    // Multi-member group still renders ONE GroupCard in Stack layout.
    expect(find.byType(GroupCard), findsOneWidget);
    // Solo rooms render as RoomRows, not RoomCards.
    expect(find.byType(RoomRow), findsNWidgets(2));
    expect(find.byType(RoomCard), findsNothing);
    // Grouped rooms still never appear standalone.
    expect(find.widgetWithText(RoomRow, 'Living Room'), findsNothing);
    expect(find.widgetWithText(RoomRow, 'Kitchen'), findsNothing);
  });

  testWidgets('tapping a bottom-strip row pushes the Now Playing screen', (
    t,
  ) async {
    await _pump(t, const HomeScreen(), household: _twoRoomGroupPlusTwoSolos());

    // No Now Playing screen until a source is tapped.
    expect(find.byType(NowPlayingScreen), findsNothing);

    // Two active sources (LR+KT group + Office). Tap the Office strip row body.
    // "Opus" also shows on the playing Office RoomCard, so scope the finder to
    // the strip; the play button absorbs its own taps, so tapping the title
    // text (inside the row's InkWell) fires the row tap -> Now Playing.
    final stripOpus = find.descendant(
      of: find.byType(BottomStrip),
      matching: find.text('Opus'),
    );
    expect(stripOpus, findsOneWidget);
    await t.tap(stripOpus);
    await t.pumpAndSettle();

    // The real Navigator push rendered the Now Playing screen for that group.
    expect(find.byType(NowPlayingScreen), findsOneWidget);
  });

  /// The floating strip renders ONE row per active source, uncapped
  /// (`bottom_strip.dart`), so the fixed bottom reserve Home used to apply was
  /// only ever right for a single source: with two, the strip outgrew it and
  /// the last card stayed partly covered even at maximum scroll - its controls
  /// unreachable. The reserve is measured off the strip now, so the end of the
  /// list has to clear it whatever the source count.
  testWidgets('two sources: the last card clears the strip at full scroll', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    await _pump(t, const HomeScreen(), household: _twoRoomGroupPlusTwoSolos());

    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
    await t.pumpAndSettle();

    final position = t
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the body must overflow, or this test proves nothing',
    );
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'the drag must reach the very end of the list',
    );

    final strip = t.getRect(find.byType(BottomStrip));
    expect(
      strip.height,
      greaterThan(_legacyFixedReserve),
      reason:
          'two sources must push the strip past the old fixed reserve, or this '
          'is not exercising the regression',
    );

    // Groups sort by coordinator id (BR, LR, OF), so Office is last.
    expect(
      t.getRect(find.byKey(const ValueKey('OF'))).bottom,
      lessThanOrEqualTo(strip.top),
      reason: 'the last card must sit entirely above the strip at full scroll',
    );
  });

  /// Growing the reserve extends `maxScrollExtent` but leaves `pixels` at the
  /// OLD maximum - `ScrollPosition` only corrects when the offset falls out of
  /// range, and a larger extent keeps it in range. So a second source starting
  /// while the user sits at the bottom slides the last card back under the
  /// now-taller strip, and it stays there until the next scroll gesture. Home
  /// re-anchors instead.
  testWidgets('a source starting at full scroll keeps the last card clear', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    final household = MutableHousehold(_oneRoomGroupPlusTwoSolos());
    await _pump(t, const HomeScreen(), householdNotifier: () => household);

    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
    await t.pumpAndSettle();

    final position = t
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'the drag must reach the end before the transition',
    );
    final oneSourceStrip = t.getRect(find.byType(BottomStrip)).height;

    // A second source starts while the user is pinned to the bottom.
    household.replace(_twoRoomGroupPlusTwoSolos());
    await t.pumpAndSettle();

    final strip = t.getRect(find.byType(BottomStrip));
    expect(
      strip.height,
      greaterThan(oneSourceStrip),
      reason: 'the transition must actually grow the strip',
    );
    expect(
      t.getRect(find.byKey(const ValueKey('OF'))).bottom,
      lessThanOrEqualTo(strip.top),
      reason:
          'the last card must still clear the strip after it grows, without '
          'needing another scroll gesture',
    );
  });
}
