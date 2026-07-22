// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Discovery)
final discoveryProvider = DiscoveryProvider._();

final class DiscoveryProvider
    extends $AsyncNotifierProvider<Discovery, rust_api.Topology> {
  DiscoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'discoveryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$discoveryHash();

  @$internal
  @override
  Discovery create() => Discovery();
}

String _$discoveryHash() => r'0320061c7b0855afad2eb0aa542b90e4a5eaa35c';

abstract class _$Discovery extends $AsyncNotifier<rust_api.Topology> {
  FutureOr<rust_api.Topology> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<rust_api.Topology>, rust_api.Topology>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<rust_api.Topology>, rust_api.Topology>,
              AsyncValue<rust_api.Topology>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// A monotonic signal bumped on every wire install that may NOT transition
/// [discoveryProvider] - specifically a value-equal fast `refreshTopology()`
/// (a no-op regroup). `wireGenerationProvider` (events.dart) watches this to
/// force a re-read of the Rust generation so the event stream re-subscribes
/// against the new wire. Lives here because [Discovery] owns the wire lifecycle
/// and is the sole bumper; `events.dart` only consumes it (keeps the dependency
/// direction events → discovery, avoiding a cycle).
///
/// `keepAlive`: the count must persist for the app lifetime (it outlives any
/// single widget subscription and accumulates across regroups).

@ProviderFor(WireInstallSignal)
final wireInstallSignalProvider = WireInstallSignalProvider._();

/// A monotonic signal bumped on every wire install that may NOT transition
/// [discoveryProvider] - specifically a value-equal fast `refreshTopology()`
/// (a no-op regroup). `wireGenerationProvider` (events.dart) watches this to
/// force a re-read of the Rust generation so the event stream re-subscribes
/// against the new wire. Lives here because [Discovery] owns the wire lifecycle
/// and is the sole bumper; `events.dart` only consumes it (keeps the dependency
/// direction events → discovery, avoiding a cycle).
///
/// `keepAlive`: the count must persist for the app lifetime (it outlives any
/// single widget subscription and accumulates across regroups).
final class WireInstallSignalProvider
    extends $NotifierProvider<WireInstallSignal, int> {
  /// A monotonic signal bumped on every wire install that may NOT transition
  /// [discoveryProvider] - specifically a value-equal fast `refreshTopology()`
  /// (a no-op regroup). `wireGenerationProvider` (events.dart) watches this to
  /// force a re-read of the Rust generation so the event stream re-subscribes
  /// against the new wire. Lives here because [Discovery] owns the wire lifecycle
  /// and is the sole bumper; `events.dart` only consumes it (keeps the dependency
  /// direction events → discovery, avoiding a cycle).
  ///
  /// `keepAlive`: the count must persist for the app lifetime (it outlives any
  /// single widget subscription and accumulates across regroups).
  WireInstallSignalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wireInstallSignalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wireInstallSignalHash();

  @$internal
  @override
  WireInstallSignal create() => WireInstallSignal();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$wireInstallSignalHash() => r'2bf533d35d8e5429c890c41b9e404b5358f7c8a6';

/// A monotonic signal bumped on every wire install that may NOT transition
/// [discoveryProvider] - specifically a value-equal fast `refreshTopology()`
/// (a no-op regroup). `wireGenerationProvider` (events.dart) watches this to
/// force a re-read of the Rust generation so the event stream re-subscribes
/// against the new wire. Lives here because [Discovery] owns the wire lifecycle
/// and is the sole bumper; `events.dart` only consumes it (keeps the dependency
/// direction events → discovery, avoiding a cycle).
///
/// `keepAlive`: the count must persist for the app lifetime (it outlives any
/// single widget subscription and accumulates across regroups).

abstract class _$WireInstallSignal extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(DiscoveryRetrying)
final discoveryRetryingProvider = DiscoveryRetryingProvider._();

final class DiscoveryRetryingProvider
    extends $NotifierProvider<DiscoveryRetrying, bool> {
  DiscoveryRetryingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'discoveryRetryingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$discoveryRetryingHash();

  @$internal
  @override
  DiscoveryRetrying create() => DiscoveryRetrying();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$discoveryRetryingHash() => r'f379d808a43d4ec90d3cb90690e553c103419d0b';

abstract class _$DiscoveryRetrying extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
