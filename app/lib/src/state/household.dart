/// The accumulating household provider - the central state spine of the UI.
///
/// A keep-alive Notifier that seeds its skeleton from [discoveryProvider]
/// (identity: rooms, groups, membership, coordinator) and folds the live
/// [changeEventsProvider] deltas (volume, mute, transport, track, group
/// volume/mute) on top via the pure [household_reducer]. Group volume/mute
/// are event-only, so this accumulation is the only path to those values.
///
/// Optimistic mutators apply the same delta the authoritative event would,
/// so a command-driven change shows in the UI instantly (Task 4 calls these).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart';
import 'discovery.dart';
import 'events.dart';
import 'household_reducer.dart';
import 'model/group_state.dart';
import 'model/household.dart';

part 'household.g.dart';

/// Fields that commands can change optimistically. Group fields use the
/// coordinator's speaker id so observations survive a group-id change.
enum CommandField {
  roomVolume,
  roomMute,
  groupVolume,
  groupMute,
  transportToggle,
}

typedef CommandObservation = ({int topology, int revision});

@Riverpod(keepAlive: true)
class HouseholdNotifier extends _$HouseholdNotifier {
  Household _confirmed = const Household();
  int _topologyRevision = 0;
  int _eventRevision = 0;
  final _observations = <({String speakerId, CommandField field}), int>{};

  CommandObservation observation(String speakerId, CommandField field) => (
    topology: _topologyRevision,
    revision: _observations[(speakerId: speakerId, field: field)] ?? 0,
  );

  String? _confirmedGroupId(String coordinatorId) {
    for (final group in _confirmed.groups.values) {
      if (group.coordinatorId == coordinatorId) return group.id;
    }
    return null;
  }

  /// Last observed or successfully commanded value, never an in-flight guess.
  Object? confirmedValue(String speakerId, CommandField field) {
    final room = _confirmed.rooms[speakerId];
    final group = _confirmed.groups[_confirmedGroupId(speakerId)];
    return switch (field) {
      CommandField.roomVolume => room?.volume,
      CommandField.roomMute => room?.muted,
      CommandField.groupVolume => group?.groupVolume,
      CommandField.groupMute => group?.groupMuted,
      CommandField.transportToggle => group?.transport,
    };
  }

  /// A successful command needs no NOTIFY when the device value was unchanged.
  /// Keep that value for rediscovery, without replacing a newer optimistic UI
  /// intent. The scheduler calls this only if dispatch saw no newer observation.
  void confirmCommand(String speakerId, CommandField field, Object? value) {
    final groupId = _confirmedGroupId(speakerId);
    _confirmed = switch (field) {
      CommandField.roomVolume => updateRoom(
        _confirmed,
        speakerId,
        (r) => r.copyWith(volume: value),
      ),
      CommandField.roomMute => updateRoom(
        _confirmed,
        speakerId,
        (r) => r.copyWith(muted: value),
      ),
      CommandField.groupVolume => updateGroup(
        _confirmed,
        groupId ?? '',
        (g) => g.copyWith(groupVolume: value),
      ),
      CommandField.groupMute => updateGroup(
        _confirmed,
        groupId ?? '',
        (g) => g.copyWith(groupMuted: value),
      ),
      CommandField.transportToggle => updateGroup(
        _confirmed,
        groupId ?? '',
        (g) => g.copyWith(transport: value),
      ),
    };
    _recordObservation(speakerId, field);
  }

  void _recordObservation(String speakerId, CommandField field) {
    final known = switch (field) {
      CommandField.roomVolume ||
      CommandField.roomMute => _confirmed.rooms.containsKey(speakerId),
      _ => _confirmedGroupId(speakerId) != null,
    };
    if (known) {
      _observations[(speakerId: speakerId, field: field)] = ++_eventRevision;
    }
  }

  void _observeEvent(ChangeEventDto event) {
    _confirmed = applyEvent(_confirmed, event);
    switch (event) {
      case ChangeEventDto_Volume(:final speakerId):
        _recordObservation(speakerId, CommandField.roomVolume);
      case ChangeEventDto_Mute(:final speakerId):
        _recordObservation(speakerId, CommandField.roomMute);
      case ChangeEventDto_GroupVolume(:final groupId):
        final coordinator = _confirmed.groups[groupId]?.coordinatorId;
        if (coordinator != null) {
          _recordObservation(coordinator, CommandField.groupVolume);
        }
      case ChangeEventDto_GroupMute(:final groupId):
        final coordinator = _confirmed.groups[groupId]?.coordinatorId;
        if (coordinator != null) {
          _recordObservation(coordinator, CommandField.groupMute);
        }
      case ChangeEventDto_Playback(:final groupId):
        final coordinator = _confirmed.groups[groupId]?.coordinatorId;
        if (coordinator != null) {
          _recordObservation(coordinator, CommandField.transportToggle);
        }
      default:
        break;
    }
    state = applyEvent(state, event);
  }

