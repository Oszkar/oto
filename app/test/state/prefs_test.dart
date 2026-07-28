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

  test(
    'SettingsNotifier restores defaults from prefs and persists on set',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        ],
      );
      addTearDown(container.dispose);

      // restores defaults
      expect(container.read(settingsProvider).accent, Accent.teal);
      expect(container.read(settingsProvider).mode, ThemeMode.system);
      expect(container.read(settingsProvider).layout, HomeLayout.cards);

      // setter updates state AND persists
      await container.read(settingsProvider.notifier).setAccent(Accent.indigo);
      expect(container.read(settingsProvider).accent, Accent.indigo);
      expect(
        PrefsRepository(prefs).accent,
        Accent.indigo,
        reason: 'persisted to prefs',
      );

      await container
          .read(settingsProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await container
          .read(settingsProvider.notifier)
          .setHomeLayout(HomeLayout.stack);
      expect(container.read(settingsProvider).mode, ThemeMode.dark);
      expect(container.read(settingsProvider).layout, HomeLayout.stack);
    },
  );

  test('current Home layout changes without changing the default', () async {
    SharedPreferences.setMockInitialValues({'homeLayout': 'cards'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(currentHomeLayoutProvider), HomeLayout.cards);

    container
        .read(currentHomeLayoutProvider.notifier)
        .setLayout(HomeLayout.stack);

    expect(container.read(currentHomeLayoutProvider), HomeLayout.stack);
    expect(
      PrefsRepository(prefs).homeLayout,
      HomeLayout.cards,
      reason: 'the Home toggle is session-only',
    );
  });

  test('default applies on the next provider session only', () async {
    SharedPreferences.setMockInitialValues({'homeLayout': 'cards'});
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);
    final currentSession = ProviderContainer(
      overrides: [prefsRepositoryProvider.overrideWithValue(repo)],
    );

    expect(currentSession.read(currentHomeLayoutProvider), HomeLayout.cards);

    await currentSession
        .read(settingsProvider.notifier)
        .setHomeLayout(HomeLayout.stack);

    expect(repo.homeLayout, HomeLayout.stack);
    expect(
      currentSession.read(currentHomeLayoutProvider),
      HomeLayout.cards,
      reason: 'changing the default does not change the current session',
    );
    currentSession.dispose();

    final nextSession = ProviderContainer(
      overrides: [prefsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(nextSession.dispose);
    expect(nextSession.read(currentHomeLayoutProvider), HomeLayout.stack);
  });

  test(
    'unknown/legacy stored accent falls back to teal (does not throw)',
    () async {
      SharedPreferences.setMockInitialValues({'accent': 'crimson'});
      final repo = PrefsRepository(await SharedPreferences.getInstance());
      expect(repo.accent, Accent.teal);
    },
  );

  test('unknown/legacy stored themeMode falls back to system', () async {
    SharedPreferences.setMockInitialValues({'themeMode': 'sepia'});
    final repo = PrefsRepository(await SharedPreferences.getInstance());
    expect(repo.themeMode, ThemeMode.system);
  });

  test('unknown/legacy stored homeLayout falls back to cards', () async {
    SharedPreferences.setMockInitialValues({'homeLayout': 'mosaic'});
    final repo = PrefsRepository(await SharedPreferences.getInstance());
    expect(repo.homeLayout, HomeLayout.cards);
  });
}
