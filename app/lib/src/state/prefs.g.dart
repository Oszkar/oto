// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prefs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the loaded [PrefsRepository]. Declared as a throw-until-overridden
/// provider: `main()` loads `SharedPreferences` once (async) and overrides this
/// with `overrideWithValue(PrefsRepository(prefs))` before `runApp`. Keeping it
/// synchronous here lets [SettingsNotifier] return a plain record (no AsyncValue)
/// -- the standard Riverpod + shared_preferences pattern. (The Task 7 shell wires
/// the override; tests override it directly.)

@ProviderFor(prefsRepository)
final prefsRepositoryProvider = PrefsRepositoryProvider._();

/// Holds the loaded [PrefsRepository]. Declared as a throw-until-overridden
/// provider: `main()` loads `SharedPreferences` once (async) and overrides this
/// with `overrideWithValue(PrefsRepository(prefs))` before `runApp`. Keeping it
/// synchronous here lets [SettingsNotifier] return a plain record (no AsyncValue)
/// -- the standard Riverpod + shared_preferences pattern. (The Task 7 shell wires
/// the override; tests override it directly.)

final class PrefsRepositoryProvider
    extends
        $FunctionalProvider<PrefsRepository, PrefsRepository, PrefsRepository>
    with $Provider<PrefsRepository> {
  /// Holds the loaded [PrefsRepository]. Declared as a throw-until-overridden
  /// provider: `main()` loads `SharedPreferences` once (async) and overrides this
  /// with `overrideWithValue(PrefsRepository(prefs))` before `runApp`. Keeping it
  /// synchronous here lets [SettingsNotifier] return a plain record (no AsyncValue)
  /// -- the standard Riverpod + shared_preferences pattern. (The Task 7 shell wires
  /// the override; tests override it directly.)
  PrefsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'prefsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$prefsRepositoryHash();

  @$internal
  @override
  $ProviderElement<PrefsRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PrefsRepository create(Ref ref) {
    return prefsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PrefsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PrefsRepository>(value),
    );
  }
}

String _$prefsRepositoryHash() => r'a6b506423cd9f15e8edc194c722216e8ac395d40';

/// Current persisted settings. Restores from the repo on build; every setter
/// reflects the choice in state immediately, then persists best-effort.
///
/// State-first ordering keeps a cosmetic toggle instant (no lag on disk I/O)
/// and applies the user's choice for the session even if the write fails; a
/// rare persistence failure (e.g. full disk) is swallowed rather than crashing
/// the toggle - the only consequence is the setting not surviving a restart.

@ProviderFor(SettingsNotifier)
final settingsProvider = SettingsNotifierProvider._();

/// Current persisted settings. Restores from the repo on build; every setter
/// reflects the choice in state immediately, then persists best-effort.
///
/// State-first ordering keeps a cosmetic toggle instant (no lag on disk I/O)
/// and applies the user's choice for the session even if the write fails; a
/// rare persistence failure (e.g. full disk) is swallowed rather than crashing
/// the toggle - the only consequence is the setting not surviving a restart.
final class SettingsNotifierProvider
    extends
        $NotifierProvider<
          SettingsNotifier,
          ({Accent accent, HomeLayout layout, ThemeMode mode})
        > {
  /// Current persisted settings. Restores from the repo on build; every setter
  /// reflects the choice in state immediately, then persists best-effort.
  ///
  /// State-first ordering keeps a cosmetic toggle instant (no lag on disk I/O)
  /// and applies the user's choice for the session even if the write fails; a
  /// rare persistence failure (e.g. full disk) is swallowed rather than crashing
  /// the toggle - the only consequence is the setting not surviving a restart.
  SettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsNotifierHash();

  @$internal
  @override
  SettingsNotifier create() => SettingsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ({Accent accent, HomeLayout layout, ThemeMode mode}) value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            ({Accent accent, HomeLayout layout, ThemeMode mode})
          >(value),
    );
  }
}

String _$settingsNotifierHash() => r'3fc9b8f82b5175f7aa7478e5056fbed01dcb22e6';

/// Current persisted settings. Restores from the repo on build; every setter
/// reflects the choice in state immediately, then persists best-effort.
///
/// State-first ordering keeps a cosmetic toggle instant (no lag on disk I/O)
/// and applies the user's choice for the session even if the write fails; a
/// rare persistence failure (e.g. full disk) is swallowed rather than crashing
/// the toggle - the only consequence is the setting not surviving a restart.

abstract class _$SettingsNotifier
    extends $Notifier<({Accent accent, HomeLayout layout, ThemeMode mode})> {
  ({Accent accent, HomeLayout layout, ThemeMode mode}) build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              ({Accent accent, HomeLayout layout, ThemeMode mode}),
              ({Accent accent, HomeLayout layout, ThemeMode mode})
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ({Accent accent, HomeLayout layout, ThemeMode mode}),
                ({Accent accent, HomeLayout layout, ThemeMode mode})
              >,
              ({Accent accent, HomeLayout layout, ThemeMode mode}),
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Home layout for the current app session.
///
/// The persisted setting is read once when this provider is first created.
/// Subsequent Home toggles update only this state, while Settings continues to
/// manage the default used by the next root provider scope.

@ProviderFor(CurrentHomeLayout)
final currentHomeLayoutProvider = CurrentHomeLayoutProvider._();

/// Home layout for the current app session.
///
/// The persisted setting is read once when this provider is first created.
/// Subsequent Home toggles update only this state, while Settings continues to
/// manage the default used by the next root provider scope.
final class CurrentHomeLayoutProvider
    extends $NotifierProvider<CurrentHomeLayout, HomeLayout> {
  /// Home layout for the current app session.
  ///
  /// The persisted setting is read once when this provider is first created.
  /// Subsequent Home toggles update only this state, while Settings continues to
  /// manage the default used by the next root provider scope.
  CurrentHomeLayoutProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentHomeLayoutProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentHomeLayoutHash();

  @$internal
  @override
  CurrentHomeLayout create() => CurrentHomeLayout();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeLayout value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeLayout>(value),
    );
  }
}

String _$currentHomeLayoutHash() => r'65fe17df02af7e5227a5275e944dbc41cdfef307';

/// Home layout for the current app session.
///
/// The persisted setting is read once when this provider is first created.
/// Subsequent Home toggles update only this state, while Settings continues to
/// manage the default used by the next root provider scope.

abstract class _$CurrentHomeLayout extends $Notifier<HomeLayout> {
  HomeLayout build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<HomeLayout, HomeLayout>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HomeLayout, HomeLayout>,
              HomeLayout,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
