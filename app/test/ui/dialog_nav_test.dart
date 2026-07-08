// Task 7: on WIDE layouts, Settings and the Group editor open as centered
// dialogs hosting the chrome-free `*Body`; on phone they push the full-screen
// `*Screen` route. The tier is read from `MediaQuery.sizeOf`, so these tests
// force the view size (mirroring wide_home_test) before pumping so
// `context.isWide` sees it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/group/group_editor_screen.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';
import 'package:oto/src/ui/shell/nav.dart';

import 'home/_fixtures.dart';

/// Pump a host page with two buttons that call the nav helpers with their own
/// context, at [size], inside a ProviderScope seeded with [household], loaded
/// SharedPreferences (for Settings), and spy controllers.
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
        householdProvider.overrideWith(() => FixtureHousehold(household)),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        playbackControllerProvider.overrideWith((ref) => SpyPlayback(ref)),
        groupingControllerProvider.overrideWith((ref) => SpyGrouping(ref)),
        positionApiProvider.overrideWithValue(const StubPositionApi()),
      ],
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  key: const Key('open-settings'),
                  onPressed: () => openSettings(context),
                  child: const Text('settings'),
                ),
                ElevatedButton(
                  key: const Key('open-group-editor'),
                  onPressed: () => openGroupEditor(context, 'LR'),
                  child: const Text('group'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: openSettings shows a Dialog hosting SettingsBody', (
    tester,
  ) async {
    await _pump(
      tester,
      household: groupEditHousehold(),
      size: const Size(1280, 800),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(SettingsBody), findsOneWidget);
    // No full-screen route: the dialog hosts the body directly.
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('wide: openGroupEditor shows a Dialog hosting GroupEditorBody', (
    tester,
  ) async {
    await _pump(
      tester,
      household: groupEditHousehold(),
      size: const Size(1280, 800),
    );

    await tester.tap(find.byKey(const Key('open-group-editor')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(GroupEditorBody), findsOneWidget);
    expect(find.byType(GroupEditorScreen), findsNothing);

    // Save pops the hosting dialog cleanly ("save then close").
    await tester.tap(find.byKey(const Key('group-save')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(GroupEditorBody), findsNothing);
  });

  testWidgets('wide: the Settings dialog close control dismisses it', (
    tester,
  ) async {
    await _pump(
      tester,
      household: groupEditHousehold(),
      size: const Size(1280, 800),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('phone: openSettings pushes the SettingsScreen route', (
    tester,
  ) async {
    await _pump(
      tester,
      household: groupEditHousehold(),
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('phone: openGroupEditor pushes the GroupEditorScreen route', (
    tester,
  ) async {
    await _pump(
      tester,
      household: groupEditHousehold(),
      size: const Size(390, 844),
    );

    await tester.tap(find.byKey(const Key('open-group-editor')));
    await tester.pumpAndSettle();

    expect(find.byType(GroupEditorScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
