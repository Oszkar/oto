/// Optimistic, LAN-polite command controllers (Task 4).
///
/// Commands update local household state **instantly** (optimistic), then fire
/// the SOAP command and let the authoritative event reconcile. Volume drags are
/// throttled (≤1 SOAP / 150 ms, trailing) plus one final send on release - the
/// LAN-politeness non-negotiable: never one command per slider pixel.
///
/// Reconciliation is shared by both controllers through [CommandScheduler]. A
/// `CommandError_NotFound` means a stale identifier, so we re-discover; any
/// other current-intent error restores the lane's last committed value. A
/// successful no-op set emits no echo (Sonos suppresses unchanged values), so a
/// standing optimistic value is correct - we never revert for lack of an echo,
/// only on a thrown error.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;
import '../rust/api.dart' show CommandError, CommandError_NotFound;
import 'command_failures.dart';
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

enum _CommandLane {
  roomVolume,
  roomMute,
  groupVolume,
  groupMute,
  transportToggle,
}

typedef _LaneKey = ({String speakerId, _CommandLane lane});

class _LaneState {
  int generation = 0;
  int activeIntents = 0;
  Object? committed;
}

class _GroupTarget {
  const _GroupTarget(this.originalGroupId, this.coordinatorId);

  final String originalGroupId;
  final String? coordinatorId;

  String get dispatchKey => coordinatorId ?? originalGroupId;
}

class _CommandIntent<T> {
  _CommandIntent({
    required this.key,
    required this.state,
    required this.generation,
    required this.optimisticValue,
    required this.restore,
    required this.dispatchKey,
    required this.label,
    this.groupTarget,
  });

  final _LaneKey key;
  final _LaneState state;
  final int generation;
  final T optimisticValue;
  final void Function(T committed, String? currentGroupId) restore;
  final String dispatchKey;
  final String? label;
  final _GroupTarget? groupTarget;
  bool active = true;
}

/// Shared command authority for both controllers.
///
/// Physical-device dispatch ordering and user-intent supersession deliberately
/// use different keys. Every command sent to one speaker shares a dispatch
/// tail, while only a newer value in the same operation lane suppresses an
/// older rollback. Each lane also keeps the last successfully committed value,
/// separate from the household's currently rendered optimistic value.
class CommandScheduler {
  CommandScheduler(this.ref);

  final Ref ref;
  final Map<String, Future<void>> _tails = {};
  final Map<_LaneKey, _LaneState> _lanes = {};

  /// Coordinator captures that outlive individual mid-drag sends. The scalar
  /// helper owns gesture timing; the scheduler owns the stable physical target.
  final Map<String, String?> _groupGestures = {};

  String? roomLabel(String speakerId) =>
      ref.read(householdProvider).rooms[speakerId]?.name;

  String? _coordinatorOf(String groupId) =>
      ref.read(householdProvider).groups[groupId]?.coordinatorId;

  String? _labelFor(_GroupTarget target) {
    final coordinator = target.coordinatorId;
    return coordinator == null ? null : roomLabel(coordinator);
  }

  _GroupTarget _captureGroup(String groupId) {
    final coordinator = _groupGestures.containsKey(groupId)
        ? _groupGestures[groupId]
        : _coordinatorOf(groupId);
    return _GroupTarget(groupId, coordinator);
  }

  /// Re-resolve immediately before dispatch or rollback. Following the captured
  /// coordinator even when the old id still exists avoids sending a queued
  /// command to a newly re-coordinated group that happens to reuse that id.
  String _currentGroupId(_GroupTarget target) {
    final coordinator = target.coordinatorId;
    if (coordinator != null) {
      for (final group in ref.read(householdProvider).groups.values) {
        if (group.coordinatorId == coordinator) return group.id;
      }
    }
    return target.originalGroupId;
  }

  void _openGroupGesture(String groupId) {
    _groupGestures.putIfAbsent(groupId, () => _coordinatorOf(groupId));
  }

