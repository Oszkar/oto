import 'package:flutter/material.dart' show ThemeMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/accent.dart';

part 'prefs.g.dart';

/// Home body layout preference.
enum HomeLayout { cards, stack }

/// Typed wrapper over [SharedPreferences] for oto's three persisted settings.
/// Defaults: system theme, teal accent, card layout.
class PrefsRepository {
  PrefsRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _kThemeMode = 'themeMode';
  static const _kAccent = 'accent';
  static const _kHomeLayout = 'homeLayout';

  ThemeMode get themeMode => switch (_prefs.getString(_kThemeMode)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  Future<void> setThemeMode(ThemeMode m) =>
      _prefs.setString(_kThemeMode, m.name);

  Accent get accent {
    final name = _prefs.getString(_kAccent);
    // Accent.values.byName throws on an unknown/legacy value; fall back to teal.
    return Accent.values.firstWhere(
      (a) => a.name == name,
      orElse: () => Accent.teal,
    );
  }

  Future<void> setAccent(Accent a) => _prefs.setString(_kAccent, a.name);

  HomeLayout get homeLayout => _prefs.getString(_kHomeLayout) == 'stack'
      ? HomeLayout.stack
      : HomeLayout.cards;
  Future<void> setHomeLayout(HomeLayout l) =>
      _prefs.setString(_kHomeLayout, l.name);
}

/// Holds the loaded [PrefsRepository]. Declared as a throw-until-overridden
/// provider: `main()` loads `SharedPreferences` once (async) and overrides this
/// with `overrideWithValue(PrefsRepository(prefs))` before `runApp`. Keeping it
/// synchronous here lets [SettingsNotifier] return a plain record (no AsyncValue)
/// -- the standard Riverpod + shared_preferences pattern. (The Task 7 shell wires
/// the override; tests override it directly.)
@Riverpod(keepAlive: true)
PrefsRepository prefsRepository(Ref ref) => throw UnimplementedError(
  'Override prefsRepositoryProvider in main() with a loaded SharedPreferences.',
);

/// Current persisted settings. Restores from the repo on build; every setter
/// writes through to the repo AND updates state so the UI reacts immediately.
@Riverpod(keepAlive: true)
class SettingsNotifier extends _$SettingsNotifier {
  @override
  ({ThemeMode mode, Accent accent, HomeLayout layout}) build() {
    final repo = ref.watch(prefsRepositoryProvider);
    return (mode: repo.themeMode, accent: repo.accent, layout: repo.homeLayout);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    await ref.read(prefsRepositoryProvider).setThemeMode(m);
    state = (mode: m, accent: state.accent, layout: state.layout);
  }

  Future<void> setAccent(Accent a) async {
    await ref.read(prefsRepositoryProvider).setAccent(a);
    state = (mode: state.mode, accent: a, layout: state.layout);
  }

  Future<void> setHomeLayout(HomeLayout l) async {
    await ref.read(prefsRepositoryProvider).setHomeLayout(l);
    state = (mode: state.mode, accent: state.accent, layout: l);
  }
}
