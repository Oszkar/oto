/// View-model group type and playback-state enum. Immutable,
/// value-comparable. A group is one set of rooms playing in sync, with a
/// coordinator. Mapped from backend topology/state by Task 3's reducer.
library;

import 'package:flutter/foundation.dart' show listEquals;

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

  /// Whether this group is currently a "source": it has a track, or a
  /// transport that is set and not stopped. Idle/stopped groups are not
  /// sources.
  bool get hasActiveStream =>
      track != null ||
      (transport != null && transport != PlaybackState.stopped);

  GroupState copyWith({
    String? id,
    String? coordinatorId,
    List<String>? memberIds,
    PlaybackState? transport,
    Track? track,
    int? groupVolume,
    bool? groupMuted,
  }) => GroupState(
    id: id ?? this.id,
    coordinatorId: coordinatorId ?? this.coordinatorId,
    memberIds: memberIds ?? this.memberIds,
    transport: transport ?? this.transport,
    track: track ?? this.track,
    groupVolume: groupVolume ?? this.groupVolume,
    groupMuted: groupMuted ?? this.groupMuted,
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
