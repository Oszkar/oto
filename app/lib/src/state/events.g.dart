// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single-consumer stream of ChangeEvents from Rust. Subscribes once
/// per discovery cycle: when `discoveryProvider` yields a new value
/// (success or error), this provider is invalidated and re-runs the
/// FRB `subscribe_change_events` call against the current wire.
///
/// Per-speaker / per-group projections are added in Slice 2; for
/// v0.4 baseline, downstream consumers `ref.watch(changeEventsProvider)`
/// directly and filter client-side.
///
/// **keepAlive: true** (per /codex review on PR #43, finding P1 #1):
/// the Rust consumer loop in `api.rs::subscribe_change_events` blocks
/// indefinitely in `recv()` and only observes Dart cancellation on the
/// next `sink.add(...)` attempt. With `keepAlive: false`, normal
/// provider disposal (no widgets listening) could strand the Rust loop
/// while it still holds the one-shot `take_event_stream()` receiver,
/// making the wire unable to re-stream until rediscovery. Keeping the
/// provider alive for the app lifetime avoids that whole class of bug;
/// the provider is still invalidated and rebuilt when `discoveryProvider`
/// changes (rediscovery), so the FRB stream restarts cleanly on wire
/// replacement — the intended lifecycle boundary.
/// The current wire generation, or `null` until the first successful
/// discovery. `currentWireGeneration()` bumps only on a successful
/// `discover_with`, so although this recomputes on every `discoveryProvider`
/// transition, its VALUE only changes when a new wire is actually installed.
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only on a real new wire — not on a loading/failed re-discover.

@ProviderFor(wireGeneration)
const wireGenerationProvider = WireGenerationProvider._();

/// Single-consumer stream of ChangeEvents from Rust. Subscribes once
/// per discovery cycle: when `discoveryProvider` yields a new value
/// (success or error), this provider is invalidated and re-runs the
/// FRB `subscribe_change_events` call against the current wire.
///
/// Per-speaker / per-group projections are added in Slice 2; for
/// v0.4 baseline, downstream consumers `ref.watch(changeEventsProvider)`
/// directly and filter client-side.
///
/// **keepAlive: true** (per /codex review on PR #43, finding P1 #1):
/// the Rust consumer loop in `api.rs::subscribe_change_events` blocks
/// indefinitely in `recv()` and only observes Dart cancellation on the
/// next `sink.add(...)` attempt. With `keepAlive: false`, normal
/// provider disposal (no widgets listening) could strand the Rust loop
/// while it still holds the one-shot `take_event_stream()` receiver,
/// making the wire unable to re-stream until rediscovery. Keeping the
/// provider alive for the app lifetime avoids that whole class of bug;
/// the provider is still invalidated and rebuilt when `discoveryProvider`
/// changes (rediscovery), so the FRB stream restarts cleanly on wire
/// replacement — the intended lifecycle boundary.
/// The current wire generation, or `null` until the first successful
/// discovery. `currentWireGeneration()` bumps only on a successful
/// `discover_with`, so although this recomputes on every `discoveryProvider`
/// transition, its VALUE only changes when a new wire is actually installed.
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only on a real new wire — not on a loading/failed re-discover.

final class WireGenerationProvider
    extends $FunctionalProvider<BigInt?, BigInt?, BigInt?>
    with $Provider<BigInt?> {
  /// Single-consumer stream of ChangeEvents from Rust. Subscribes once
  /// per discovery cycle: when `discoveryProvider` yields a new value
  /// (success or error), this provider is invalidated and re-runs the
  /// FRB `subscribe_change_events` call against the current wire.
  ///
  /// Per-speaker / per-group projections are added in Slice 2; for
  /// v0.4 baseline, downstream consumers `ref.watch(changeEventsProvider)`
  /// directly and filter client-side.
  ///
  /// **keepAlive: true** (per /codex review on PR #43, finding P1 #1):
  /// the Rust consumer loop in `api.rs::subscribe_change_events` blocks
  /// indefinitely in `recv()` and only observes Dart cancellation on the
  /// next `sink.add(...)` attempt. With `keepAlive: false`, normal
  /// provider disposal (no widgets listening) could strand the Rust loop
  /// while it still holds the one-shot `take_event_stream()` receiver,
  /// making the wire unable to re-stream until rediscovery. Keeping the
  /// provider alive for the app lifetime avoids that whole class of bug;
  /// the provider is still invalidated and rebuilt when `discoveryProvider`
  /// changes (rediscovery), so the FRB stream restarts cleanly on wire
  /// replacement — the intended lifecycle boundary.
  /// The current wire generation, or `null` until the first successful
  /// discovery. `currentWireGeneration()` bumps only on a successful
  /// `discover_with`, so although this recomputes on every `discoveryProvider`
  /// transition, its VALUE only changes when a new wire is actually installed.
  /// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
  /// rebuild only on a real new wire — not on a loading/failed re-discover.
  const WireGenerationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wireGenerationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wireGenerationHash();

  @$internal
  @override
  $ProviderElement<BigInt?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BigInt? create(Ref ref) {
    return wireGeneration(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BigInt? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BigInt?>(value),
    );
  }
}

String _$wireGenerationHash() => r'6dba8cada3a1a86e67a56791020803b1cc38c96e';

@ProviderFor(changeEvents)
const changeEventsProvider = ChangeEventsProvider._();

final class ChangeEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<rust_api.ChangeEventDto>,
          rust_api.ChangeEventDto,
          Stream<rust_api.ChangeEventDto>
        >
    with
        $FutureModifier<rust_api.ChangeEventDto>,
        $StreamProvider<rust_api.ChangeEventDto> {
  const ChangeEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'changeEventsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$changeEventsHash();

  @$internal
  @override
  $StreamProviderElement<rust_api.ChangeEventDto> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<rust_api.ChangeEventDto> create(Ref ref) {
    return changeEvents(ref);
  }
}

String _$changeEventsHash() => r'5cb7b520b72864c1031e9fc532a4c68f58870165';
