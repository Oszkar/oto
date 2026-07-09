/// v0.6.0 end-to-end UI acceptance test. Boots the full app (`OtoApp` ->
/// `HomePage` -> `HomeScreen`) against the LAN-free dev mock seam and asserts
/// the composed Home renders, reflects a live volume mutation, follows a
/// `play()` transport change, and survives a `TopologyChanged` regroup without
/// a stale-state crash.
///
/// This is the only automated coverage that the assembled v0.6.0 UI renders
/// live against the real Dart->Rust->Dart bridge (the widget tests in `test/`
/// seed `householdProvider` with fixtures; here the household ACCUMULATES from
/// real bridge events fed by `MockWire`). It mirrors the boot/seam/polling
/// mechanics of `v0_4_events_test.dart`.
///
/// Run on a connected Windows desktop:
///
/// ```text
/// cd app && flutter test integration_test/v0_6_0_ui_test.dart -d windows
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/rust/frb_generated.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/ui/home/bottom_strip.dart';
import 'package:oto/src/ui/home/group_card.dart';
import 'package:oto/src/ui/home/room_card.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';
import 'package:oto/src/ui/shell/oto_app.dart';

// MockWire fixture (native/crates/mock): 3 speakers / 2 groups.
//   - RINCON_KITCHEN ("Kitchen") + RINCON_DINING ("Dining") -> group
//     RINCON_KITCHEN:1 (multi-room, coordinator Kitchen).
//   - RINCON_OFFICE ("Office") -> group RINCON_OFFICE:0 (solo).
// Every speaker seeds at SEED_VOLUME = 30; both groups seed Stopped.
const _kitchenSpeaker = 'RINCON_KITCHEN';
const _kitchenGroup = 'RINCON_KITCHEN:1';
const _seedVolume = 30;

/// A [Discovery] whose `build()` drives discovery via the dev MockWire seam
/// (`devDiscoverMock`) instead of a real LAN `discover()`. This installs the
/// MockWire as the held Rust wire, so the unified change-event stream
/// (`changeEventsProvider`) subscribes against it and the seed + mutation
/// events flow through the REAL bridge into the accumulating `householdProvider`
/// - the whole point of this end-to-end test.
///
/// `refreshTopology()` is left as the base implementation: it calls
/// `rust_api.refreshTopology()`, which the MockWire honours (re-pull snapshot +
/// fresh seeded wire), so the topology-follow path exercises real Rust too.
class _MockDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() => rust_api.devDiscoverMock();
}

/// Wait for `condition()` to become true, polling each event-loop turn. Mirrors
/// `_waitFor` in `v0_4_events_test.dart`: when the Rust side emits an event the
/// test resumes promptly instead of sleeping a fixed interval. Pumps the widget
/// tree each turn so provider rebuilds settle into the rendered frame.
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? message,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(message ?? 'condition never became true within $timeout');
    }
    // Pump a short interval so the Rust->Dart sink.add has a chance to push,
    // the provider graph rebuilds, and the new frame is laid out.
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Boot the full app against the mock seam. Overrides `discoveryProvider` to
/// drive the MockWire, and `prefsRepositoryProvider` with a loaded
/// SharedPreferences (OtoApp -> settingsProvider needs it or it throws).
Future<void> _bootApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoveryProvider.overrideWith(_MockDiscovery.new),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
      ],
      child: const OtoApp(),
    ),
  );
}

