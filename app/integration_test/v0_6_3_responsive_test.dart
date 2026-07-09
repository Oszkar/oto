/// v0.6.3 end-to-end wide-layout acceptance test. Boots the full app
/// (`OtoApp` -> `HomePage` -> `HomeScreen`) at a desktop width against the
/// LAN-free dev mock seam and asserts the wide three-pane shell renders and
/// follows real bridge state: the persistent `NowPlayingPane` (no floating
/// `BottomStrip`), the desktop `OtoNavRail`, playing a group filling the
/// pane, select-in-place on a group card, and the Settings dialog opening
/// from the rail. Mirrors the boot/seam/polling mechanics of
/// `v0_6_0_ui_test.dart`; standalone (integration tests do not import each
/// other), so the mock/boot/wait helpers are copied rather than shared.
///
/// Run on a connected Windows desktop:
///
/// ```text
/// cd app && flutter test integration_test/v0_6_3_responsive_test.dart -d windows
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
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/state/selected_source.dart';
import 'package:oto/src/ui/home/bottom_strip.dart';
import 'package:oto/src/ui/home/group_card.dart';
import 'package:oto/src/ui/now_playing/now_playing_pane.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';
import 'package:oto/src/ui/shell/oto_app.dart';
import 'package:oto/src/ui/shell/oto_nav_rail.dart';
import 'package:oto/src/ui/widgets/album_art.dart';

// MockWire fixture (native/crates/mock): 3 speakers / 2 groups.
//   - RINCON_KITCHEN ("Kitchen") + RINCON_DINING ("Dining") -> group
//     RINCON_KITCHEN:1 (multi-room, coordinator Kitchen).
//   - RINCON_OFFICE ("Office") -> group RINCON_OFFICE:0 (solo).
// Every speaker seeds at SEED_VOLUME = 30; both groups seed Stopped.
const _kitchenGroup = 'RINCON_KITCHEN:1';

/// A [Discovery] whose `build()` drives discovery via the dev MockWire seam
/// (`devDiscoverMock`) instead of a real LAN `discover()`. This installs the
/// MockWire as the held Rust wire, so the unified change-event stream
/// (`changeEventsProvider`) subscribes against it and the seed events flow
/// through the REAL bridge into the accumulating `householdProvider`.
class _MockDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() => rust_api.devDiscoverMock();
}

/// Wait for `condition()` to become true, polling each event-loop turn.
/// Mirrors `_waitFor` in `v0_6_0_ui_test.dart`: when the Rust side emits an
/// event the test resumes promptly instead of sleeping a fixed interval.
/// Pumps the widget tree each turn so provider rebuilds settle into the
/// rendered frame.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets(
    'v0.6.3 end-to-end: wide three-pane shell renders and follows play + select + settings',
    (tester) async {
      // Force a desktop width BEFORE booting so `context.isWide` /
      // `context.isDesktop` see it from the very first frame (1280 >= 1200 =
      // desktop tier).
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _bootApp(tester);

      // ── Discovery + seed settle ──────────────────────────────────────────
      // Discovery resolves (devDiscoverMock installs the mock wire), the event
      // stream subscribes, and the seed drains into the accumulating
      // household. Wait until the household has the full 3-speaker / 2-group
      // skeleton.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OtoApp)),
      );
      await _waitFor(
        tester,
        () {
          final h = container.read(householdProvider);
          return h.rooms.length == 3 && h.groups.length == 2;
        },
        message: 'discovery + seed never populated the household',
      );
      await tester.pumpAndSettle();

      // ── Wide three-pane shell ────────────────────────────────────────────
      expect(
        find.byType(NowPlayingPane),
        findsOneWidget,
        reason: 'wide replaces the floating strip with a persistent detail pane',
      );
      expect(
        find.byType(BottomStrip),
        findsNothing,
        reason: 'wide suppresses the phone floating strip entirely',
      );
      expect(
        find.byType(OtoNavRail),
        findsOneWidget,
        reason: 'desktop (>=1200) shows the leading nav rail',
      );
      // Both groups seed Stopped, so there is no active source and the pane
      // falls back to its empty placeholder.
      expect(
        find.text('Pick a room to control'),
        findsOneWidget,
        reason: 'no active source yet -> the pane shows its empty placeholder',
      );

      // ── play(group) -> the pane fills ────────────────────────────────────
      // `resolvedSourceProvider` defaults to the first active source, so
      // playing the Kitchen group makes the pane render its NowPlayingBody.
      await rust_api.play(groupId: _kitchenGroup);
      await _waitFor(
        tester,
        () =>
            container.read(householdProvider).groups[_kitchenGroup]?.transport ==
            PlaybackState.playing,
        message: 'play(group) did not propagate to the household',
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(NowPlayingBody),
        findsOneWidget,
        reason: 'the active Kitchen group resolves into the detail pane',
      );
      expect(
        find.text('Pick a room to control'),
        findsNothing,
        reason: 'the placeholder is gone once a source is active',
      );

      // ── Select-in-place ───────────────────────────────────────────────────
      // Tap the group card body (the header album art is inside the outer
      // select-on-wide GestureDetector and absorbs no taps of its own).
      await tester.tap(
        find.descendant(of: find.byType(GroupCard), matching: find.byType(AlbumArt)),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(selectedSourceProvider).pinned,
        isTrue,
        reason: 'tapping the group card body pins an explicit selection',
      );
      expect(
        container.read(resolvedSourceProvider),
        _kitchenGroup,
        reason: 'the pinned selection resolves into the detail pane',
      );

      // ── Settings dialog from the rail ────────────────────────────────────
      await tester.tap(find.byKey(const Key('rail-settings')));
      await tester.pumpAndSettle();

      expect(
        find.byType(SettingsBody),
        findsOneWidget,
        reason: 'openSettings renders the chrome-free Settings body',
      );
      expect(
        find.byType(Dialog),
        findsOneWidget,
        reason: 'wide opens Settings as a centered dialog, not a pushed route',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
