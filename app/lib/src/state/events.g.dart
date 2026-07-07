// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Reads the authoritative wire generation from Rust. Extracted behind an
/// overridable provider so [wireGeneration]'s keying logic is unit-testable
/// without FRB (a test injects a controllable counter). The default tears off
/// the sync FRB `currentWireGeneration()`.

@ProviderFor(wireGenerationReader)
final wireGenerationReaderProvider = WireGenerationReaderProvider._();

/// Reads the authoritative wire generation from Rust. Extracted behind an
/// overridable provider so [wireGeneration]'s keying logic is unit-testable
/// without FRB (a test injects a controllable counter). The default tears off
/// the sync FRB `currentWireGeneration()`.

final class WireGenerationReaderProvider
    extends
        $FunctionalProvider<
          BigInt Function(),
          BigInt Function(),
          BigInt Function()
        >
    with $Provider<BigInt Function()> {
  /// Reads the authoritative wire generation from Rust. Extracted behind an
  /// overridable provider so [wireGeneration]'s keying logic is unit-testable
  /// without FRB (a test injects a controllable counter). The default tears off
  /// the sync FRB `currentWireGeneration()`.
  WireGenerationReaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wireGenerationReaderProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wireGenerationReaderHash();

  @$internal
  @override
  $ProviderElement<BigInt Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BigInt Function() create(Ref ref) {
    return wireGenerationReader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BigInt Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BigInt Function()>(value),
    );
  }
}

String _$wireGenerationReaderHash() =>
    r'8efe14ef92ffed55bed217bfe23c9da18b8e1c64';

/// The current wire generation, or `null` until the first successful
/// discovery. Recomputes on every `discoveryProvider` transition, but reads
/// the **authoritative Rust generation** via [wireGenerationReaderProvider] —
/// not `discovery.hasValue`. The Rust generation reflects the
/// currently-installed wire (`0` before any successful `discover_with`, `>0`
/// after), and `discover_with` bumps it only on success.
///
/// Reading it directly (rather than gating on `discovery.hasValue`) is what
/// keeps the live event stream alive across a FAILED user re-discover: that
/// path ends in `AsyncError` with no retained value (`hasValue == false`), yet
/// the old wire is still installed and its generation unchanged, so this keeps
/// returning it — no spurious teardown (review #67-followup #2).
///
/// Recompute triggers:
///   - [discoveryProvider] — the initial discover, a user `rediscover()`, and a
///     value-CHANGING `refreshTopology()` all transition it, so this recomputes
///     and re-reads the generation.
///   - [wireInstallSignalProvider] — a value-EQUAL `refreshTopology()` (a no-op
///     regroup) does NOT transition discovery (FRB `Topology` has value
///     equality), so the install bumps this signal to force a re-read. Without
///     it the new wire's generation would go unnoticed and the stream would
///     strand on the replaced wire's dead receiver.
///
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only when a NEW wire is actually installed, not on a loading/failed
/// re-discover or a redundant signal bump.

@ProviderFor(wireGeneration)
final wireGenerationProvider = WireGenerationProvider._();

/// The current wire generation, or `null` until the first successful
/// discovery. Recomputes on every `discoveryProvider` transition, but reads
/// the **authoritative Rust generation** via [wireGenerationReaderProvider] —
/// not `discovery.hasValue`. The Rust generation reflects the
/// currently-installed wire (`0` before any successful `discover_with`, `>0`
/// after), and `discover_with` bumps it only on success.
///
/// Reading it directly (rather than gating on `discovery.hasValue`) is what
/// keeps the live event stream alive across a FAILED user re-discover: that
/// path ends in `AsyncError` with no retained value (`hasValue == false`), yet
/// the old wire is still installed and its generation unchanged, so this keeps
/// returning it — no spurious teardown (review #67-followup #2).
///
/// Recompute triggers:
///   - [discoveryProvider] — the initial discover, a user `rediscover()`, and a
///     value-CHANGING `refreshTopology()` all transition it, so this recomputes
///     and re-reads the generation.
///   - [wireInstallSignalProvider] — a value-EQUAL `refreshTopology()` (a no-op
///     regroup) does NOT transition discovery (FRB `Topology` has value
///     equality), so the install bumps this signal to force a re-read. Without
///     it the new wire's generation would go unnoticed and the stream would
///     strand on the replaced wire's dead receiver.
///
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only when a NEW wire is actually installed, not on a loading/failed
/// re-discover or a redundant signal bump.

