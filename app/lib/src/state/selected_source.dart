/// Which source the wide detail pane shows, tracked by the STABLE coordinator
/// id, plus the resolved group id the pane actually renders.
///
/// A group's `id` churns on every regroup; its `coordinatorId` does not (the
/// reducer already carries group state forward by coordinator for exactly this
/// reason). Keying the selection off the coordinator makes a pick survive a
/// regroup, and lets the auto default stay "sticky" instead of yanking to
/// whichever source happens to sort first. Backs the responsive three-pane
/// layout's detail column.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'household.dart';
import 'model/source.dart';
import 'sources.dart';

part 'selected_source.g.dart';

/// The pane's chosen source: the [coord]inator id it tracks (null = nothing
/// active), and whether that pick was an explicit user tap ([pinned]) or an
/// auto latch. An explicit pin stays put even when its source goes idle, until
/// its group vanishes; an auto latch follows the first active source and moves
/// on once the current one stops.
typedef PaneSource = ({String? coord, bool pinned});

/// Tracks the coordinator the wide detail pane shows, reconciling on every
/// active-source change (finding: a plain "first active source" default jumps
/// whenever another room starts/stops).
@riverpod
class SelectedSource extends _$SelectedSource {
  @override
  PaneSource build() {
    // Reconcile via `listen`, NOT `watch`: watching `sources` would re-run
    // build() on every source delta and wipe an explicit pick. Seed the initial
    // latch from a one-shot read so build() takes no dependency on it.
    ref.listen(sourcesProvider, (_, next) => _reconcile(next));
    // Also reconcile when the SET of coordinators changes: an idle pin whose
    // coordinator vanishes leaves the active-source list value-equal, so the
    // `sources` listener alone would never fire and the pin would go stale.
    // Project to a value-equal String so this fires only on topology-shape
    // changes (regroup, room add/remove), never on per-event playback ticks.
    ref.listen(
      householdProvider.select(
        (h) =>
            (h.groups.values.map((g) => g.coordinatorId).toList()..sort())
                .join(','),
      ),
      (_, _) => _reconcile(ref.read(sourcesProvider)),
    );
    return (coord: _firstActive(ref.read(sourcesProvider)), pinned: false);
  }

  /// Pin the group's coordinator (stable across regroup) as the shown source.
  /// A no-op for an unknown group id, leaving the current pick untouched.
  void select(String groupId) {
    final coord = ref.read(householdProvider).groups[groupId]?.coordinatorId;
    if (coord != null) state = (coord: coord, pinned: true);
  }

  /// Drop back to auto-follow, re-latching onto the current first active source.
  void clear() => _reconcile(ref.read(sourcesProvider), forceAuto: true);

  /// Keep the current pick while it is still valid; otherwise latch onto the
  /// first active source. "Valid" = still an active source, or (for an explicit
  /// pin) a still-existing group even when idle.
  void _reconcile(List<Source> sources, {bool forceAuto = false}) {
    final current = state.coord;
    if (!forceAuto && current != null) {
      final stillActive = sources.any((s) => s.coordinatorId == current);
      if (stillActive) return; // sticky: current source is still playing
      if (state.pinned && _coordExists(current)) return; // idle explicit pin
    }
    state = (coord: _firstActive(sources), pinned: false);
  }

  bool _coordExists(String coord) => ref
      .read(householdProvider)
      .groups
      .values
      .any((g) => g.coordinatorId == coord);

  static String? _firstActive(List<Source> sources) =>
      sources.isEmpty ? null : sources.first.coordinatorId;
}

/// The group id the detail pane should render: the tracked coordinator mapped
/// to its CURRENT group (active or idle, so a regroup or an idle explicit pin
/// still resolves), else the first active source, else null (empty pane).
///
/// The coordinator -> group-id mapping is done inside a `select` so this only
/// recomputes when that id (or the active-source list) actually changes, not on
/// every unrelated group event that rebuilds the `groups` map.
@riverpod
String? resolvedSource(Ref ref) {
  final coord = ref.watch(selectedSourceProvider).coord;
  final mapped = coord == null
      ? null
      : ref.watch(
          householdProvider.select((h) {
            for (final g in h.groups.values) {
              if (g.coordinatorId == coord) return g.id;
            }
            return null;
          }),
        );
  if (mapped != null) return mapped;
  final sources = ref.watch(sourcesProvider);
  return sources.isEmpty ? null : sources.first.id;
}
