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
@Riverpod(keepAlive: false)
Stream<rust_api.ChangeEventDto> changeEvents(Ref ref) {
  // Trigger rebuild on discovery change. We don't need the value;
  // the dependency on the provider is the signal.
  ref.watch(discoveryProvider);
  return rust_api.subscribeChangeEvents();
}
