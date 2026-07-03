/// The showcase catalog: every screen x state, as a flat list of [Entry]s
/// grouped by [Entry.section]. Each entry names a fixture household plus any
/// state to force (the derived home view-state, or a static Now Playing
/// position), and a builder for the screen to render. The provider overrides
/// themselves are assembled from these fields in `showcase_app.dart` - Riverpod
/// 3's `Override` type is deliberately un-nameable, so we carry typed data here
/// and build the overrides inline where the types are inferred.
library;

import 'package:flutter/widgets.dart';

import '../src/state/home_view_state.dart';
import '../src/state/now_playing.dart';
import '../src/state/model/household.dart';
import '../src/ui/group/group_editor_screen.dart';
import '../src/ui/home/home_screen.dart';
import '../src/ui/now_playing/now_playing_screen.dart';
import '../src/ui/room/room_detail_screen.dart';
import '../src/ui/settings/settings_screen.dart';
import 'fixtures.dart';

/// One showcase item: a screen rendered against [household], optionally with a
/// forced home view-state or a static Now Playing position. [build] returns the
/// screen widget shown as the preview's `home`.
class Entry {
  const Entry({
    required this.section,
    required this.name,
    required this.household,
    required this.build,
    this.homeState,
    this.nowPlaying,
  });

  /// Left-rail grouping, e.g. "Home", "Screens".
  final String section;

  /// Display name within the section, e.g. "Ready", "Now Playing (paused)".
  final String name;

  /// Fixture backing `householdProvider` (drives every by-id child lookup).
  final Household household;

  /// When set, pins `homeViewStateProvider` so one fixture can be shown in any
  /// presentation state without staging async discovery.
  final HomeViewState? homeState;

  /// When set, pins `nowPlayingPositionProvider(groupId)` to a static position,
  /// bypassing the SOAP read + its ticker.
  final ({String groupId, NowPlayingProgress position})? nowPlaying;

  /// The screen to render as the preview's `home`.
  final Widget Function() build;
}

// Track durations kept in sync with the fixtures' tracks so the progress bar's
// max matches the duration the Now Playing header shows.
const _redboneDuration = Duration(minutes: 5, seconds: 27);
const _nightcallDuration = Duration(minutes: 4, seconds: 18);

/// The full catalog. Order here is the order shown in the rail.
final List<Entry> entries = [
  // --- Home states -----------------------------------------------------------
  Entry(
    section: 'Home',
    name: 'Loading',
    household: const Household(),
    homeState: const HomeInitialLoading(),
    build: () => const HomeScreen(),
  ),
  Entry(
    section: 'Home',
    name: 'Empty',
    household: const Household(),
    homeState: const HomeEmpty(),
    build: () => const HomeScreen(),
  ),
  Entry(
    section: 'Home',
    name: 'Error (no cache)',
    household: const Household(),
    homeState: HomeDiscoveryFailedNoCache(sampleDiscoveryError),
    build: () => const HomeScreen(),
  ),
  Entry(
    section: 'Home',
    name: 'Ready',
    household: demoHousehold,
    homeState: const HomeReady(demoHousehold),
    build: () => const HomeScreen(),
  ),
  Entry(
    section: 'Home',
    name: 'Discovering (cached)',
    household: demoHousehold,
    homeState: const HomeDiscoveringWithCache(demoHousehold),
    build: () => const HomeScreen(),
  ),
  Entry(
    section: 'Home',
    name: 'Refresh failed (cached)',
    household: demoHousehold,
    homeState: HomeDiscoveryFailedWithCache(demoHousehold, sampleDiscoveryError),
    build: () => const HomeScreen(),
  ),

  // --- Screens ---------------------------------------------------------------
  Entry(
    section: 'Screens',
    name: 'Now Playing (playing)',
    household: demoHousehold,
    nowPlaying: (
      groupId: 'g_lr',
      position: progress(const Duration(minutes: 2, seconds: 14), _redboneDuration),
    ),
    build: () => const NowPlayingScreen(groupId: 'g_lr'),
  ),
  Entry(
    section: 'Screens',
    name: 'Now Playing (paused)',
    household: demoHousehold,
    nowPlaying: (
      groupId: 'g_br',
      position: progress(const Duration(minutes: 1, seconds: 2), _nightcallDuration),
    ),
    build: () => const NowPlayingScreen(groupId: 'g_br'),
  ),
  Entry(
    section: 'Screens',
    name: 'Room detail (solo)',
    household: demoHousehold,
    build: () => const RoomDetailScreen(speakerId: 'RINCON_OF'),
  ),
  Entry(
    section: 'Screens',
    name: 'Room detail (grouped)',
    household: demoHousehold,
    build: () => const RoomDetailScreen(speakerId: 'RINCON_LR'),
  ),
  Entry(
    section: 'Screens',
    name: 'Group editor',
    household: demoHousehold,
    build: () => const GroupEditorScreen(hostId: 'RINCON_LR'),
  ),
  Entry(
    section: 'Screens',
    name: 'Settings',
    household: demoHousehold,
    build: () => const SettingsScreen(),
  ),
];
