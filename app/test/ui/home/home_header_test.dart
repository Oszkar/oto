import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/home/home_header.dart';
import 'package:oto/src/ui/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_fixtures.dart';

/// Pump the header with a seeded household and a real (mock-backed)
/// [settingsProvider] so the current layout starts from the persisted default.
Future<SharedPreferences> _pumpHeader(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({'homeLayout': 'cards'});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        householdProvider.overrideWith(
          () => FixtureHousehold(mixedHousehold()),
        ),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
      ],
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: const Scaffold(body: HomeHeader()),
      ),
    ),
  );
  return prefs;
}

void main() {
  testWidgets('subtitle reads "N rooms · M playing" for the fixture', (
    t,
  ) async {
    await _pumpHeader(t);
    // mixedHousehold: 3 rooms, only G_OF hasActiveStream.
    expect(find.text('3 rooms · 1 playing'), findsOneWidget);
    expect(find.text('Speakers'), findsOneWidget);
  });

  testWidgets('tapping Stack changes only the current layout', (t) async {
    final prefs = await _pumpHeader(t);
    expect(PrefsRepository(prefs).homeLayout, HomeLayout.cards);

    await t.tap(find.byKey(const Key('layout-toggle-stack')));
    await t.pumpAndSettle();

    final container = ProviderScope.containerOf(
      t.element(find.byType(HomeHeader)),
    );
    expect(container.read(currentHomeLayoutProvider), HomeLayout.stack);
    expect(
      PrefsRepository(prefs).homeLayout,
      HomeLayout.cards,
      reason: 'the Home toggle must not replace the persisted default',
    );
  });

  testWidgets('there is no search icon', (t) async {
    await _pumpHeader(t);
    expect(find.byKey(const Key('header-search')), findsNothing);
  });

  testWidgets('icon-only controls expose accessible labels', (t) async {
    final semantics = t.ensureSemantics();
    try {
      await _pumpHeader(t);

      expect(find.bySemanticsLabel('Cards layout'), findsWidgets);
      expect(find.bySemanticsLabel('Stack layout'), findsWidgets);
      expect(find.bySemanticsLabel('Open settings'), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tapping the gear pushes the Settings route', (t) async {
    await _pumpHeader(t);
    await t.tap(find.byKey(const Key('header-settings')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