  Set<String> _closeGroupGesture(_CommandIntent<int?> intent) {
    final target = intent.groupTarget;
    if (target == null) return const {};

    final coordinator = target.coordinatorId;
    if (coordinator == null) {
      _groupGestures.remove(target.originalGroupId);
      return {target.originalGroupId};
    }

    // A regroup can change the id supplied at drag release. Clear every alias
    // captured for the same physical coordinator so the old id cannot retain a
    // stale target if Sonos later reuses it for another group.
    final aliases = <String>{};
    _groupGestures.removeWhere((groupId, captured) {
      final matches = captured == coordinator;
      if (matches) aliases.add(groupId);
      return matches;
    });
    aliases.add(target.originalGroupId);
    return aliases;
  }

  _CommandIntent<T> _beginRoomIntent<T>({
    required String speakerId,
    required _CommandLane lane,
    required T Function() readCommitted,
    required T optimisticValue,
    required void Function() applyOptimistic,
    required void Function(T committed) restore,
  }) => _beginIntent(
    dispatchKey: speakerId,
    lane: lane,
    readCommitted: readCommitted,
    optimisticValue: optimisticValue,
    applyOptimistic: applyOptimistic,
    restore: (value, _) => restore(value),
    label: roomLabel(speakerId),
  );

  _CommandIntent<T> _beginGroupIntent<T>({
    required String groupId,
    required _CommandLane lane,
    required T Function(String currentGroupId) readCommitted,
    required T optimisticValue,
    required void Function(String currentGroupId) applyOptimistic,
    required void Function(String currentGroupId, T committed) restore,
  }) {
    final target = _captureGroup(groupId);
    final currentGroupId = _currentGroupId(target);
    return _beginIntent(
      dispatchKey: target.dispatchKey,
      lane: lane,
      readCommitted: () => readCommitted(currentGroupId),
      optimisticValue: optimisticValue,
      applyOptimistic: () => applyOptimistic(currentGroupId),
      restore: (value, currentGroupId) {
        if (currentGroupId != null) restore(currentGroupId, value);
      },
      label: _labelFor(target),
      groupTarget: target,
    );
  }

  _CommandIntent<T> _beginIntent<T>({
    required String dispatchKey,
    required _CommandLane lane,
    required T Function() readCommitted,
    required T optimisticValue,
    required void Function() applyOptimistic,
    required void Function(T committed, String? currentGroupId) restore,
    required String? label,
    _GroupTarget? groupTarget,
  }) {
    final key = (speakerId: dispatchKey, lane: lane);
    final state = _lanes.putIfAbsent(key, _LaneState.new);
    if (state.activeIntents == 0) state.committed = readCommitted();
    state.activeIntents++;
    final generation = ++state.generation;

    // The generation is visible before the optimistic write. An older failure
    // landing after this point therefore cannot clobber the newer user intent.
    applyOptimistic();
    return _CommandIntent(
      key: key,
      state: state,
      generation: generation,
      optimisticValue: optimisticValue,
      restore: restore,
      dispatchKey: dispatchKey,
      label: label,
      groupTarget: groupTarget,
    );
  }

  bool _isLatest<T>(_CommandIntent<T> intent) =>
      intent.state.generation == intent.generation;

  void _cancelIntent<T>(_CommandIntent<T> intent) => _finishIntent(intent);

  Future<void> _dispatchRoomIntent<T>(
    _CommandIntent<T> intent,
    Future<void> Function() command,
  ) => _enqueue(intent.dispatchKey, () => _runIntent(intent, (_) => command()));

  Future<void> _dispatchGroupIntent<T>(
    _CommandIntent<T> intent,
    Future<void> Function(String currentGroupId) command,
  ) => _enqueue(
    intent.dispatchKey,
    () => _runIntent(intent, (groupId) {
      if (groupId == null) {
        return Future<void>.error(
          StateError('group intent has no captured group target'),
        );
      }
      return command(groupId);
    }),
  );

  Future<void> _runIntent<T>(
    _CommandIntent<T> intent,
    Future<void> Function(String? currentGroupId) command,
  ) async {
    final groupTarget = intent.groupTarget;
    final groupId = groupTarget == null ? null : _currentGroupId(groupTarget);
    try {
      await command(groupId);
      // A superseded success is still the committed predecessor for any newer
      // queued operation that may fail.
      intent.state.committed = intent.optimisticValue;
    } on CommandError catch (error) {
      if (_isLatest(intent)) {
        final rollbackGroupId = groupTarget == null
            ? null
            : _currentGroupId(groupTarget);
        intent.restore(intent.state.committed as T, rollbackGroupId);
        _report(error, intent.label);
      }
      _rediscoverIfStale(error);
    } finally {
      _finishIntent(intent);
    }
  }

