/// v0.4 unified ChangeEvent stream. Single FRB call per app instance;
/// Dart-side fanout via downstream `StreamProvider`s (FRB does NOT
/// broadcast - see FRB pre-check § 5). Depends on `discoveryProvider`
/// so the stream restarts after `discover()` replaces the wire - per
/// spec § 7 "discover() ↔ active-subscription orchestration".
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;
import 'discovery.dart';

part 'events.g.dart';

/// Reads the authoritative wire generation from Rust. Extracted behind an
/// overridable provider so [wireGeneration]'s keying logic is unit-testable
/// without FRB (a test injects a controllable counter). The default tears off
/// the sync FRB `currentWireGeneration()`.
@riverpod
BigInt Function() wireGenerationReader(Ref ref) =>
    rust_api.currentWireGeneration;

/// The current wire generation, or `null` until the first successful
/// discovery. Recomputes on every `discoveryProvider` transition, but reads
/// the **authoritative Rust generation** via [wireGenerationReaderProvider] -
/// not `discovery.hasValue`. The Rust generation reflects the
/// currently-installed wire (`0` before any successful `discover_with`, `>0`
/// after), and `discover_with` bumps it only on success.
///
/// Reading it directly (rather than gating on `discovery.hasValue`) is what
/// keeps the live event stream alive across a FAILED user re-discover: that
/// path ends in `AsyncError` with no retained value (`hasValue == false`), yet
/// the old wire is still installed and its generation unchanged, so this keeps
/// returning it - no spurious teardown (review #67-followup #2).
///
/// Recompute triggers:
///   - [discoveryProvider] - the initial discover, a user `rediscover()`, and a
///     value-CHANGING `refreshTopology()` all transition it, so this recomputes
///     and re-reads the generation.
///   - [wireInstallSignalProvider] - a value-EQUAL `refreshTopology()` (a no-op
///     regroup) does NOT transition discovery (FRB `Topology` has value
///     equality), so the install bumps this signal to force a re-read. Without
///     it the new wire's generation would go unnoticed and the stream would
///     strand on the replaced wire's dead receiver.
///
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only when a NEW wire is actually installed, not on a loading/failed
/// re-discover or a redundant signal bump.
@riverpod
BigInt? wireGeneration(Ref ref) {
  // Force a re-read on a wire install that did NOT transition discovery (a
  // value-equal fast `refreshTopology()`); see [wireInstallSignalProvider].
  ref.watch(wireInstallSignalProvider);
  // Depend on discovery so we recompute on its transitions (a successful
  // discover bumps the Rust generation); the AsyncValue itself is unused -
  // gating on `hasValue` would tear the stream down on a failed rediscover.
  ref.watch(discoveryProvider);
  final generation = ref.watch(wireGenerationReaderProvider)();
  return generation == BigInt.zero ? null : generation;
}

/// Builds the raw FRB change-event stream. Extracted behind an overridable
/// provider so [changeEvents]'s re-subscription is observable in tests (count
/// the factory calls) without FRB. The default tears off `subscribeChangeEvents`.
@riverpod
Stream<rust_api.ChangeEventDto> Function() changeEventStreamFactory(Ref ref) =>
    rust_api.subscribeChangeEvents;

/// Single-consumer stream of ChangeEvents from Rust. Re-subscribes once per
/// **new wire** - keyed on [wireGenerationProvider], which only changes on a
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
/// wire replacement - the intended lifecycle boundary.
@Riverpod(keepAlive: true)
Stream<rust_api.ChangeEventDto> changeEvents(Ref ref) {
  final generation = ref.watch(wireGenerationProvider);
  if (generation == null) {
    // No wire installed yet - nothing to subscribe to.
    return const Stream<rust_api.ChangeEventDto>.empty();
  }
  return ref.watch(changeEventStreamFactoryProvider)();
}
