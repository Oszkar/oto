// Composition tests for the assembled HomeScreen (Task 11b).
//
// HomeScreen is the integration point: it watches `settingsProvider` for the
// layout and `householdProvider` for the body, then composes HomeHeader + the
// group/solo body + BottomStrip, wiring strip taps to the Now Playing route.
//
// The load-bearing invariant under test is the spec §6 composition rule: every
// room belongs to a group, so we iterate `household.groups` and a multi-member
// group renders ONE GroupCard while a single-member group renders a RoomCard
// (Cards) / RoomRow (Stack). A grouped room therefore NEVER appears as a
// standalone card -- no duplicates.
//
// This test owns its own `_wrap`/`_settle` helpers (rather than the leaf-widget
// `_fixtures.wrap`) because HomeScreen pulls in HomeHeader, which watches
// `settingsProvider`; that needs `prefsRepositoryProvider` overridden with a
// loaded SharedPreferences, and a real Navigator (not a bare Scaffold) so the
// strip tap can push the Now Playing route.
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
/// SharedPreferences (so `settingsProvider` resolves for the header/layout),
/// the oto theme, and spy playback/grouping controllers. Uses a real
/// MaterialApp Navigator so a strip tap can push the Now Playing route.
///
/// [layout] seeds the persisted home layout (Cards vs Stack) via the prefs
/// override pattern (`prefs_test.dart`), driving `settingsProvider.layout`.
Future<void> _pump(
  WidgetTester t,
  Widget child, {
  Household household = const Household(),
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
        householdProvider.overrideWith(() => FixtureHousehold(household)),
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
}
