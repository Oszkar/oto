/// Optimistic, LAN-polite command controllers (Task 4).
///
/// Commands update local household state **instantly** (optimistic), then fire
/// the SOAP command and let the authoritative event reconcile. Volume drags are
/// throttled (≤1 SOAP / 150 ms, trailing) plus one final send on release - the
/// LAN-politeness non-negotiable: never one command per slider pixel.
///
/// Reconciliation (shared via [_Reconciling]): a `CommandError_NotFound` means a
/// stale identifier, so we re-discover; any other error rolls the optimistic
/// value back. A *successful* no-op set emits no echo (Sonos suppresses
/// unchanged values), so a standing optimistic value is correct - we **never**
/// revert for lack of an echo, only on a thrown error.
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

/// Shared optimistic-command reconciliation. Runs [op]; on a thrown
/// [CommandError] it either re-discovers (stale id → `NotFound`) or rolls back
/// (any other error). Keeps `send`/error handling DRY across both controllers.
mixin _Reconciling {
  Ref get ref;

  /// Room name for [speakerId], to name it in a failure notice. Null when the
  /// id is unknown (already gone from the household) - `describeCommandError`
  /// then falls back to a generic subject rather than printing a raw id.
  String? roomLabel(String speakerId) =>
      ref.read(householdProvider).rooms[speakerId]?.name;

  /// A group is labelled by its coordinator's room name - the same name the
  /// group card titles itself with. Used for group-addressed commands
  /// (transport, group volume/mute), which have no single speaker to name.
  String? groupLabel(String groupId) {
    final h = ref.read(householdProvider);
    final coord = h.groups[groupId]?.coordinatorId;
    return coord == null ? null : h.rooms[coord]?.name;
  }

  Future<void> send(
    Future<void> Function() op, {
    void Function()? rollback,
    String? label,
    bool Function()? isCurrent,
  }) async {
    try {
      await op();
    } on CommandError catch (e) {
      // A superseded send stays SILENT. `_ThrottledScalar` can have an earlier
      // mid-drag send still in flight when the final one succeeds; if that
      // stale send then fails, neither its rollback nor its failure notice is
      // about anything the user is still doing - announcing it would claim
      // "Could not reach Kitchen" right after the volume they set landed fine.
      if (isCurrent?.call() ?? true) {
        // Any thrown error means the optimistic guess didn't take, so undo it. A
        // *successful* no-op set emits no echo, so a standing optimistic value
        // is correct - we roll back only on a thrown error, never for a missing
        // echo.
        rollback?.call();
        // Say so. Before v0.6.4 the rollback was silent, which made a failed
        // command look like a control that bounced back for no reason.
        ref
            .read(commandFailuresProvider.notifier)
            .report(describeCommandError(e, label));
      }
      if (e is CommandError_NotFound) {
        // Stale identifier - also re-discover so the id is refreshed (sonos-notes
        // § Identifiers). Deliberately OUTSIDE the isCurrent gate: a stale id is
        // stale regardless of which gesture observed it, which preserves the
        // pre-v0.6.4 re-discover behaviour exactly. Rolling back first means the
        // view shows the last-known value until the fresh topology re-seeds it
        // via events, rather than a wrong optimistic guess carried across
        // re-discovery by coordinator.
        ref.invalidate(discoveryProvider);
      }
    }
  }
}

/// One throttled, optimistic scalar (a volume) per target id - shared by the
/// per-speaker and per-group volume paths so the drag bookkeeping lives once.
///
/// Encapsulates: pre-gesture anchor capture, the LAN throttle (≤1 SOAP /
/// 150 ms, trailing), a single final send on release, and **sequence-gated**
/// rollback. The sequence gate fixes a real race: release (`end`) can fire
/// while an earlier throttled mid-drag send is still in flight; if that stale
/// send then fails *after* the final send succeeded, a naive rollback would
/// revert the UI to the pre-gesture value, clobbering the value the user
/// actually set. Each send bumps a per-id sequence, and a send only rolls back
/// if it is still the latest - so a superseded send fails silently.
class _ThrottledScalar {
  _ThrottledScalar({
    required this.readCurrent,
    required this.readLabel,
    required this.applyOptimistic,
    required this.restore,
    required this.command,
    required this.reconcile,
  });