/// Read the rendered value of the first [OtoSlider] under [ancestor]. The
/// slider is normalized 0..1; callers compare against `volume / 100`.
double _sliderValueIn(WidgetTester tester, Finder ancestor) {
  final slider = tester.widget<OtoSlider>(
    find.descendant(of: ancestor, matching: find.byType(OtoSlider)).first,
  );
  return slider.value;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets(
    'v0.6.0 end-to-end: composed Home renders, follows volume + play + regroup',
    (tester) async {
      await _bootApp(tester);

      // ── Discovery + seed settle ──────────────────────────────────────────
      // Discovery resolves (devDiscoverMock installs the mock wire), the event
      // stream subscribes, and the seed drains (3 Volume + 3 Mute + 2 Playback)
      // into the accumulating household. Wait until the household has the full
      // 3-speaker / 2-group skeleton AND Kitchen's seed volume (30) has landed.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OtoApp)),
      );
      await _waitFor(
        tester,
        () {
          final h = container.read(householdProvider);
          return h.rooms.length == 3 &&
              h.groups.length == 2 &&
              h.rooms[_kitchenSpeaker]?.volume == _seedVolume;
        },
        message: 'discovery + seed never populated the household',
      );
      await tester.pumpAndSettle();

      // ── Composed body (no dupes) ─────────────────────────────────────────
      // The multi-room Kitchen+Dining group renders ONE merged GroupCard; the
      // solo Office renders ONE RoomCard. The grouped rooms (Kitchen, Dining)
      // must NOT also appear as standalone room cards.
      expect(
        find.byType(GroupCard),
        findsOneWidget,
        reason: 'the multi-room group renders exactly one merged card',
      );
      expect(
        find.byType(RoomCard),
        findsOneWidget,
        reason: 'the lone solo room (Office) renders exactly one room card',
      );
      expect(
        find.widgetWithText(RoomCard, 'Kitchen'),
        findsNothing,
        reason: 'a grouped room appears only inside its group card, never as a '
            'standalone card',
      );
      expect(find.widgetWithText(RoomCard, 'Dining'), findsNothing);
      expect(
        find.widgetWithText(RoomCard, 'Office'),
        findsOneWidget,
        reason: 'the solo Office room card is present',
      );

      // ── Volume mutation -> slider reflects it ────────────────────────────
      // Kitchen is a grouped room, so its per-room level slider lives inside
      // the GroupCard. Drive a setVolume; the mock auto-emits a Volume event
      // that accumulates, and the rendered group card slider must move to N/100.
      const newVolume = 77;
      final officeCard = find.widgetWithText(RoomCard, 'Office');
      final officeSeed = _sliderValueIn(tester, officeCard);
      expect(
        officeSeed,
        closeTo(_seedVolume / 100, 0.001),
        reason: 'Office room card seeds at SEED_VOLUME / 100',
      );

      await rust_api.setVolume(speakerId: _kitchenSpeaker, volume: newVolume);
      await _waitFor(
        tester,
        () => container.read(householdProvider).rooms[_kitchenSpeaker]?.volume ==
            newVolume,
        message: 'setVolume did not propagate to the household',
      );
      await tester.pumpAndSettle();

      // Kitchen's per-room slider is the one inside the group card whose value
      // is now newVolume/100. Assert at least one OtoSlider in the group card
      // renders the new value (the group also has a master + Dining level).
      final groupCard = find.byType(GroupCard);
      final groupSliders = tester
          .widgetList<OtoSlider>(
            find.descendant(of: groupCard, matching: find.byType(OtoSlider)),
          )
          .map((s) => s.value)
          .toList();
      expect(
        groupSliders,
        contains(closeTo(newVolume / 100, 0.001)),
        reason: 'the Kitchen per-room slider must reflect the new volume',
      );

      // ── play(group) -> transport flips, BottomStrip shows the source ─────
      // Both groups seed Stopped, so no source is active and the strip is empty
      // initially. Playing the Kitchen group makes it a source; the strip then
      // renders a row with a play/pause button keyed by the group id.
      expect(
        find.byType(BottomStrip),
        findsOneWidget,
        reason: 'BottomStrip is always composed (renders empty when no source)',
      );
      expect(
        find.byKey(const Key('strip-play-$_kitchenGroup')),
        findsNothing,
        reason: 'no source yet -> the strip has no play button',
      );

      await rust_api.play(groupId: _kitchenGroup);
      // The mock auto-emits a per-GROUP Playback(Playing) event; the household
      // folds it (transport -> playing), the group becomes a source, and the
      // strip renders a row keyed by the group id. Wait on the rendered button.
      await _waitFor(
        tester,
        () => find
            .byKey(const Key('strip-play-$_kitchenGroup'))
            .evaluate()
            .isNotEmpty,
        message: 'play(group) did not surface the source in the BottomStrip',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('strip-play-$_kitchenGroup')),
        findsOneWidget,
        reason: 'the now-playing Kitchen group is a source in the strip',
      );

      // ── TopologyChanged -> regroup followed, no stale-state crash ────────
      // Push a topology change; the watched topologyController debounces
      // (250 ms) then fast re-pulls via the mock. The tree must keep rendering
      // (HomePage activated the controller) and no exception may be thrown.
      await rust_api.devPushTopologyChangeOnMock();
      // Past the 250 ms debounce + the re-pull + settle.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // The household still has the 3-speaker / 2-group skeleton (the mock
      // re-pull returns the same fixture) and the tree still renders.
      final afterRegroup = container.read(householdProvider);
      expect(afterRegroup.rooms.length, 3);
      expect(afterRegroup.groups.length, 2);
      expect(
        find.byType(GroupCard),
        findsOneWidget,
        reason: 'the regroup was followed without a stale-state crash',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
