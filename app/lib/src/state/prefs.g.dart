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
/// writes through to the repo AND updates state so the UI reacts immediately.

@ProviderFor(SettingsNotifier)
final settingsProvider = SettingsNotifierProvider._();

/// Current persisted settings. Restores from the repo on build; every setter
/// writes through to the repo AND updates state so the UI reacts immediately.
final class SettingsNotifierProvider
    extends
        $NotifierProvider<
          SettingsNotifier,
          ({Accent accent, HomeLayout layout, ThemeMode mode})
        > {
  /// Current persisted settings. Restores from the repo on build; every setter
  /// writes through to the repo AND updates state so the UI reacts immediately.
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

String _$settingsNotifierHash() => r'8dcd94566582bcfa45feb1bbec664892d9484217';

/// Current persisted settings. Restores from the repo on build; every setter
/// writes through to the repo AND updates state so the UI reacts immediately.

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
