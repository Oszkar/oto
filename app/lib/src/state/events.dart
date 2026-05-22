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
@Riverpod(keepAlive: true)
Stream<rust_api.ChangeEventDto> changeEvents(Ref ref) {
  // Trigger rebuild on discovery change. We don't need the value;
  // the dependency on the provider is the signal.
  ref.watch(discoveryProvider);
  return rust_api.subscribeChangeEvents();
}
