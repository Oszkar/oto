/// Topology-change controller. Fast SSDP-skipping re-discover since v0.5.1.
///
/// Listens on the unified [changeEventsProvider] for
/// [rust_api.ChangeEventDto_TopologyChanged] notifications (emitted when
/// the Sonos household is regrouped) and, after a 250 ms debounce window,
/// re-pulls the authoritative topology.
///
/// **Debounce rationale.** A single regroup fires one `GroupMembership`
/// NOTIFY per affected speaker (see docs/sonos-notes.md § "Topology change
/// events"), so the controller sees a burst of `TopologyChanged` events.
/// The 250 ms window coalesces the burst into exactly one re-pull once the
/// household settles.
///
/// **Fast re-discover (no SSDP).** The debounce body calls
/// `Discovery.refreshTopology()` — a re-pull that SKIPS SSDP (~tens of ms vs the
/// ~3–5 s of a full `discover()`), then installs a fresh seeded wire through
/// the same wire-replacement lifecycle. `refreshTopology()` re-keys the event
/// stream itself (it bumps the wire-install signal that `wireGenerationProvider`
/// watches — see `Discovery._publishInstalledWire`), so the new wire's fresh
/// pump (clean `TopologyFilter`) is picked up even when the new `Topology` is
/// value-equal to the old (a no-op `TopologyChanged`) and `discoveryProvider`
/// does not transition. If the fast re-pull throws (e.g. every cached speaker is
/// now unreachable), it falls back to a full re-discover via
/// `ref.invalidate(discoveryProvider)`.
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
        debounce = Timer(_debounceWindow, () async {
          // Fast re-discover (no SSDP). On failure (e.g. every
          // cached speaker is now unreachable) fall back to a full
          // re-discover, which re-runs SSDP.
          try {
            // refreshTopology() re-keys the event stream itself — it bumps the
            // wire-install signal so changeEventsProvider re-subscribes against
            // the new wire even on a value-equal re-pull that does not transition
            // discoveryProvider (see Discovery._publishInstalledWire). Nothing to
            // invalidate here.
            await ref.read(discoveryProvider.notifier).refreshTopology();
          } catch (_) {
            ref.invalidate(discoveryProvider);
          }
        });
      }
    });
  });
}
