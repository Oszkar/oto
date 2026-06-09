/// Optimistic, LAN-polite command controllers (Task 4).
///
/// Commands update local household state **instantly** (optimistic), then fire
/// the SOAP command and let the authoritative event reconcile. Volume drags are
/// throttled (≤1 SOAP / 150 ms, trailing) plus one final send on release — the
/// LAN-politeness non-negotiable: never one command per slider pixel.
///
/// Reconciliation (shared via [_Reconciling]): a `CommandError_NotFound` means a
/// stale identifier, so we re-discover; any other error rolls the optimistic
/// value back. A *successful* no-op set emits no echo (Sonos suppresses
/// unchanged values), so a standing optimistic value is correct — we **never**
/// revert for lack of an echo, only on a thrown error.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;
import '../rust/api.dart' show CommandError, CommandError_NotFound;
import 'discovery.dart';
import 'household.dart';
import 'model/group_state.dart';
import 'throttle.dart';

part 'commands.g.dart';

/// Indirection over the FRB command functions so tests can subclass/override
/// it to spy on calls and inject thrown [CommandError]s without touching Rust.
class CommandApi {
  const CommandApi();

  Future<void> play(String groupId) => rust_api.play(groupId: groupId);
  Future<void> pause(String groupId) => rust_api.pause(groupId: groupId);
  Future<void> next(String groupId) => rust_api.next(groupId: groupId);
  Future<void> previous(String groupId) => rust_api.previous(groupId: groupId);
  Future<void> setVolume(String speakerId, int v) =>
      rust_api.setVolume(speakerId: speakerId, volume: v);
  Future<void> setMute(String speakerId, bool m) =>
      rust_api.setMute(speakerId: speakerId, muted: m);
  Future<void> joinGroup(String speakerId, String coordinatorId) =>
      rust_api.joinGroup(speakerId: speakerId, coordinatorId: coordinatorId);
  Future<void> leaveGroup(String speakerId) =>
      rust_api.leaveGroup(speakerId: speakerId);
  Future<void> setGroupVolume(String groupId, int v) =>
      rust_api.setGroupVolume(groupId: groupId, volume: v);
  Future<void> setGroupMute(String groupId, bool m) =>
      rust_api.setGroupMute(groupId: groupId, muted: m);
}

/// Shared optimistic-command reconciliation. Runs [op]; on a thrown
/// [CommandError] it either re-discovers (stale id → `NotFound`) or rolls back
/// (any other error). Keeps `send`/error handling DRY across both controllers.
mixin _Reconciling {
  Ref get ref;

  Future<void> send(Future<void> Function() op, {void Function()? rollback}) async {
    try {
      await op();
    } on CommandError catch (e) {
      if (e is CommandError_NotFound) {
        // Stale identifier — re-discover (sonos-notes § Identifiers).
        ref.invalidate(discoveryProvider);
      } else {
        // Sonos device-reject / Network unreachable → roll back. A *successful*
        // no-op emits no echo, so a standing optimistic value is correct;
        // rollback only on a thrown error.
        rollback?.call();
      }
    }
  }
}

/// Transport + per-speaker volume commands, optimistic and LAN-throttled.
class PlaybackController with _Reconciling {
  PlaybackController(this.ref, this.api);
  @override
  final Ref ref;
  final CommandApi api;
  final _volThrottle = <String, Throttle>{};
  // Pre-gesture volume per speaker, captured once per drag, for rollback.
  final _volAnchor = <String, int?>{};

  HouseholdNotifier get _h => ref.read(householdProvider.notifier);

  /// Flip transport optimistically and fire play/pause. On a stale-id error the
  /// shared reconciler re-discovers; on any other error it rolls transport back.
  Future<void> togglePlay(String groupId, PlaybackState current) async {
    final next = current == PlaybackState.playing
        ? PlaybackState.paused
        : PlaybackState.playing;
    _h.setOptimisticTransport(groupId, next);
    await send(
      () => next == PlaybackState.playing ? api.play(groupId) : api.pause(groupId),
      rollback: () => _h.setOptimisticTransport(groupId, current),
    );
  }

  /// Skip to the next track. No optimistic state: the authoritative `Track`
  /// event drives the change, and the shared [send] re-discovers on a stale-id
  /// `NotFound`. (Deferred from Task 4 to the Now Playing screen.)
  Future<void> next(String groupId) => send(() => api.next(groupId));

  /// Skip to the previous track. Same no-optimistic-state rationale as [next].
  Future<void> previous(String groupId) => send(() => api.previous(groupId));

