// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sources.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Derived active-source list for the UI.
///
/// A class Notifier (not a bare function provider) so [updateShouldNotify] can
/// dedupe by value: [sourcesFromHousehold] returns a fresh `List` on every
/// household delta, and `List` has no value equality, so a plain provider would
/// notify consumers (`bottom_strip`) on *every* event - an unrelated room's
/// volume tick - even when the derived sources are identical. `listEquals` over
/// the value-equal [Source] elements suppresses those no-op rebuilds.

@ProviderFor(Sources)
final sourcesProvider = SourcesProvider._();

/// Derived active-source list for the UI.
///
/// A class Notifier (not a bare function provider) so [updateShouldNotify] can
/// dedupe by value: [sourcesFromHousehold] returns a fresh `List` on every
/// household delta, and `List` has no value equality, so a plain provider would
/// notify consumers (`bottom_strip`) on *every* event - an unrelated room's
/// volume tick - even when the derived sources are identical. `listEquals` over
/// the value-equal [Source] elements suppresses those no-op rebuilds.
final class SourcesProvider extends $NotifierProvider<Sources, List<Source>> {
  /// Derived active-source list for the UI.
  ///
  /// A class Notifier (not a bare function provider) so [updateShouldNotify] can
  /// dedupe by value: [sourcesFromHousehold] returns a fresh `List` on every
  /// household delta, and `List` has no value equality, so a plain provider would
  /// notify consumers (`bottom_strip`) on *every* event - an unrelated room's
  /// volume tick - even when the derived sources are identical. `listEquals` over
  /// the value-equal [Source] elements suppresses those no-op rebuilds.
  SourcesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesHash();

  @$internal
  @override
  Sources create() => Sources();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Source> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Source>>(value),
    );
  }
}

String _$sourcesHash() => r'8fedb09b2b913f91da121589b04b5b8abcb2108b';

/// Derived active-source list for the UI.
///
/// A class Notifier (not a bare function provider) so [updateShouldNotify] can
/// dedupe by value: [sourcesFromHousehold] returns a fresh `List` on every
/// household delta, and `List` has no value equality, so a plain provider would
/// notify consumers (`bottom_strip`) on *every* event - an unrelated room's
/// volume tick - even when the derived sources are identical. `listEquals` over
/// the value-equal [Source] elements suppresses those no-op rebuilds.

abstract class _$Sources extends $Notifier<List<Source>> {
  List<Source> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<Source>, List<Source>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Source>, List<Source>>,
              List<Source>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
