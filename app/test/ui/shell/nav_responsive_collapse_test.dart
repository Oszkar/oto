// Wide-mode panes (Settings, Group editor) open as a centered Dialog via
// `_showPaneDialog`. `checkResponsivePop` already handles the phone routes
// collapsing INTO the pane when the window widens; this covers the reverse -
// the dialog collapsing into the full-screen phone route when the window
// narrows while it's open.
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
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/home/home_screen.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';

import '../home/_fixtures.dart';

Household _oneRoomHousehold() {
  return const Household(
    rooms: {
      'LR': RoomState(
        id: 'LR',
        name: 'Living Room',
        kind: RoomKind.speaker,
        volume: 20,
        groupId: 'G_LR',
      ),
    },
    groups: {
      'G_LR': GroupState(
        id: 'G_LR',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.stopped,
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

Future<void> _pumpDesktop(WidgetTester tester) async {
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
          () => FixtureHousehold(_oneRoomHousehold()),
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
}

void main() {
  testWidgets(
    'Settings dialog collapses into the full-screen route when the window narrows',
    (tester) async {
      await _pumpDesktop(tester);

      await tester.tap(find.byKey(const Key('rail-settings')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();

      expect(
        find.byType(Dialog),
        findsNothing,
        reason: 'the wide-mode dialog must dismiss once the tier goes narrow',
      );
      expect(
        find.byType(SettingsScreen),
        findsOneWidget,
        reason: 'and hand off to the full-screen phone route in its place',
      );
      // The content survives the swap, not just an empty route.
      expect(find.text('Settings'), findsOneWidget);
    },
  );
}