  Future<void> _orderRoom({
    required String speakerId,
    required Future<void> Function() command,
  }) => _enqueue(speakerId, () => _runOrdered(command, roomLabel(speakerId)));

  Future<void> _orderGroup({
    required String groupId,
    required Future<void> Function(String currentGroupId) command,
  }) {
    final target = _captureGroup(groupId);
    return _enqueue(
      target.dispatchKey,
      () => _runOrdered(
        () => command(_currentGroupId(target)),
        _labelFor(target),
      ),
    );
  }

  Future<void> _runOrdered(
    Future<void> Function() command,
    String? label,
  ) async {
    try {
      await command();
    } on CommandError catch (error) {
      _report(error, label);
      _rediscoverIfStale(error);
    }
  }

  void _report(CommandError error, String? label) => ref
      .read(commandFailuresProvider.notifier)
      .report(describeCommandError(error, label));

  void _rediscoverIfStale(CommandError error) {
    // Deliberately independent of supersession. A stale identifier remains
    // useful discovery evidence even when its optimistic intent was replaced.
    if (error is CommandError_NotFound) ref.invalidate(discoveryProvider);
  }

  void _finishIntent<T>(_CommandIntent<T> intent) {
    if (!intent.active) return;
    intent.active = false;
    intent.state.activeIntents--;
    if (intent.state.activeIntents == 0 &&
        identical(_lanes[intent.key], intent.state)) {
      _lanes.remove(intent.key);
    }
  }

  Future<void> _enqueue(String dispatchKey, Future<void> Function() command) {
    final previous = _tails[dispatchKey];
    final next = previous == null
        ? command()
        : previous.catchError((_) {}).then((_) => command());
    _tails[dispatchKey] = next;

    void releaseTail(Object? _) {
      if (identical(_tails[dispatchKey], next)) _tails.remove(dispatchKey);
    }

    // Observe both outcomes without creating an unhandled derived future.
    next.then(releaseTail, onError: releaseTail);
    return next;
  }
}

/// One throttled, optimistic scalar (a volume) per target id - shared by the
/// per-speaker and per-group volume paths so the drag bookkeeping lives once.
///
/// This class owns only throttle and gesture bookkeeping. Dispatch ordering,
/// supersession, and rollback baselines live in [CommandScheduler].
class _ThrottledScalar {
  _ThrottledScalar({
    required this.beginIntent,
    required this.dispatchIntent,
    required this.cancelIntent,
    required this.intentIsLatest,
    this.onGestureStarted,
    this.onGestureSettled,
  });

  final _CommandIntent<int?> Function(String id, int value) beginIntent;
  final Future<void> Function(_CommandIntent<int?> intent, String id, int value)
  dispatchIntent;
  final void Function(_CommandIntent<int?> intent) cancelIntent;
  final bool Function(_CommandIntent<int?> intent) intentIsLatest;
  final void Function(String id)? onGestureStarted;
  final Set<String> Function(_CommandIntent<int?> intent)? onGestureSettled;

  final _throttle = <String, Throttle>{};
  final _pending = <String, _CommandIntent<int?>>{};
  final _openGestures = <String>{};

  void _openGesture(String id) {
    if (_openGestures.add(id)) onGestureStarted?.call(id);
  }

  /// Mid-drag: optimistic now, SOAP send throttled to the trailing edge.
  void drag(String id, int value) {
    _openGesture(id);
    final intent = beginIntent(id, value);
    final replaced = _pending[id];
    _pending[id] = intent;
    if (replaced != null) cancelIntent(replaced);
    _throttle
        .putIfAbsent(id, () => Throttle(const Duration(milliseconds: 150)))
        .run(() {
          if (identical(_pending[id], intent)) _pending.remove(id);
          dispatchIntent(intent, id, value);
        });
  }

