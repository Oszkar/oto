// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// LAN discovery + the v0.5.1 topology fast-path.
///
/// An async Notifier (not a plain Future provider) so it can expose
/// [Discovery.refreshTopology] alongside the deferred `build()` discover.
/// `ref.watch(discoveryProvider)` still yields an `AsyncValue<Topology>`, so
/// every existing consumer (incl. `events.dart`'s `wireGenerationProvider`)
/// is unchanged — and a `refreshTopology()` re-pull still surfaces as a
/// `discoveryProvider` transition, which is what drives the event stream to
/// re-subscribe against the new wire (see [Discovery.refreshTopology]).
///
/// `build()` runs the full `discover()`: Rust SSDP (~3–5 s) + GetZoneGroupState.
/// FRB runs it off the UI isolate, so AsyncValue gives loading / error / data;
/// retry via `ref.invalidate` / `ref.refresh`.
///
/// On Android the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The lock
/// is released in a `finally` so a failed discover still frees it. Other
/// platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android dropping
/// SSDP replies, not a precondition. If acquire fails (no Wi-Fi service,
/// permission denied — the native handler returns a structured error), we
/// still attempt discovery rather than hard-failing.

@ProviderFor(Discovery)
final discoveryProvider = DiscoveryProvider._();

/// LAN discovery + the v0.5.1 topology fast-path.
///
/// An async Notifier (not a plain Future provider) so it can expose
/// [Discovery.refreshTopology] alongside the deferred `build()` discover.
/// `ref.watch(discoveryProvider)` still yields an `AsyncValue<Topology>`, so
/// every existing consumer (incl. `events.dart`'s `wireGenerationProvider`)
/// is unchanged — and a `refreshTopology()` re-pull still surfaces as a
/// `discoveryProvider` transition, which is what drives the event stream to
/// re-subscribe against the new wire (see [Discovery.refreshTopology]).
///
/// `build()` runs the full `discover()`: Rust SSDP (~3–5 s) + GetZoneGroupState.
/// FRB runs it off the UI isolate, so AsyncValue gives loading / error / data;
/// retry via `ref.invalidate` / `ref.refresh`.
///
/// On Android the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The lock
/// is released in a `finally` so a failed discover still frees it. Other
/// platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android dropping
/// SSDP replies, not a precondition. If acquire fails (no Wi-Fi service,
/// permission denied — the native handler returns a structured error), we
/// still attempt discovery rather than hard-failing.
final class DiscoveryProvider
    extends $AsyncNotifierProvider<Discovery, rust_api.Topology> {
  /// LAN discovery + the v0.5.1 topology fast-path.
  ///
  /// An async Notifier (not a plain Future provider) so it can expose
  /// [Discovery.refreshTopology] alongside the deferred `build()` discover.
  /// `ref.watch(discoveryProvider)` still yields an `AsyncValue<Topology>`, so
  /// every existing consumer (incl. `events.dart`'s `wireGenerationProvider`)
  /// is unchanged — and a `refreshTopology()` re-pull still surfaces as a
  /// `discoveryProvider` transition, which is what drives the event stream to
  /// re-subscribe against the new wire (see [Discovery.refreshTopology]).
  ///
  /// `build()` runs the full `discover()`: Rust SSDP (~3–5 s) + GetZoneGroupState.
  /// FRB runs it off the UI isolate, so AsyncValue gives loading / error / data;
  /// retry via `ref.invalidate` / `ref.refresh`.
  ///
  /// On Android the SSDP window is wrapped in a held
  /// `WifiManager.MulticastLock` — without it Android drops the inbound
  /// multicast replies and discovery finds nothing on release builds. The lock
  /// is released in a `finally` so a failed discover still frees it. Other
  /// platforms call `discover()` directly (no channel handler exists).
  ///
  /// The lock is **best-effort**: it's an optimization to stop Android dropping
  /// SSDP replies, not a precondition. If acquire fails (no Wi-Fi service,
  /// permission denied — the native handler returns a structured error), we
  /// still attempt discovery rather than hard-failing.
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

String _$discoveryHash() => r'3f8c5a8bd62eee7b8169184b8035ae753eb1ed8d';

/// LAN discovery + the v0.5.1 topology fast-path.
///
/// An async Notifier (not a plain Future provider) so it can expose
/// [Discovery.refreshTopology] alongside the deferred `build()` discover.
/// `ref.watch(discoveryProvider)` still yields an `AsyncValue<Topology>`, so
/// every existing consumer (incl. `events.dart`'s `wireGenerationProvider`)
/// is unchanged — and a `refreshTopology()` re-pull still surfaces as a
/// `discoveryProvider` transition, which is what drives the event stream to
/// re-subscribe against the new wire (see [Discovery.refreshTopology]).
///
/// `build()` runs the full `discover()`: Rust SSDP (~3–5 s) + GetZoneGroupState.
/// FRB runs it off the UI isolate, so AsyncValue gives loading / error / data;
/// retry via `ref.invalidate` / `ref.refresh`.
///
/// On Android the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The lock
/// is released in a `finally` so a failed discover still frees it. Other
/// platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android dropping
/// SSDP replies, not a precondition. If acquire fails (no Wi-Fi service,
/// permission denied — the native handler returns a structured error), we
/// still attempt discovery rather than hard-failing.

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