  /// Current authoritative value for [id] - the rollback target (anchor).
  final int? Function(String id) readCurrent;

  /// Human label for [id], for the failure notice.
  final String? Function(String id) readLabel;

  /// Apply an optimistic [value] for [id] to local household state.
  final void Function(String id, int value) applyOptimistic;

  /// Restore [id] to a possibly-null pre-gesture anchor on rollback. Distinct
  /// from [applyOptimistic] (which only ever sets a concrete drag value)
  /// because the anchor can be `null` at cold-start, and a failed command must
  /// then clear the field rather than leave a fabricated value standing.
  final void Function(String id, int? value) restore;

  /// Fire the SOAP command for [id] at [value].
  final Future<void> Function(String id, int value) command;

  /// The shared reconciler - [_Reconciling.send].
  final Future<void> Function(
    Future<void> Function(), {
    void Function()? rollback,
    String? label,
    bool Function()? isCurrent,
  })
  reconcile;

  final _throttle = <String, Throttle>{};
  final _anchor = <String, int?>{};
  final _seq = <String, int>{};

  /// Mid-drag: optimistic now, SOAP send throttled to the trailing edge.
  void drag(String id, int value) {
    _anchor.putIfAbsent(id, () => readCurrent(id));
    applyOptimistic(id, value);
    _throttle
        .putIfAbsent(id, () => Throttle(const Duration(milliseconds: 150)))
        .run(() => _fire(id, value));
  }

  /// Drag release: send the final value exactly once. Cancel the pending
  /// trailing send (dispose, do NOT flush - flush + this send would double-fire).
  void end(String id, int value) {
    _anchor.putIfAbsent(id, () => readCurrent(id));
    applyOptimistic(id, value);
    _throttle.remove(id)?.dispose();
    final future = _fire(id, value);
    final mySeq = _seq[id]; // the sequence _fire just assigned (synchronously).
    future.whenComplete(() {
      // Release the per-id bookkeeping ONLY if this gesture is still the latest.
      // A new drag/end on the same id can start while our send is in flight;
      // clearing unconditionally would wipe the newer gesture's anchor +
      // sequence, stranding its rollback (it would see a null sequence and skip,
      // leaving a failed newer command's optimistic value standing).
      if (_seq[id] == mySeq) {
        _anchor.remove(id);
        _seq.remove(id);
      }
    });
  }

  Future<void> _fire(String id, int value) {
    // This send is now the latest for [id]. An older in-flight send that fails
    // later will find a newer (or cleared) seq and skip its rollback, so a
    // stale mid-drag failure can't clobber the final value.
    final mySeq = (_seq[id] ?? 0) + 1;
    _seq[id] = mySeq;
    return reconcile(
      () => command(id, value),
      label: readLabel(id),
      // Superseded by a newer gesture on the same id -> no rollback AND no
      // notice. One predicate governs both so they cannot drift.
      isCurrent: () => _seq[id] == mySeq,
      rollback: () {
        // Restore the pre-gesture anchor, which may be null (cold-start) -
        // `restore` clears to null so a failed command can't leave a fabricated
        // value standing.
        restore(id, _anchor[id]);
      },
    );
  }
}

/// Transport + per-speaker volume commands, optimistic and LAN-throttled.
class PlaybackController with _Reconciling {
  PlaybackController(this.ref, this.api) {
    _volume = _ThrottledScalar(
      readCurrent: (id) => ref.read(householdProvider).rooms[id]?.volume,
      readLabel: roomLabel,
      applyOptimistic: (id, v) => _h.setOptimisticVolume(id, v),
      restore: (id, v) => _h.restoreVolume(id, v),
      command: (id, v) => api.setVolume(id, v),
      reconcile: send,
    );
  }
  @override
  final Ref ref;
  final CommandApi api;
  late final _ThrottledScalar _volume;

