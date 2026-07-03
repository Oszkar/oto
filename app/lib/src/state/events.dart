/// v0.4 unified ChangeEvent stream. Single FRB call per app instance;
/// Dart-side fanout via downstream `StreamProvider`s (FRB does NOT
/// broadcast — see FRB pre-check § 5). Depends on `discoveryProvider`
/// so the stream restarts after `discover()` replaces the wire — per
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

/// The current wire generation, or `null` until the first successful discovery.
///
/// Keyed on the MONOTONIC Rust generation VALUE (not on the topology value): it
/// bumps once per successful `discover_with`, so downstream [changeEvents]
/// re-subscribes EXACTLY once per new wire. Exactly-once is load-bearing — the
/// wire's event receiver is one-shot, so a double re-subscribe against the same
/// wire would take an already-taken receiver and strand the stream.
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
/// A failed re-discover does not bump the Rust generation, so the value is
/// unchanged and the live stream is preserved (review #67-followup #2).
@riverpod
BigInt? wireGeneration(Ref ref) {
  // Force a re-read on a wire install that did NOT transition discovery (a
  // value-equal fast `refreshTopology()`); see [wireInstallSignalProvider].
  ref.watch(wireInstallSignalProvider);
  final discovery = ref.watch(discoveryProvider);
  final readGeneration = ref.watch(wireGenerationReaderProvider);
  // hasValue stays true across loading/error once discovery has succeeded once
  // (Riverpod attaches the prior value), so a failed re-discover keeps reading
  // the SAME generation → no change → no rebuild downstream.
  return discovery.hasValue ? readGeneration() : null;
}

/// Builds the raw FRB change-event stream. Extracted behind an overridable
/// provider so [changeEvents]'s re-subscription is observable in tests (count
/// the factory calls) without FRB. The default tears off `subscribeChangeEvents`.
@riverpod
Stream<rust_api.ChangeEventDto> Function() changeEventStreamFactory(Ref ref) =>
    rust_api.subscribeChangeEvents;

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
@Riverpod(keepAlive: true)
Stream<rust_api.ChangeEventDto> changeEvents(Ref ref) {
  final generation = ref.watch(wireGenerationProvider);
  if (generation == null) {
    // No wire installed yet — nothing to subscribe to.
    return const Stream<rust_api.ChangeEventDto>.empty();
  }
  return ref.watch(changeEventStreamFactoryProvider)();
}
