/// View-model group type and playback-state enum. Immutable,
/// value-comparable. A group is one set of rooms playing in sync, with a
/// coordinator. Mapped from backend topology/state by Task 3's reducer.
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'copy_with.dart';
import 'track.dart';

/// Transport state of a group's coordinator. Mirrors the backend
/// `PlaybackStateDto`; the DTO→view mapping lives in Task 3, NOT here.
enum PlaybackState { stopped, playing, paused, transitioning }

/// One synchrony group: a coordinator plus its members, with the current
/// transport, track, and group-master volume/mute.
///
/// `memberIds` is a collection field, so equality compares it with
/// [listEquals] and the hash folds it with [Object.hashAll]. A bare
/// `Object.hash(memberIds)` would hash by identity and silently break
/// Riverpod `select` — the #1 bug this design guards against.
class GroupState {
  final String id;
  final String coordinatorId;
  final List<String> memberIds;
  final PlaybackState? transport;
  final Track? track;
  final int? groupVolume;
  final bool? groupMuted;

  const GroupState({
    required this.id,
    required this.coordinatorId,
    required this.memberIds,
    this.transport,
    this.track,
    this.groupVolume,
    this.groupMuted,
  });

  /// Whether this group is currently a "source": something is playing here, or
  /// a real track is loaded and paused/transitioning. Idle/stopped groups, and
  /// groups carrying only a stale/empty track (Sonos emits an EMPTY track on
  /// stop, which the reducer can't null out — see [Track.hasContent]), are NOT
  /// sources.
  ///
  /// - `playing` is always a source (true even before track metadata lands).
  /// - otherwise a content-bearing track that isn't stopped (paused /
  ///   transitioning) is a resumable source.
  /// A non-stopped transport with no real track (a cleared/empty track or a
  /// bare paused state) is NOT a source — that was the phantom-"Playing" bug.
  bool get hasActiveStream =>
      transport == PlaybackState.playing ||
      (track != null &&
          track!.hasContent &&
          transport != null &&
          transport != PlaybackState.stopped);

  /// Nullable fields default to the [keep] sentinel so they can be explicitly
  /// cleared to `null` (the `x ?? this.x` idiom can only set-or-keep, never
  /// clear; the optimistic-command rollback needs to restore a cold-start
  /// `null`). [orKeep] resolves each against the current value. Non-nullable
  /// fields keep the simple `?? this.x` form.
  GroupState copyWith({
    String? id,
    String? coordinatorId,
    List<String>? memberIds,
    Object? transport = keep,
    Object? track = keep,
    Object? groupVolume = keep,
    Object? groupMuted = keep,
  }) => GroupState(
    id: id ?? this.id,
    coordinatorId: coordinatorId ?? this.coordinatorId,
    memberIds: memberIds ?? this.memberIds,
    transport: orKeep(transport, this.transport),
    track: orKeep(track, this.track),
    groupVolume: orKeep(groupVolume, this.groupVolume),
    groupMuted: orKeep(groupMuted, this.groupMuted),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupState &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          coordinatorId == other.coordinatorId &&
          listEquals(memberIds, other.memberIds) &&
          transport == other.transport &&
          track == other.track &&
          groupVolume == other.groupVolume &&
          groupMuted == other.groupMuted;

  @override
  int get hashCode => Object.hash(
    id,
    coordinatorId,
    Object.hashAll(memberIds),
    transport,
    track,
    groupVolume,
    groupMuted,
  );
}
