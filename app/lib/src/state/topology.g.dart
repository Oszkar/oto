// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topology.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Side-effect controller (no exposed state). `keepAlive` so the
/// subscription + debounce timer live for the app lifetime once activated;
/// builds once (uses `ref.listen`, never `ref.watch`, so a new event does
/// not rebuild it).

@ProviderFor(topologyController)
const topologyControllerProvider = TopologyControllerProvider._();

/// Side-effect controller (no exposed state). `keepAlive` so the
/// subscription + debounce timer live for the app lifetime once activated;
/// builds once (uses `ref.listen`, never `ref.watch`, so a new event does
/// not rebuild it).

final class TopologyControllerProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Side-effect controller (no exposed state). `keepAlive` so the
  /// subscription + debounce timer live for the app lifetime once activated;
  /// builds once (uses `ref.listen`, never `ref.watch`, so a new event does
  /// not rebuild it).
  const TopologyControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'topologyControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$topologyControllerHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return topologyController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$topologyControllerHash() =>
    r'2f36616724a6503d444603a8a56abe2c8ae79793';
