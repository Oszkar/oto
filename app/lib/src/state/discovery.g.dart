// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate` / `ref.refresh`.
///
/// On Android (v0.5 S3) the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The
/// lock is released in a `finally` so a failed discover still frees it.
/// Other platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android
/// dropping SSDP replies, not a precondition. If acquire fails (no Wi-Fi
/// service, permission denied — the native handler returns a structured
/// error), we still attempt discovery rather than hard-failing.

@ProviderFor(discovery)
final discoveryProvider = DiscoveryProvider._();

/// Deferred LAN discovery. The Rust `discover()` blocks ~3–5 s and FRB
/// runs it off the UI isolate, so this is a Future provider: AsyncValue
/// gives loading / error / data; retry via `ref.invalidate` / `ref.refresh`.
///
/// On Android (v0.5 S3) the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The
/// lock is released in a `finally` so a failed discover still frees it.
/// Other platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android
/// dropping SSDP replies, not a precondition. If acquire fails (no Wi-Fi
/// service, permission denied — the native handler returns a structured
/// error), we still attempt discovery rather than hard-failing.

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
  /// gives loading / error / data; retry via `ref.invalidate` / `ref.refresh`.
  ///
  /// On Android (v0.5 S3) the SSDP window is wrapped in a held
  /// `WifiManager.MulticastLock` — without it Android drops the inbound
  /// multicast replies and discovery finds nothing on release builds. The
  /// lock is released in a `finally` so a failed discover still frees it.
  /// Other platforms call `discover()` directly (no channel handler exists).
  ///
  /// The lock is **best-effort**: it's an optimization to stop Android
  /// dropping SSDP replies, not a precondition. If acquire fails (no Wi-Fi
  /// service, permission denied — the native handler returns a structured
  /// error), we still attempt discovery rather than hard-failing.
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
  $FutureProviderElement<rust_api.Topology> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<rust_api.Topology> create(Ref ref) {
    return discovery(ref);
  }
}

String _$discoveryHash() => r'a1e518381167514cf0d16dd6021238226f762b35';