  /// Mid-drag volume: optimistic now, SOAP send throttled to the trailing edge.
  void setVolume(String speakerId, int v) {
    _volAnchor.putIfAbsent(
      speakerId,
      () => ref.read(householdProvider).rooms[speakerId]?.volume,
    );
    _h.setOptimisticVolume(speakerId, v);
    _volThrottle
        .putIfAbsent(speakerId, () => Throttle(const Duration(milliseconds: 150)))
        .run(() => send(
              () => api.setVolume(speakerId, v),
              rollback: () => _rollbackVolume(speakerId),
            ));
  }

  /// Drag release: send the final value exactly once. Cancel the pending
  /// trailing send (dispose, do NOT flush) — flush() + this explicit send would
  /// double-fire the SOAP call.
  void setVolumeEnd(String speakerId, int v) {
    // Capture the anchor if a mid-drag setVolume never ran (e.g. a tap-to-set,
    // or the end fires alone) so the rollback target is the pre-gesture value.
    _volAnchor.putIfAbsent(
      speakerId,
      () => ref.read(householdProvider).rooms[speakerId]?.volume,
    );
    _h.setOptimisticVolume(speakerId, v);
    _volThrottle.remove(speakerId)?.dispose();
    send(() => api.setVolume(speakerId, v),
            rollback: () => _rollbackVolume(speakerId))
        .whenComplete(() => _volAnchor.remove(speakerId)); // gesture done.
  }

  void _rollbackVolume(String speakerId) {
    final prev = _volAnchor[speakerId];
    if (prev != null) _h.setOptimisticVolume(speakerId, prev);
  }
}

/// Group form/break + group volume/mute commands. Form/break do NOT mutate
/// membership optimistically — the topology event path (GroupMembership NOTIFY
/// → debounced topology re-pull) drives that update.
class GroupingController with _Reconciling {
  GroupingController(this.ref, this.api);
  @override
  final Ref ref;
  final CommandApi api;
  final _gVolThrottle = <String, Throttle>{};
  final _gVolAnchor = <String, int?>{};

  HouseholdNotifier get _h => ref.read(householdProvider.notifier);

  Future<void> joinGroup(String speakerId, String coordinatorId) =>
      send(() => api.joinGroup(speakerId, coordinatorId));

  Future<void> leaveGroup(String speakerId) =>
      send(() => api.leaveGroup(speakerId));

  void setGroupVolume(String groupId, int v) {
    _gVolAnchor.putIfAbsent(
      groupId,
      () => ref.read(householdProvider).groups[groupId]?.groupVolume,
    );
    _h.setOptimisticGroupVolume(groupId, v);
    _gVolThrottle
        .putIfAbsent(groupId, () => Throttle(const Duration(milliseconds: 150)))
        .run(() => send(
              () => api.setGroupVolume(groupId, v),
              rollback: () => _rollbackGroupVolume(groupId),
            ));
  }

  void setGroupVolumeEnd(String groupId, int v) {
    // Capture the anchor if a mid-drag setGroupVolume never ran (see
    // PlaybackController.setVolumeEnd) so the rollback target is pre-gesture.
    _gVolAnchor.putIfAbsent(
      groupId,
      () => ref.read(householdProvider).groups[groupId]?.groupVolume,
    );
    _h.setOptimisticGroupVolume(groupId, v);
    _gVolThrottle.remove(groupId)?.dispose();
    send(() => api.setGroupVolume(groupId, v),
            rollback: () => _rollbackGroupVolume(groupId))
        .whenComplete(() => _gVolAnchor.remove(groupId));
  }

  Future<void> setGroupMute(String groupId, bool muted) {
    final prev = ref.read(householdProvider).groups[groupId]?.groupMuted;
    _h.setOptimisticGroupMuted(groupId, muted);
    return send(
      () => api.setGroupMute(groupId, muted),
      rollback: () {
        if (prev != null) _h.setOptimisticGroupMuted(groupId, prev);
      },
    );
  }

  void _rollbackGroupVolume(String groupId) {
    final prev = _gVolAnchor[groupId];
    if (prev != null) _h.setOptimisticGroupVolume(groupId, prev);
  }
}

/// The FRB command indirection. Overridden in tests with a spy.
@riverpod
CommandApi commandApi(Ref ref) => const CommandApi();

/// Stable singleton controller; keepAlive so throttle timers + rollback anchors
/// survive across a drag gesture (and the controller isn't rebuilt mid-gesture).
@Riverpod(keepAlive: true)
PlaybackController playbackController(Ref ref) =>
    PlaybackController(ref, ref.watch(commandApiProvider));

/// Stable singleton controller; keepAlive for the same reason as
/// [playbackControllerProvider].
@Riverpod(keepAlive: true)
GroupingController groupingController(Ref ref) =>
    GroupingController(ref, ref.watch(commandApiProvider));
