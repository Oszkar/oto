import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../platform/android_multicast_lock.dart';
import '../rust/api.dart' as rust_api;

part 'discovery.g.dart';

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
/// On Android (v0.5 S3) the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` — without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The lock
/// is released in a `finally` so a failed discover still frees it. Other
/// platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android dropping
/// SSDP replies, not a precondition. If acquire fails (no Wi-Fi service,
/// permission denied — the native handler returns a structured error), we
/// still attempt discovery rather than hard-failing.
@riverpod
class Discovery extends _$Discovery {
  @override
  Future<rust_api.Topology> build() async {
    if (Platform.isAndroid) {
      final acquired = await _tryLock(AndroidMulticastLock.acquire);
      try {
        return await rust_api.discover();
      } finally {
        if (acquired) await _tryLock(AndroidMulticastLock.release);
      }
    }
    return rust_api.discover();
  }

  /// v0.5.1 (Option D): fast topology re-pull (no SSDP). Replaces the wire via
  /// Rust `refreshTopology()` (re-pull authoritative topology, ~tens of ms, then a
  /// fresh seeded wire) and publishes the new `Topology`. Setting `state` to a
  /// new `AsyncValue.data` IS a `discoveryProvider` transition, so
  /// `wireGenerationProvider` recomputes and `changeEventsProvider`
  /// re-subscribes against the new wire's fresh pump — events keep flowing
  /// after a regroup.
  ///
  /// No multicast lock here: `refreshTopology()` skips SSDP, so there are no
  /// inbound multicast replies for Android to drop. On error this throws; the
  /// caller (`topologyController`) falls back to a full re-discover.
  Future<void> refreshTopology() async {
    state = AsyncValue.data(await rust_api.refreshTopology());
  }
}

/// Run a multicast-lock op, swallowing a `PlatformException` (lock is
/// best-effort). Returns whether it succeeded — so `release` is only
/// attempted when `acquire` succeeded.
Future<bool> _tryLock(Future<void> Function() op) async {
  try {
    await op();
    return true;
  } on PlatformException {
    return false;
  }
}
