import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/settings/about_section.dart';
import 'package:oto/src/ui/settings/device_list.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/_fixtures.dart';

Future<SharedPreferences> _pumpSettings(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        householdProvider.overrideWith(
          () => FixtureHousehold(mixedHousehold()),
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
}