  HouseholdNotifier get _h => ref.read(householdProvider.notifier);

  /// Flip transport optimistically and fire play/pause. On a stale-id error the
  /// shared reconciler re-discovers; on any other error it rolls transport back.
  Future<void> togglePlay(String groupId, PlaybackState current) async {
    final next = current == PlaybackState.playing
        ? PlaybackState.paused
        : PlaybackState.playing;
    _h.setOptimisticTransport(groupId, next);
    await send(
      () => next == PlaybackState.playing
          ? api.play(groupId)
          : api.pause(groupId),
      label: groupLabel(groupId),
      rollback: () => _h.setOptimisticTransport(groupId, current),
    );
  }

  /// Skip to the next track. No optimistic state: the authoritative `Track`
  /// event drives the change, and the shared [send] re-discovers on a stale-id
  /// `NotFound`. (Deferred from Task 4 to the Now Playing screen.)
  Future<void> next(String groupId) =>
      send(() => api.next(groupId), label: groupLabel(groupId));

  /// Skip to the previous track. Same no-optimistic-state rationale as [next].
  Future<void> previous(String groupId) =>
      send(() => api.previous(groupId), label: groupLabel(groupId));

  /// Mid-drag volume: optimistic now, SOAP send throttled to the trailing edge.
  void setVolume(String speakerId, int v) => _volume.drag(speakerId, v);

  /// Drag release: send the final value exactly once.
  void setVolumeEnd(String speakerId, int v) => _volume.end(speakerId, v);

  /// Flip a room's mute optimistically and fire the command. Mirrors
  /// [GroupingController.setGroupMute]: `prev` may be null (event-only field,
  /// no value seen yet), so a failed command restores null rather than leaving
  /// a fabricated value standing.
  Future<void> setMute(String speakerId, bool muted) {
    final prev = ref.read(householdProvider).rooms[speakerId]?.muted;
    _h.setOptimisticMuted(speakerId, muted);
    return send(
      () => api.setMute(speakerId, muted),
      label: roomLabel(speakerId),
      rollback: () => _h.restoreMuted(speakerId, prev),
    );
  }
}

/// Group form/break + group volume/mute commands. Form/break do NOT mutate
/// membership optimistically - the topology event path (GroupMembership NOTIFY
/// → debounced topology re-pull) drives that update.
class GroupingController with _Reconciling {
  GroupingController(this.ref, this.api) {
    _groupVolume = _ThrottledScalar(
      readCurrent: (id) => ref.read(householdProvider).groups[id]?.groupVolume,
      readLabel: groupLabel,
      applyOptimistic: (id, v) => _h.setOptimisticGroupVolume(id, v),
      restore: (id, v) => _h.restoreGroupVolume(id, v),
      command: (id, v) => api.setGroupVolume(id, v),
      reconcile: send,
    );
  }
  @override
  final Ref ref;
  final CommandApi api;
  late final _ThrottledScalar _groupVolume;

  HouseholdNotifier get _h => ref.read(householdProvider.notifier);

  Future<void> joinGroup(String speakerId, String coordinatorId) => send(
    () => api.joinGroup(speakerId, coordinatorId),
    label: roomLabel(speakerId),
  );

  Future<void> leaveGroup(String speakerId) =>
      send(() => api.leaveGroup(speakerId), label: roomLabel(speakerId));

  void setGroupVolume(String groupId, int v) => _groupVolume.drag(groupId, v);

  void setGroupVolumeEnd(String groupId, int v) => _groupVolume.end(groupId, v);

  Future<void> setGroupMute(String groupId, bool muted) {
    final prev = ref.read(householdProvider).groups[groupId]?.groupMuted;
    _h.setOptimisticGroupMuted(groupId, muted);
    return send(
      () => api.setGroupMute(groupId, muted),
      label: groupLabel(groupId),
      // `prev` may be null (event-only field, no value seen yet) - restore it
      // as-is so a failed mute can't leave a fabricated value standing.
      rollback: () => _h.restoreGroupMuted(groupId, prev),
    );
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
