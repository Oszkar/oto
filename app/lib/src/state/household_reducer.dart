/// The household reducer — the pure state spine of the v0.6 UI.
///
/// Two pure functions, no Riverpod / no I/O, so the whole accumulation
/// model is unit-testable without a `ProviderContainer`:
///
/// * [householdFromTopology] builds the identity skeleton from a discovery
///   [Topology] (rooms, groups, names, membership, coordinator), preserving
///   per-speaker live state and carrying per-group live state across a
///   regroup (group ids change; coordinators are stable).
/// * [applyEvent] folds one [ChangeEventDto] delta into a new [Household].
///
/// Group volume/mute are event-only (no getter), so accumulating the event
/// stream here is the only way the UI ever learns them.
library;

import '../rust/api.dart';
import 'model/group_state.dart';
import 'model/household.dart';
import 'model/room_state.dart';
import 'model/track.dart';

/// Build the household skeleton from a discovery [Topology].
///
/// Per-speaker live state (`volume`/`muted`/`online`) is carried from
/// [previous] by speaker id. Per-group live state
/// (`transport`/`track`/`groupVolume`/`groupMuted`) is carried from the
/// previous group that shared the SAME coordinator — group ids churn across a
/// regroup, but coordinators are stable, so this keeps now-playing and group
/// volume/mute alive through a regroup.
Household householdFromTopology(Topology topo, {Household? previous}) {
  final speakerToGroup = <String, String>{};
  for (final g in topo.groups) {
    for (final m in g.members) {
      speakerToGroup[m] = g.id;
    }
  }

  final rooms = <String, RoomState>{};
  for (final s in topo.speakers) {
    final prev = previous?.rooms[s.id];
    rooms[s.id] = RoomState(
      id: s.id,
      name: s.roomName,
      model: s.model,
      kind: roomKindFromModel(s.model),
      groupId: speakerToGroup[s.id],
      volume: prev?.volume,
      muted: prev?.muted,
      online: prev?.online ?? true,
    );
  }

  final prevByCoord = <String, GroupState>{};
  if (previous != null) {
    for (final pg in previous.groups.values) {
      prevByCoord[pg.coordinatorId] = pg;
    }
  }

  final groups = <String, GroupState>{};
  for (final g in topo.groups) {
    final carry = prevByCoord[g.coordinator];
    groups[g.id] = GroupState(
      id: g.id,
      coordinatorId: g.coordinator,
      // Defensive copy: the model claims immutability but exposes a plain
      // `List`; `g.members` is an FRB-owned list. Wrap so a holder can't
      // mutate it out from under Riverpod's value equality.
      memberIds: List.unmodifiable(g.members),
      transport: carry?.transport,
      track: carry?.track,
      groupVolume: carry?.groupVolume,
      groupMuted: carry?.groupMuted,
    );
  }

  // Wrap the maps too - every production Household is then deeply immutable.
  return Household(
    rooms: Map.unmodifiable(rooms),
    groups: Map.unmodifiable(groups),
  );
}

/// Fold one [ChangeEventDto] delta into a new [Household].
///
/// Pure: returns a NEW household (via `copyWith` over a fresh map) when an
/// entity changes; returns the same instance for no-ops and events whose
/// speaker/group id is unknown.
Household applyEvent(Household h, ChangeEventDto e) {
  switch (e) {
    case ChangeEventDto_Volume(:final speakerId, :final volume):
      return _updateRoom(h, speakerId, (r) => r.copyWith(volume: volume));
    case ChangeEventDto_Mute(:final speakerId, :final muted):
      return _updateRoom(h, speakerId, (r) => r.copyWith(muted: muted));
    case ChangeEventDto_Playback(:final groupId, :final state):
      return _updateGroup(
        h,
        groupId,
        (g) => g.copyWith(transport: playbackStateFromDto(state)),
      );
    case ChangeEventDto_Track(:final groupId, :final track):
      return _updateGroup(
        h,
        groupId,
        (g) => g.copyWith(track: Track.fromDto(track)),
      );
    case ChangeEventDto_GroupVolume(:final groupId, :final volume):
      return _updateGroup(h, groupId, (g) => g.copyWith(groupVolume: volume));
    case ChangeEventDto_GroupMute(:final groupId, :final muted):
      return _updateGroup(h, groupId, (g) => g.copyWith(groupMuted: muted));
    case ChangeEventDto_SubscriptionError(:final speakerId):
      return _updateRoom(h, speakerId, (r) => r.copyWith(online: false));
    case ChangeEventDto_SubscriptionRecovered(:final speakerId):
      return _updateRoom(h, speakerId, (r) => r.copyWith(online: true));
    case ChangeEventDto_TopologyChanged():
      // No-op: the topology controller re-discovers on this event, which
      // routes through `householdFromTopology`, not the reducer.
      return h;
  }
}

/// Apply [f] to the room [id] if it exists, returning a new household;
/// otherwise return [h] unchanged (unknown ids are ignored, never crash).
Household _updateRoom(Household h, String id, RoomState Function(RoomState) f) {
  final r = h.rooms[id];
  if (r == null) return h;
  return h.copyWith(rooms: Map.unmodifiable({...h.rooms, id: f(r)}));
}

/// Apply [f] to the group [id] if it exists, returning a new household;
/// otherwise return [h] unchanged (unknown ids are ignored, never crash).
Household _updateGroup(
  Household h,
  String id,
  GroupState Function(GroupState) f,
) {
  final g = h.groups[id];
  if (g == null) return h;
  return h.copyWith(groups: Map.unmodifiable({...h.groups, id: f(g)}));
}

/// Map the backend transport DTO to the view-model enum. The DTO boundary
/// lives here (not in `group_state.dart`), keeping the model file deps-free.
PlaybackState playbackStateFromDto(PlaybackStateDto d) => switch (d) {
  PlaybackStateDto.stopped => PlaybackState.stopped,
  PlaybackStateDto.playing => PlaybackState.playing,
  PlaybackStateDto.paused => PlaybackState.paused,
  PlaybackStateDto.transitioning => PlaybackState.transitioning,
};

/// Map the view-model enum back to the backend DTO — used by the optimistic
/// transport mutator (Task 4) so a UI-driven play/pause folds the same delta.
PlaybackStateDto playbackStateToDto(PlaybackState s) => switch (s) {
  PlaybackState.stopped => PlaybackStateDto.stopped,
  PlaybackState.playing => PlaybackStateDto.playing,
  PlaybackState.paused => PlaybackStateDto.paused,
  PlaybackState.transitioning => PlaybackStateDto.transitioning,
};
