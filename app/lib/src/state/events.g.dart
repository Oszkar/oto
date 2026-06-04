// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The current wire generation, or `null` until the first successful
/// discovery. `currentWireGeneration()` bumps only on a successful
/// `discover_with`, so although this recomputes on every `discoveryProvider`
/// transition, its VALUE only changes when a new wire is actually installed.
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only on a real new wire — not on a loading/failed re-discover.

@ProviderFor(wireGeneration)
final wireGenerationProvider = WireGenerationProvider._();

/// The current wire generation, or `null` until the first successful
/// discovery. `currentWireGeneration()` bumps only on a successful
/// `discover_with`, so although this recomputes on every `discoveryProvider`
/// transition, its VALUE only changes when a new wire is actually installed.
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only on a real new wire — not on a loading/failed re-discover.

final class WireGenerationProvider
    extends $FunctionalProvider<BigInt?, BigInt?, BigInt?>
    with $Provider<BigInt?> {
  /// The current wire generation, or `null` until the first successful
  /// discovery. `currentWireGeneration()` bumps only on a successful
  /// `discover_with`, so although this recomputes on every `discoveryProvider`
  /// transition, its VALUE only changes when a new wire is actually installed.
  /// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
  /// rebuild only on a real new wire — not on a loading/failed re-discover.
  WireGenerationProvider._()
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

/// Single-consumer stream of ChangeEvents from Rust. Re-subscribes once per
/// **new wire** — keyed on [wireGenerationProvider], which only changes on a
/// successful `discover_with`. A failed/loading re-discover does NOT rebuild
/// this provider: `discover_with` keeps the old wire on failure, and its
/// `take_event_stream` receiver is one-shot and can't be retaken, so
/// re-subscribing then would strand events on a dead receiver (codex review
/// #67-followup #2).
///
/// Downstream consumers `ref.watch(changeEventsProvider)` and filter
/// client-side (Volume/Mute/Playback/Track/Subscription*/TopologyChanged).
///
/// **keepAlive: true** (per /codex review on PR #43, finding P1 #1): the
/// Rust consumer loop in `api.rs::subscribe_change_events` blocks on
/// `recv_timeout` and only observes Dart cancellation on the next
/// `sink.add(...)`. With `keepAlive: false`, normal provider disposal (no
/// widgets listening) could strand the Rust loop while it holds the
/// one-shot receiver, making the wire unable to re-stream until rediscovery.
/// Keeping it alive for the app lifetime avoids that class of bug; it still
/// rebuilds on a new wire generation, so the FRB stream restarts cleanly on
/// wire replacement — the intended lifecycle boundary.

@ProviderFor(changeEvents)
final changeEventsProvider = ChangeEventsProvider._();

/// Single-consumer stream of ChangeEvents from Rust. Re-subscribes once per
/// **new wire** — keyed on [wireGenerationProvider], which only changes on a
/// successful `discover_with`. A failed/loading re-discover does NOT rebuild
/// this provider: `discover_with` keeps the old wire on failure, and its
/// `take_event_stream` receiver is one-shot and can't be retaken, so
/// re-subscribing then would strand events on a dead receiver (codex review
/// #67-followup #2).
///
/// Downstream consumers `ref.watch(changeEventsProvider)` and filter
/// client-side (Volume/Mute/Playback/Track/Subscription*/TopologyChanged).
///
/// **keepAlive: true** (per /codex review on PR #43, finding P1 #1): the
/// Rust consumer loop in `api.rs::subscribe_change_events` blocks on
/// `recv_timeout` and only observes Dart cancellation on the next
/// `sink.add(...)`. With `keepAlive: false`, normal provider disposal (no
/// widgets listening) could strand the Rust loop while it holds the
/// one-shot receiver, making the wire unable to re-stream until rediscovery.
/// Keeping it alive for the app lifetime avoids that class of bug; it still
/// rebuilds on a new wire generation, so the FRB stream restarts cleanly on
/// wire replacement — the intended lifecycle boundary.

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
  /// Single-consumer stream of ChangeEvents from Rust. Re-subscribes once per
  /// **new wire** — keyed on [wireGenerationProvider], which only changes on a
  /// successful `discover_with`. A failed/loading re-discover does NOT rebuild
  /// this provider: `discover_with` keeps the old wire on failure, and its
  /// `take_event_stream` receiver is one-shot and can't be retaken, so
  /// re-subscribing then would strand events on a dead receiver (codex review
  /// #67-followup #2).
  ///
  /// Downstream consumers `ref.watch(changeEventsProvider)` and filter
  /// client-side (Volume/Mute/Playback/Track/Subscription*/TopologyChanged).
  ///
  /// **keepAlive: true** (per /codex review on PR #43, finding P1 #1): the
  /// Rust consumer loop in `api.rs::subscribe_change_events` blocks on
  /// `recv_timeout` and only observes Dart cancellation on the next
  /// `sink.add(...)`. With `keepAlive: false`, normal provider disposal (no
  /// widgets listening) could strand the Rust loop while it holds the
  /// one-shot receiver, making the wire unable to re-stream until rediscovery.
  /// Keeping it alive for the app lifetime avoids that class of bug; it still
  /// rebuilds on a new wire generation, so the FRB stream restarts cleanly on
  /// wire replacement — the intended lifecycle boundary.
  ChangeEventsProvider._()
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
