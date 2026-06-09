import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';

void main() {
  test('defaults then round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = PrefsRepository(await SharedPreferences.getInstance());
    expect(repo.themeMode, ThemeMode.system);
    expect(repo.accent, Accent.teal);
    expect(repo.homeLayout, HomeLayout.cards);
    await repo.setAccent(Accent.amber);
    await repo.setHomeLayout(HomeLayout.stack);
    final repo2 = PrefsRepository(await SharedPreferences.getInstance());
    expect(repo2.accent, Accent.amber);
    expect(repo2.homeLayout, HomeLayout.stack);
  });

  test('SettingsNotifier restores defaults from prefs and persists on set', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
    ]);
    addTearDown(container.dispose);

    // restores defaults
    expect(container.read(settingsProvider).accent, Accent.teal);
    expect(container.read(settingsProvider).mode, ThemeMode.system);
    expect(container.read(settingsProvider).layout, HomeLayout.cards);

    // setter updates state AND persists
    await container.read(settingsProvider.notifier).setAccent(Accent.indigo);
    expect(container.read(settingsProvider).accent, Accent.indigo);
    expect(PrefsRepository(prefs).accent, Accent.indigo, reason: 'persisted to prefs');

    await container.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
    await container.read(settingsProvider.notifier).setHomeLayout(HomeLayout.stack);
    expect(container.read(settingsProvider).mode, ThemeMode.dark);
    expect(container.read(settingsProvider).layout, HomeLayout.stack);
  });

  test('unknown/legacy stored accent falls back to teal (does not throw)', () async {
    SharedPreferences.setMockInitialValues({'accent': 'crimson'});
    final repo = PrefsRepository(await SharedPreferences.getInstance());
    expect(repo.accent, Accent.teal);
  });
}