  @override
  Household build() {
    // Future discovery transitions (regroup / re-discover) fold in here,
    // preserving confirmed per-speaker/-group state independently of the UI's
    // in-flight optimistic values.
    ref.listen(discoveryProvider, (_, next) {
      next.whenData((topo) {
        // Only a user-requested scan resets stale unreachable flags; every
        // automatic path carries them forward. See `TopologySource`.
        //
        // Identity-matched against the topology the source describes: `build()`
        // publishes some microtasks after it completes, so a `refreshTopology()`
        // landing in between could otherwise make a full-discovery result read
        // as a fast refresh. On a mismatch we carry health forward - a missed
        // reset (the user can scan again) rather than a spurious one.
        final last = ref.read(discoveryProvider.notifier).lastPublish;
        final userScan =
            last != null &&
            identical(last.topology, topo) &&
            last.source == TopologySource.userScan;
        _confirmed = householdFromTopology(
          topo,
          previous: _confirmed,
          clearHealth: userScan,
        );
        // A replacement starts from confirmed state, not an optimistic guess
        // made against the previous wire. No removed entity keeps a revision.
        _topologyRevision++;
        _observations.clear();
        state = _confirmed;
      });
    });
    ref.listen(changeEventsProvider, (_, next) {
      next.whenData(_observeEvent);
    });
    // Seed the INITIAL skeleton from discovery's current value. We read here
    // rather than rely on a `fireImmediately` listener: an immediate fire runs
    // during build(), so it would set `state` (reading an uninitialized `state`
    // via `previous: state`) only for `return const Household()` to overwrite
    // it -- leaving the UI empty whenever discovery already resolved before
    // this provider was first watched (codex review, PR #80).
    _confirmed = switch (ref.read(discoveryProvider)) {
      AsyncData(:final value) => householdFromTopology(value),
      _ => const Household(),
    };
    return _confirmed;
  }

  /// Optimistically reflect a per-speaker volume change before the event
  /// echoes back. Mirrors a `Volume` event.
  void setOptimisticVolume(String speakerId, int v) => state = applyEvent(
    state,
    ChangeEventDto.volume(speakerId: speakerId, volume: v),
  );

  /// Optimistically reflect a per-speaker mute change. Mirrors a `Mute` event.
  void setOptimisticMuted(String speakerId, bool m) => state = applyEvent(
    state,
    ChangeEventDto.mute(speakerId: speakerId, muted: m),
  );

  /// Optimistically reflect a group master volume change. Mirrors a
  /// `GroupVolume` event (the only path to a group volume value).
  void setOptimisticGroupVolume(String groupId, int v) => state = applyEvent(
    state,
    ChangeEventDto.groupVolume(groupId: groupId, volume: v),
  );

  /// Optimistically reflect a group master mute change. Mirrors a
  /// `GroupMute` event (the only path to a group mute value).
  void setOptimisticGroupMuted(String groupId, bool m) => state = applyEvent(
    state,
    ChangeEventDto.groupMute(groupId: groupId, muted: m),
  );

  /// Optimistically reflect a group transport change. Mirrors a `Playback`
  /// event; the view enum is mapped back to the DTO at the boundary.
  void setOptimisticTransport(String groupId, PlaybackState t) =>
      state = applyEvent(
        state,
        ChangeEventDto.playback(groupId: groupId, state: playbackStateToDto(t)),
      );

  // ── Rollback restores ──────────────────────────────────────────────────
  //
  // Unlike the optimistic setters above (which mirror a non-null event), these
  // restore a field to its PRE-gesture value, which may be `null` at cold-start
  // - before any event has landed. The optimistic-event path can't express a
  // `null` (a `ChangeEventDto` always carries a concrete value), so rollback
  // folds through `copyWith` directly, whose sentinel form clears to `null`.
  // Without this a failed command on a never-yet-observed field would leave a
  // fabricated value standing (most reachable for group volume/mute, which are
  // event-only and often `null` until the user's first change).

  /// Restore a room's volume to [v] (may be `null`) after a failed command.
  void restoreVolume(String speakerId, int? v) =>
      state = updateRoom(state, speakerId, (r) => r.copyWith(volume: v));

  /// Restore a room's mute to [m] (may be `null`) after a failed command.
  void restoreMuted(String speakerId, bool? m) =>
      state = updateRoom(state, speakerId, (r) => r.copyWith(muted: m));

  /// Restore a group's master volume to [v] (may be `null`).
  void restoreGroupVolume(String groupId, int? v) =>
      state = updateGroup(state, groupId, (g) => g.copyWith(groupVolume: v));

  /// Restore a group's master mute to [m] (may be `null`).
  void restoreGroupMuted(String groupId, bool? m) =>
      state = updateGroup(state, groupId, (g) => g.copyWith(groupMuted: m));

  void restoreTransport(String groupId, PlaybackState? transport) => state =
      updateGroup(state, groupId, (g) => g.copyWith(transport: transport));
}
