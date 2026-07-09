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

@Riverpod(keepAlive: true)
class HouseholdNotifier extends _$HouseholdNotifier {
  @override
  Household build() {
    // Future discovery transitions (regroup / re-discover) fold in here,
    // preserving accumulated per-speaker/-group state via `previous: state`.
    ref.listen(discoveryProvider, (_, next) {
      next.whenData(
        (topo) => state = householdFromTopology(topo, previous: state),
      );
    });
    ref.listen(changeEventsProvider, (_, next) {
      next.whenData((e) => state = applyEvent(state, e));
    });
    // Seed the INITIAL skeleton from discovery's current value. We read here
    // rather than rely on a `fireImmediately` listener: an immediate fire runs
    // during build(), so it would set `state` (reading an uninitialized `state`
    // via `previous: state`) only for `return const Household()` to overwrite
    // it -- leaving the UI empty whenever discovery already resolved before
    // this provider was first watched (codex review, PR #80).
    return switch (ref.read(discoveryProvider)) {
      AsyncData(:final value) => householdFromTopology(value),
      _ => const Household(),
    };
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

  /// Restore a group's master volume to [v] (may be `null`).
  void restoreGroupVolume(String groupId, int? v) =>
      state = updateGroup(state, groupId, (g) => g.copyWith(groupVolume: v));

  /// Restore a group's master mute to [m] (may be `null`).
  void restoreGroupMuted(String groupId, bool? m) =>
      state = updateGroup(state, groupId, (g) => g.copyWith(groupMuted: m));
}
