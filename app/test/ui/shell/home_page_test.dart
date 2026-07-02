// Shell wiring: HomePage must ACTIVATE the topology-follow controller.
//
// `topologyControllerProvider` is a keep-alive side-effect provider that does
// nothing until something watches it. The topology_controller_test exercises it
// after MANUAL activation; this test proves the shell (`HomePage`) is what
// activates it in the real app, so a regroup refreshes Home without a manual
// re-discover.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/state/topology.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/shell/home_page.dart';

import '../home/_fixtures.dart';

class _EmptyDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async =>
      const rust_api.Topology(speakers: [], groups: []);
}

void main() {
  testWidgets('HomePage activates the otherwise-dormant topology controller', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        discoveryProvider.overrideWith(_EmptyDiscovery.new),
        householdProvider.overrideWith(
          () => FixtureHousehold(const Household()),
        ),
        // topologyController listens to changeEvents; stub it so activation
        // doesn't reach currentWireGeneration()'s FFI in a unit test.
        changeEventsProvider.overrideWith(
          (ref) => const Stream<rust_api.ChangeEventDto>.empty(),
        ),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        playbackControllerProvider.overrideWith((ref) => SpyPlayback(ref)),
        groupingControllerProvider.overrideWith((ref) => SpyGrouping(ref)),
        positionApiProvider.overrideWithValue(const StubPositionApi()),
      ],
    );
    addTearDown(container.dispose);

    // Dormant before the shell mounts.
    expect(
      container.exists(topologyControllerProvider),
      isFalse,
      reason: 'the controller is inert until something watches it',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: otoTheme(Brightness.light, Accent.teal),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pump();

    expect(
      container.exists(topologyControllerProvider),
      isTrue,
      reason:
          'HomePage.build watches topologyControllerProvider, activating the '
          'topology-follow controller for the app lifetime',
    );
  });
}