final class WireGenerationProvider
    extends $FunctionalProvider<BigInt?, BigInt?, BigInt?>
    with $Provider<BigInt?> {
  /// The current wire generation, or `null` until the first successful
  /// discovery. Recomputes on every `discoveryProvider` transition, but reads
  /// the **authoritative Rust generation** via [wireGenerationReaderProvider] —
  /// not `discovery.hasValue`. The Rust generation reflects the
  /// currently-installed wire (`0` before any successful `discover_with`, `>0`
  /// after), and `discover_with` bumps it only on success.
  ///
  /// Reading it directly (rather than gating on `discovery.hasValue`) is what
  /// keeps the live event stream alive across a FAILED user re-discover: that
  /// path ends in `AsyncError` with no retained value (`hasValue == false`), yet
  /// the old wire is still installed and its generation unchanged, so this keeps
  /// returning it — no spurious teardown (review #67-followup #2).
  ///
  /// Recompute triggers:
  ///   - [discoveryProvider] — the initial discover, a user `rediscover()`, and a
  ///     value-CHANGING `refreshTopology()` all transition it, so this recomputes
  ///     and re-reads the generation.
  ///   - [wireInstallSignalProvider] — a value-EQUAL `refreshTopology()` (a no-op
  ///     regroup) does NOT transition discovery (FRB `Topology` has value
  ///     equality), so the install bumps this signal to force a re-read. Without
  ///     it the new wire's generation would go unnoticed and the stream would
  ///     strand on the replaced wire's dead receiver.
  ///
  /// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
  /// rebuild only when a NEW wire is actually installed, not on a loading/failed
  /// re-discover or a redundant signal bump.
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

String _$wireGenerationHash() => r'9d424df16478f6b7516d1bd050ddda7138fa7342';

/// Builds the raw FRB change-event stream. Extracted behind an overridable
/// provider so [changeEvents]'s re-subscription is observable in tests (count
/// the factory calls) without FRB. The default tears off `subscribeChangeEvents`.

@ProviderFor(changeEventStreamFactory)
final changeEventStreamFactoryProvider = ChangeEventStreamFactoryProvider._();

/// Builds the raw FRB change-event stream. Extracted behind an overridable
/// provider so [changeEvents]'s re-subscription is observable in tests (count
/// the factory calls) without FRB. The default tears off `subscribeChangeEvents`.

final class ChangeEventStreamFactoryProvider
    extends
        $FunctionalProvider<
          Stream<rust_api.ChangeEventDto> Function(),
          Stream<rust_api.ChangeEventDto> Function(),
          Stream<rust_api.ChangeEventDto> Function()
        >
    with $Provider<Stream<rust_api.ChangeEventDto> Function()> {
  /// Builds the raw FRB change-event stream. Extracted behind an overridable
  /// provider so [changeEvents]'s re-subscription is observable in tests (count
  /// the factory calls) without FRB. The default tears off `subscribeChangeEvents`.
  ChangeEventStreamFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'changeEventStreamFactoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$changeEventStreamFactoryHash();

  @$internal
  @override
  $ProviderElement<Stream<rust_api.ChangeEventDto> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Stream<rust_api.ChangeEventDto> Function() create(Ref ref) {
    return changeEventStreamFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Stream<rust_api.ChangeEventDto> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Stream<rust_api.ChangeEventDto> Function()>(value),
    );
  }
}

String _$changeEventStreamFactoryHash() =>
    r'228bff73bc2aa543f38510adef172bcf543173ad';

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

String _$changeEventsHash() => r'5ab0efe7273ceff530275f62f3d7a79510938332';
