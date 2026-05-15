// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate`.

@ProviderFor(discovery)
const discoveryProvider = DiscoveryProvider._();

/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate`.

final class DiscoveryProvider
    extends
        $FunctionalProvider<
          AsyncValue<rust_api.Topology>,
          rust_api.Topology,
          FutureOr<rust_api.Topology>
        >
    with
        $FutureModifier<rust_api.Topology>,
        $FutureProvider<rust_api.Topology> {
  /// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
  /// runs it off the UI isolate, so this is a Future provider: AsyncValue
  /// gives loading / error / data; retry via `ref.invalidate`.
  const DiscoveryProvider._()
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
  $FutureProviderElement<rust_api.Topology> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<rust_api.Topology> create(Ref ref) {
    return discovery(ref);
  }
}

String _$discoveryHash() => r'38b5b0ee3cff790a96f3e2e030d7534a6ec0745f';
