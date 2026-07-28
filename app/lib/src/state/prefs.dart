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
/// reflects the choice in state immediately, then persists best-effort.
///
/// State-first ordering keeps a cosmetic toggle instant (no lag on disk I/O)
/// and applies the user's choice for the session even if the write fails; a
/// rare persistence failure (e.g. full disk) is swallowed rather than crashing
/// the toggle - the only consequence is the setting not surviving a restart.
@Riverpod(keepAlive: true)
class SettingsNotifier extends _$SettingsNotifier {
  @override
  ({ThemeMode mode, Accent accent, HomeLayout layout}) build() {
    final repo = ref.watch(prefsRepositoryProvider);
    return (mode: repo.themeMode, accent: repo.accent, layout: repo.homeLayout);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    state = (mode: m, accent: state.accent, layout: state.layout);
    try {
      await ref.read(prefsRepositoryProvider).setThemeMode(m);
    } catch (_) {}
  }

  Future<void> setAccent(Accent a) async {
    state = (mode: state.mode, accent: a, layout: state.layout);
    try {
      await ref.read(prefsRepositoryProvider).setAccent(a);
    } catch (_) {}
  }

  Future<void> setHomeLayout(HomeLayout l) async {
    state = (mode: state.mode, accent: state.accent, layout: l);
    try {
      await ref.read(prefsRepositoryProvider).setHomeLayout(l);
    } catch (_) {}
  }
}

/// Home layout for the current app session.
///
/// The persisted setting is read once when this provider is first created.
/// Subsequent Home toggles update only this state, while Settings continues to
/// manage the default used by the next root provider scope.
@Riverpod(keepAlive: true)
class CurrentHomeLayout extends _$CurrentHomeLayout {
  @override
  HomeLayout build() => ref.read(settingsProvider).layout;

  void setLayout(HomeLayout layout) => state = layout;
}
