import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../platform/android_multicast_lock.dart';
import '../rust/api.dart' as rust_api;

part 'discovery.g.dart';

/// WHY a topology was published, not which mechanism produced it.
///
/// `HouseholdNotifier` uses this to decide whether to reset stale per-speaker
/// health. The reset is optimistic - neither path carries per-speaker
/// reachability evidence (see the `clearHealth` comment in
/// `household_reducer.dart`) - so it is only justified when the user actually
/// asked for a rescan.
///
/// The distinction is deliberately about intent rather than "did SSDP run".
/// Several automatic paths also run a full `discover()`: `ref.invalidate` after
/// a `CommandError_NotFound` (commands.dart), and `topologyController`'s
/// fallback when a fast refresh throws (topology.dart). Labelling those by
/// mechanism made them clear health with no user action behind it - and the
/// second case is exactly the background-regroup path the fast-refresh
/// exclusion exists to protect, re-entering through its own error fallback.
enum TopologySource {
  /// The user asked for it: [Discovery.rediscover] (the "Scan network" /
  /// "Retry" buttons). The only source that clears carried health.
  userScan,

  /// Everything else - app start, a `NotFound` re-discover, the fast-refresh
  /// fallback, or a fast `refreshTopology()`. Carries health forward.
  automatic,
}

/// LAN discovery + the v0.5.1 topology fast-path.
///
/// An async Notifier (not a plain Future provider) so it can expose
/// [Discovery.refreshTopology] alongside the deferred `build()` discover.
/// `ref.watch(discoveryProvider)` still yields an `AsyncValue<Topology>`, so
/// every existing consumer (incl. `events.dart`'s `wireGenerationProvider`)
/// is unchanged - and a `refreshTopology()` re-pull still surfaces as a
/// `discoveryProvider` transition, which is what drives the event stream to
/// re-subscribe against the new wire (see [Discovery.refreshTopology]).
///
/// `build()` runs the full `discover()`: Rust SSDP (~3–5 s) + GetZoneGroupState.
/// FRB runs it off the UI isolate, so AsyncValue gives loading / error / data;
/// user-facing retries go through [Discovery.rediscover] so the UI can show a
/// fresh scanning state immediately.
///
/// On Android the SSDP window is wrapped in a held
/// `WifiManager.MulticastLock` - without it Android drops the inbound
/// multicast replies and discovery finds nothing on release builds. The lock
/// is released in a `finally` so a failed discover still frees it. Other
/// platforms call `discover()` directly (no channel handler exists).
///
/// The lock is **best-effort**: it's an optimization to stop Android dropping
/// SSDP replies, not a precondition. If acquire fails (no Wi-Fi service,
/// permission denied - the native handler returns a structured error), we
/// still attempt discovery rather than hard-failing.
@riverpod
class Discovery extends _$Discovery {
  /// The most recent topology paired with the path that produced it.
  ///
  /// Deliberately ONE field holding both halves: a bare "last source" flag is a
  /// side channel that can describe a different topology than the one a
  /// listener is folding. `build()` completes asynchronously and Riverpod
  /// publishes its value some microtasks later, so a `refreshTopology()` that
  /// lands in between would leave a bare flag pointing at the wrong result.
  /// Consumers identity-match against [topology] and fall back to carrying
  /// health forward when it does not match - the conservative direction (a
  /// missed reset, never a spurious one).
  ({rust_api.Topology topology, TopologySource source})? lastPublish;

  /// Set by [rediscover] and consumed by the next [build]. A bare "this was a
  /// full discovery" label was wrong: `ref.invalidate(discoveryProvider)` also
  /// re-runs `build()`, and those callers are automatic. Invalidation
  /// constructs a FRESH notifier, so this flag resets to false for them - only
  /// [rediscover], which calls `build()` on the existing instance, can set it.
  bool _userRequested = false;

  @override
  Future<rust_api.Topology> build() async {
    // Read-and-clear up front, so a throwing discover still consumes the flag
    // and a later automatic rebuild cannot inherit it.
    final source = _userRequested
        ? TopologySource.userScan
        : TopologySource.automatic;
    _userRequested = false;
    if (Platform.isAndroid) {
      final acquired = await _tryLock(AndroidMulticastLock.acquire);
      try {
        final topo = await rust_api.discover();
        lastPublish = (topology: topo, source: source);
        return topo;
      } finally {
        if (acquired) await _tryLock(AndroidMulticastLock.release);
      }
    }
    final topo = await rust_api.discover();
    lastPublish = (topology: topo, source: source);
    return topo;
  }

  /// User-initiated full SSDP discovery retry.
  ///
  /// Publishing a fresh loading state first makes retry feedback visible
  /// immediately instead of leaving the old error UI on screen for the SSDP
  /// window. A *failed* retry ends in `AsyncError` (no retained value), but the
  /// live event stream is NOT torn down: `events.dart`'s `wireGeneration` reads
  /// the authoritative Rust generation, not `discovery.hasValue`, so it keeps
  /// returning the installed (old) wire's generation across a failed retry.
  Future<void> rediscover() async {
    // The one path the user drives. `build()` consumes this.
    _userRequested = true;
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
    final topo = await rust_api.refreshTopology();
    lastPublish = (topology: topo, source: TopologySource.automatic);
    _publishInstalledWire(topo);
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
/// [discoveryProvider] - specifically a value-equal fast `refreshTopology()`
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
  /// meaningless - only that it changes matters.
  void bump() => state = state + 1;
}

@riverpod
class DiscoveryRetrying extends _$DiscoveryRetrying {
  @override
  bool build() => false;

  void setRetrying(bool value) => state = value;
}

/// Run a multicast-lock op, swallowing a `PlatformException` (lock is
/// best-effort). Returns whether it succeeded - so `release` is only
/// attempted when `acquire` succeeded.
Future<bool> _tryLock(Future<void> Function() op) async {
  try {
    await op();
    return true;
  } on PlatformException {
    return false;
  }
}