  /// Drag release: send the final value exactly once. Cancel the pending
  /// trailing send (dispose, do NOT flush - flush + this send would double-fire).
  void end(String id, int value) {
    _openGesture(id);
    final intent = beginIntent(id, value);
    _throttle.remove(id)?.dispose();
    final pending = _pending.remove(id);
    if (pending != null) cancelIntent(pending);
    final future = dispatchIntent(intent, id, value);

    void settle(Object? _) {
      if (intentIsLatest(intent)) {
        final aliases = onGestureSettled?.call(intent);
        if (aliases == null) {
          _openGestures.remove(id);
        } else {
          _openGestures.removeAll(aliases);
        }
      }
    }

    future.then(settle, onError: settle);
  }
}

/// Transport + per-speaker volume commands, optimistic and LAN-throttled.
class PlaybackController {
  PlaybackController(this.ref, this.api, this.scheduler) {
    _volume = _ThrottledScalar(
      beginIntent: (id, value) => scheduler._beginRoomIntent<int?>(
        speakerId: id,
        lane: _CommandLane.roomVolume,
        readCommitted: () => ref.read(householdProvider).rooms[id]?.volume,
        optimisticValue: value,
        applyOptimistic: () => _h.setOptimisticVolume(id, value),
        restore: (committed) => _h.restoreVolume(id, committed),
      ),
      dispatchIntent: (intent, id, value) =>
          scheduler._dispatchRoomIntent(intent, () => api.setVolume(id, value)),
      cancelIntent: scheduler._cancelIntent,
      intentIsLatest: scheduler._isLatest,
    );
  }
  final Ref ref;
  final CommandApi api;
  final CommandScheduler scheduler;
  late final _ThrottledScalar _volume;

  HouseholdNotifier get _h => ref.read(householdProvider.notifier);

  /// Flip transport optimistically and fire play/pause. On a stale-id error the
  /// shared scheduler re-discovers; on any other error it rolls transport back.
  Future<void> togglePlay(String groupId, PlaybackState current) async {
    final next = current == PlaybackState.playing
        ? PlaybackState.paused
        : PlaybackState.playing;
    final intent = scheduler._beginGroupIntent<PlaybackState>(
      groupId: groupId,
      lane: _CommandLane.transportToggle,
      readCommitted: (currentGroupId) =>
          ref.read(householdProvider).groups[currentGroupId]?.transport ??
          current,
      optimisticValue: next,
      applyOptimistic: (currentGroupId) =>
          _h.setOptimisticTransport(currentGroupId, next),
      restore: (currentGroupId, committed) =>
          _h.setOptimisticTransport(currentGroupId, committed),
    );
    await scheduler._dispatchGroupIntent(
      intent,
      (currentGroupId) => next == PlaybackState.playing
          ? api.play(currentGroupId)
          : api.pause(currentGroupId),
    );
  }

  /// Skip to the next track. No optimistic state: the authoritative `Track`
  /// event drives the change, and the shared [send] re-discovers on a stale-id
  /// `NotFound`. (Deferred from Task 4 to the Now Playing screen.)
  Future<void> next(String groupId) =>
      scheduler._orderGroup(groupId: groupId, command: api.next);

  /// Skip to the previous track. Same no-optimistic-state rationale as [next].
  Future<void> previous(String groupId) =>
      scheduler._orderGroup(groupId: groupId, command: api.previous);

  /// Mid-drag volume: optimistic now, SOAP send throttled to the trailing edge.
  void setVolume(String speakerId, int v) => _volume.drag(speakerId, v);

  /// Drag release: send the final value exactly once.
  void setVolumeEnd(String speakerId, int v) => _volume.end(speakerId, v);

  /// Flip a room's mute optimistically and fire the command. Mirrors
  /// [GroupingController.setGroupMute]: `prev` may be null (event-only field,
  /// no value seen yet), so a failed command restores null rather than leaving
  /// a fabricated value standing.
  Future<void> setMute(String speakerId, bool muted) {
    final intent = scheduler._beginRoomIntent<bool?>(
      speakerId: speakerId,
      lane: _CommandLane.roomMute,
      readCommitted: () => ref.read(householdProvider).rooms[speakerId]?.muted,
      optimisticValue: muted,
      applyOptimistic: () => _h.setOptimisticMuted(speakerId, muted),
      restore: (committed) => _h.restoreMuted(speakerId, committed),
    );
    return scheduler._dispatchRoomIntent(
      intent,
      () => api.setMute(speakerId, muted),
    );
  }
}

