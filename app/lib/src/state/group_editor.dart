/// Pure logic + selection state for the group editor (v0.6.1).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'household.dart';
import 'model/household.dart';

part 'group_editor.g.dart';

/// The join/leave commands needed to turn the host group's current membership
/// into the selected set. The host itself is never joined or left.
class MembershipDiff {
  final Set<String> toJoin;
  final Set<String> toLeave;
  const MembershipDiff(this.toJoin, this.toLeave);
}

MembershipDiff diffMembership({
  required String host,
  required Set<String> currentMembers,
  required Set<String> selected,
}) {
  final toJoin = selected.difference(currentMembers)..remove(host);
  final toLeave = currentMembers.difference(selected)..remove(host);
  return MembershipDiff(toJoin, toLeave);
}

/// Selected rooms that currently play their own independent source (a group
/// other than the host's, with an active stream). Joining them stops it.
Set<String> roomsWithConflict(
  Household h, {
  required String host,
  required Set<String> selected,
}) {
  final hostGroup = h.rooms[host]?.groupId;
  final out = <String>{};
  for (final id in selected) {
    if (id == host) continue;
    final gid = h.rooms[id]?.groupId;
    if (gid == null || gid == hostGroup) continue;
    if (h.groups[gid]?.hasActiveStream ?? false) out.add(id);
  }
  return out;
}

/// Editor selection, keyed by host room id. Seeds from the host group's current
/// members; `toggle` adds/removes a room (the host stays selected).
@riverpod
class GroupEditorSelection extends _$GroupEditorSelection {
  /// The host group's current members, always including the host (it anchors
  /// the selection even if absent from its own memberIds mid topology refresh).
  Set<String> _liveMembers(Household h) {
    final gid = h.rooms[host]?.groupId;
    final members = gid == null
        ? <String>{host}
        : (h.groups[gid]?.memberIds.toSet() ?? {host});
    return {...members, host};
  }

  @override
  Set<String> build(String host) {
    // Rebase the selection when the group's membership changes underneath us
    // (e.g. another client groups/ungroups a room while the editor is open):
    // reflect external adds/removes so a no-op Save can't silently undo them.
    // The user's pending toggles for other rooms are preserved.
    ref.listen(householdProvider, (prev, next) {
      if (prev == null) return;
      final added = _liveMembers(next).difference(_liveMembers(prev));
      final removed = _liveMembers(prev).difference(_liveMembers(next));
      if (added.isEmpty && removed.isEmpty) return;
      state = ({...state, ...added}..removeAll(removed))..add(host);
    });
    return _liveMembers(ref.read(householdProvider));
  }

  void toggle(String roomId) {
    if (roomId == host) return; // host is always selected
    final next = {...state};
    next.contains(roomId) ? next.remove(roomId) : next.add(roomId);
    state = next;
  }
}
