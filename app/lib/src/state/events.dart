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

/// The current wire generation, or `null` until the first successful
/// discovery. `currentWireGeneration()` bumps only on a successful
/// `discover_with`, so although this recomputes on every `discoveryProvider`
/// transition, its VALUE only changes when a new wire is actually installed.
/// Riverpod dedupes by `==` (BigInt is value-equal), so downstream watchers
/// rebuild only on a real new wire — not on a loading/failed re-discover.
@riverpod
BigInt? wireGeneration(Ref ref) {
  final discovery = ref.watch(discoveryProvider);
  // hasValue stays true across loading/error once discovery has succeeded
  // once (AsyncValue retains the prior value), so a failed re-discover keeps
  // reading the SAME generation → no change → no rebuild downstream.
  return discovery.hasValue ? rust_api.currentWireGeneration() : null;
}

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
  return rust_api.subscribeChangeEvents();
}
