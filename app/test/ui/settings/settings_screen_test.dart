import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/app_info.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/settings/about_section.dart';
import 'package:oto/src/ui/settings/device_list.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/_fixtures.dart';

Future<SharedPreferences> _pumpSettings(
  WidgetTester t, {
  Household? household,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fixture = household ?? mixedHousehold();
  final rooms = Map.of(fixture.rooms);
  if (rooms.containsKey('OF')) {
    rooms['OF'] = rooms['OF']!.copyWith(model: 'Move 2');
  }
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        householdProvider.overrideWith(
          () => FixtureHousehold(fixture.copyWith(rooms: rooms)),
        ),
      ],
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: const SettingsScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return prefs;
}

String _pubspecBaseVersion() {
  final versionLine = File(
    'pubspec.yaml',
  ).readAsLinesSync().firstWhere((line) => line.startsWith('version:'));
  return versionLine.split(':').last.trim().split('+').first;
}

void main() {
  testWidgets('renders Settings sections', (t) async {
    await _pumpSettings(t);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byKey(const Key('settings-back')), findsOneWidget);
    expect(find.byType(DeviceList), findsOneWidget);
    expect(find.byType(AboutSection), findsOneWidget);
  });

  testWidgets('theme, accent, and layout controls persist choices', (t) async {
    final prefs = await _pumpSettings(t);
    await t.tap(find.byKey(const Key('settings-theme-dark')));
    await t.tap(find.byKey(const Key('settings-accent-amber')));
    await t.tap(find.byKey(const Key('settings-layout-stack')));
    await t.pumpAndSettle();
    final repo = PrefsRepository(prefs);
    expect(repo.themeMode, ThemeMode.dark);
    expect(repo.accent, Accent.amber);
    expect(repo.homeLayout, HomeLayout.stack);
  });

  testWidgets('devices list shows rooms, models, grouping, and offline state', (
    t,
  ) async {
    await _pumpSettings(t);

    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Move 2'), findsOneWidget);
    expect(find.text('Bedroom'), findsOneWidget);
    expect(find.text('Patio'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Standalone'), findsNWidgets(2));
  });

  testWidgets('devices list shows grouped room count', (t) async {
    await _pumpSettings(t, household: groupEditHousehold());

    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('2 rooms'), findsNWidgets(2));
  });

  testWidgets('about section shows local-first identity and version', (
    t,
  ) async {
    await _pumpSettings(t);

    expect(find.text('oto'), findsOneWidget);
    expect(find.text(AppInfo.version), findsOneWidget);
    expect(find.text('Version ${AppInfo.version}'), findsNothing);
    expect(find.textContaining('local network'), findsOneWidget);
    expect(find.textContaining('Not affiliated with Sonos'), findsOneWidget);
  });

  test('AppInfo version stays aligned with pubspec base version', () {
    expect(AppInfo.version, _pubspecBaseVersion());
  });
}
