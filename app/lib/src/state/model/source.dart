/// The "source" view-model — the central UI abstraction. A source is one
/// group that is currently playing (or has a track). Derived from a
/// [Household] by [sourcesFromHousehold].
library;

import 'household.dart';
import 'track.dart';

/// One active source: a playing group, surfaced to the UI with a
/// human-readable [label] and its [memberCount]. Value-comparable.
class Source {
  final String id;
  final String label;
  final Track? track;
  final int memberCount;

  const Source({
    required this.id,
    required this.label,
    this.track,
    required this.memberCount,
  });

  Source copyWith({
    String? id,
    String? label,
    Track? track,
    int? memberCount,
  }) => Source(
    id: id ?? this.id,
    label: label ?? this.label,
    track: track ?? this.track,
    memberCount: memberCount ?? this.memberCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Source &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          track == other.track &&
          memberCount == other.memberCount;

  @override
  int get hashCode => Object.hash(id, label, track, memberCount);
}

/// Derive the active sources from a household: one [Source] per group with
/// `hasActiveStream`, labelled by its member room names joined with `" + "`.
/// Idle/stopped groups are excluded. Order is deterministic (sorted by label).
List<Source> sourcesFromHousehold(Household h) {
  final out = <Source>[];
  for (final g in h.groups.values) {
    if (!g.hasActiveStream) continue;
    final names = g.memberIds.map((id) => h.rooms[id]?.name ?? id).toList();
    out.add(
      Source(
        id: g.id,
        label: names.join(' + '),
        track: g.track,
        memberCount: g.memberIds.length,
      ),
    );
  }
  out.sort((a, b) => a.label.compareTo(b.label));
  return out;
}
