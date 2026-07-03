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
/// user-facing retries go through [Discovery.rediscover] so the UI can show a
/// fresh scanning state immediately.
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

  /// User-initiated full SSDP discovery retry.
  ///
  /// `ref.invalidate(discoveryProvider)` keeps the previous error attached to
  /// the in-flight loading state. Publishing a fresh loading state first makes
  /// retry feedback visible immediately instead of leaving the old error UI on
  /// screen for the SSDP window.
  Future<void> rediscover() async {
    final retrying = ref.read(discoveryRetryingProvider.notifier);
    retrying.setRetrying(true);
    state = const AsyncLoading();
    try {
      state = await AsyncValue.guard(build);
    } finally {
      retrying.setRetrying(false);
    }
  }

  /// Fast topology re-pull (no SSDP). Replaces the wire via Rust
  /// `refreshTopology()` (re-pull authoritative topology, ~tens of ms, then a
  /// fresh seeded wire) and publishes the new `Topology` through
  /// [_publishInstalledWire], which also re-keys the event stream.
  ///
  /// No multicast lock here: `refreshTopology()` skips SSDP, so there are no
  /// inbound multicast replies for Android to drop. On error this throws; the
  /// caller (`topologyController`) falls back to a full re-discover.
  Future<void> refreshTopology() async {
    _publishInstalledWire(await rust_api.refreshTopology());
  }

  /// Publish a freshly re-pulled wire's [topology] AND re-key the event stream.
  ///
  /// The signal bump forces `wireGenerationProvider` (events.dart) to recompute
  /// even when [topology] is value-equal to the current one. A no-op regroup
  /// yields an unchanged `Topology`; because FRB `Topology` has value equality,
  /// re-publishing it does NOT transition `discoveryProvider`, so on its own it
  /// would leave the event stream subscribed to the REPLACED wire's now-dead
  /// one-shot receiver (events silently stop). Bumping the install signal makes
  /// `wireGenerationProvider` re-read the fresh Rust generation and re-subscribe.
  ///
  /// Co-located with the publish so any future fast (non-SSDP, non-transitioning)
  /// install that routes through here cannot reintroduce the value-equal-strand
  /// class by forgetting to signal.
  void _publishInstalledWire(rust_api.Topology topology) {
    state = AsyncValue.data(topology);
    ref.read(wireInstallSignalProvider.notifier).bump();
  }
}

/// A monotonic signal bumped on every wire install that may NOT transition
/// [discoveryProvider] — specifically a value-equal fast `refreshTopology()`
/// (a no-op regroup). `wireGenerationProvider` (events.dart) watches this to
/// force a re-read of the Rust generation so the event stream re-subscribes
/// against the new wire. Lives here because [Discovery] owns the wire lifecycle
/// and is the sole bumper; `events.dart` only consumes it (keeps the dependency
/// direction events → discovery, avoiding a cycle).
///
/// `keepAlive`: the count must persist for the app lifetime (it outlives any
/// single widget subscription and accumulates across regroups).
@Riverpod(keepAlive: true)
class WireInstallSignal extends _$WireInstallSignal {
  @override
  int build() => 0;

  /// Signal that a fresh wire was installed. Monotonic; the value itself is
  /// meaningless — only that it changes matters.
  void bump() => state = state + 1;
}

@riverpod
class DiscoveryRetrying extends _$DiscoveryRetrying {
  @override
  bool build() => false;

  void setRetrying(bool value) => state = value;
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
