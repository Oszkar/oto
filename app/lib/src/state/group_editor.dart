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
  @override
  Set<String> build(String host) {
    final gid = ref.read(householdProvider).rooms[host]?.groupId;
    final members = gid == null
        ? <String>{host}
        : (ref.read(householdProvider).groups[gid]?.memberIds.toSet() ?? {host});
    return {...members, host};
  }

  void toggle(String roomId) {
    if (roomId == host) return; // host is always selected
    final next = {...state};
    next.contains(roomId) ? next.remove(roomId) : next.add(roomId);
    state = next;
  }
}
