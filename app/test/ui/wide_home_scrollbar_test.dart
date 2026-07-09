// Regression: a Scrollbar with no explicit controller falls back to
// PrimaryScrollController, but a ScrollView only auto-attaches to that
// shared controller on mobile platforms - on desktop the Scrollbar finds a
// controller with no attached ScrollPosition and throws "The Scrollbar's
// ScrollController has no ScrollPosition attached" the moment it's
// interacted with. Home's own list and the wide NowPlayingPane are mounted
// simultaneously, so both scrollables need their own explicit controller
// (see home_screen.dart / now_playing_screen.dart) rather than relying on
// PrimaryScrollController.
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
import 'package:oto/src/ui/home/home_screen.dart';
import 'package:oto/src/ui/now_playing/now_playing_pane.dart';

import 'home/_fixtures.dart';

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
    },
    groups: {
      'G_LR': GroupState(
        id: 'G_LR',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.playing,
        track: Track(title: 'Strobe', artist: 'Deadmau5'),
      ),
    },
  );
}

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
  @override
  Future<rust_api.Topology> build() async => _topology;
}

/// The [ScrollController] a scrollable widget (`SingleChildScrollView` or
/// `ListView`) was built with, however it exposes it.
ScrollController? _controllerOf(Widget widget) => switch (widget) {
  SingleChildScrollView() => widget.controller,
  ListView() => widget.controller,
  _ => throw ArgumentError('not a scrollable this helper knows: $widget'),
};

void main() {
  testWidgets(
    'Home list and the wide NowPlayingPane each own their scrollbar controller',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
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
            discoveryProvider.overrideWith(_DataDiscovery.new),
            householdProvider.overrideWith(
              () => FixtureHousehold(_activeGroupHousehold()),
            ),
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

      // Both scrollables are mounted at once at this width: Home's own list
      // and the persistent detail pane's NowPlayingBody.
      expect(find.byType(NowPlayingPane), findsOneWidget);

      final scrollbars = tester.widgetList<Scrollbar>(find.byType(Scrollbar));
      final scrollViews = tester.widgetList<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollbars.length, 2, reason: 'Home body + NowPlayingBody');
      expect(scrollViews.length, 2);

      final scrollbarControllers = scrollbars.map((s) => s.controller).toSet();
      final scrollViewControllers = scrollViews.map(_controllerOf).toSet();

      expect(
        scrollbarControllers,
        isNot(contains(null)),
        reason:
            'every Scrollbar must own an explicit controller instead of '
            'falling back to PrimaryScrollController',
      );
      expect(
        scrollbarControllers.length,
        2,
        reason: 'each scrollable must have its OWN controller, not share one',
      );
      expect(
        scrollbarControllers,
        scrollViewControllers,
        reason:
            'each Scrollbar must be wired to the SAME controller instance '
            'as the scrollable it wraps',
      );
    },
  );
}
