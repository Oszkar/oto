/// v0.5 (S1) — topology-change controller.
///
/// Listens on the unified [changeEventsProvider] for
/// [rust_api.ChangeEventDto_TopologyChanged] notifications (emitted when
/// the Sonos household is regrouped) and, after a 250 ms debounce window,
/// invalidates [discoveryProvider] to re-pull the authoritative topology.
///
/// **Debounce rationale.** A single regroup fires one `GroupMembership`
/// NOTIFY per affected speaker (see docs/sonos-notes.md § "Topology change
/// events"), so the controller sees a burst of `TopologyChanged` events.
/// The 250 ms window coalesces the burst into exactly one re-pull once the
/// household settles.
///
/// **Why a full re-discover (Option A) rather than a lightweight refresh.**
/// v0.5 S1 deliberately uses the proven cold-start path: invalidating
/// [discoveryProvider] re-runs `discover()`, which rebuilds the wire +
/// event pump + topology + caches from scratch — correct by construction,
/// with no risk of stale event-routing after a regroup (the pump's
/// coordinator→group maps are frozen at subscribe time). The lightweight
/// SOAP-only fast path (`refresh_topology`, ~50 ms, no SSDP) is deferred to
/// v0.6 when the UI makes the ~3-5 s re-discover latency user-visible; the
/// controller's contract (TopologyChanged → debounce → re-pull) is
/// identical, so that future swap is a one-line change. See the v0.5 plan
/// Task 5 (Option A).
///
/// Activated by watching [topologyControllerProvider]. The v0.6 UI watches
/// it once the app shell exists (the same way it will watch
/// [discoveryProvider]); until then it is exercised by tests.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;
import 'discovery.dart';
import 'events.dart';

part 'topology.g.dart';

/// Debounce window. A single regroup fans out one NOTIFY per affected
/// speaker; this coalesces the burst into one re-pull.
const _debounceWindow = Duration(milliseconds: 250);

/// Side-effect controller (no exposed state). `keepAlive` so the
/// subscription + debounce timer live for the app lifetime once activated;
/// builds once (uses `ref.listen`, never `ref.watch`, so a new event does
/// not rebuild it).
@Riverpod(keepAlive: true)
void topologyController(Ref ref) {
  Timer? debounce;
  ref.onDispose(() {
    debounce?.cancel();
    debounce = null;
  });

  ref.listen(changeEventsProvider, (previous, next) {
    next.whenData((event) {
      if (event is rust_api.ChangeEventDto_TopologyChanged) {
        // (Re)arm the debounce: each TopologyChanged within the window
        // resets it, so a per-speaker NOTIFY burst yields one re-pull.
        debounce?.cancel();
        debounce = Timer(_debounceWindow, () {
          ref.invalidate(discoveryProvider);
        });
      }
    });
  });
}