/// Group form/break + group volume/mute commands. Form/break do NOT mutate
/// membership optimistically - the topology event path (GroupMembership NOTIFY
/// → debounced topology re-pull) drives that update.
class GroupingController {
  GroupingController(this.ref, this.api, this.scheduler) {
    _groupVolume = _ThrottledScalar(
      beginIntent: (id, value) => scheduler._beginGroupIntent<int?>(
        groupId: id,
        lane: _CommandLane.groupVolume,
        readCommitted: (currentGroupId) =>
            ref.read(householdProvider).groups[currentGroupId]?.groupVolume,
        optimisticValue: value,
        applyOptimistic: (currentGroupId) =>
            _h.setOptimisticGroupVolume(currentGroupId, value),
        restore: (currentGroupId, committed) =>
            _h.restoreGroupVolume(currentGroupId, committed),
      ),
      dispatchIntent: (intent, _, value) => scheduler._dispatchGroupIntent(
        intent,
        (currentGroupId) => api.setGroupVolume(currentGroupId, value),
      ),
      cancelIntent: scheduler._cancelIntent,
      intentIsLatest: scheduler._isLatest,
      onGestureStarted: scheduler._openGroupGesture,
      onGestureSettled: scheduler._closeGroupGesture,
    );
  }
  final Ref ref;
  final CommandApi api;
  final CommandScheduler scheduler;
  late final _ThrottledScalar _groupVolume;

  HouseholdNotifier get _h => ref.read(householdProvider.notifier);

  Future<void> joinGroup(String speakerId, String coordinatorId) =>
      scheduler._orderRoom(
        speakerId: speakerId,
        command: () => api.joinGroup(speakerId, coordinatorId),
      );

  Future<void> leaveGroup(String speakerId) => scheduler._orderRoom(
    speakerId: speakerId,
    command: () => api.leaveGroup(speakerId),
  );

  void setGroupVolume(String groupId, int v) => _groupVolume.drag(groupId, v);

  void setGroupVolumeEnd(String groupId, int v) => _groupVolume.end(groupId, v);

  Future<void> setGroupMute(String groupId, bool muted) {
    final intent = scheduler._beginGroupIntent<bool?>(
      groupId: groupId,
      lane: _CommandLane.groupMute,
      readCommitted: (currentGroupId) =>
          ref.read(householdProvider).groups[currentGroupId]?.groupMuted,
      optimisticValue: muted,
      applyOptimistic: (currentGroupId) =>
          _h.setOptimisticGroupMuted(currentGroupId, muted),
      restore: (currentGroupId, committed) =>
          _h.restoreGroupMuted(currentGroupId, committed),
    );
    return scheduler._dispatchGroupIntent(
      intent,
      (currentGroupId) => api.setGroupMute(currentGroupId, muted),
    );
  }
}

/// The FRB command indirection. Overridden in tests with a spy.
@riverpod
CommandApi commandApi(Ref ref) => const CommandApi();

/// One app-lifetime scheduler shared by every command controller.
@Riverpod(keepAlive: true)
CommandScheduler commandScheduler(Ref ref) => CommandScheduler(ref);

/// Stable singleton controller; keepAlive so throttle timers and gesture state
/// survive across a drag gesture (and the controller isn't rebuilt mid-gesture).
@Riverpod(keepAlive: true)
PlaybackController playbackController(Ref ref) => PlaybackController(
  ref,
  ref.watch(commandApiProvider),
  ref.watch(commandSchedulerProvider),
);

/// Stable singleton controller; keepAlive for the same reason as
/// [playbackControllerProvider].
@Riverpod(keepAlive: true)
GroupingController groupingController(Ref ref) => GroupingController(
  ref,
  ref.watch(commandApiProvider),
  ref.watch(commandSchedulerProvider),
);
