import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/group_editor.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';

void main() {
  test('diff joins newly-selected and leaves deselected, never the host', () {
    final d = diffMembership(
      host: 'LR',
      currentMembers: {'LR', 'KT'},
      selected: {'LR', 'BR'}, // KT removed, BR added
    );
    expect(d.toJoin, {'BR'});
    expect(d.toLeave, {'KT'});
  });

  test('no-op selection yields empty diff', () {
    final d = diffMembership(
      host: 'LR', currentMembers: {'LR', 'KT'}, selected: {'LR', 'KT'});
    expect(d.toJoin, isEmpty);
    expect(d.toLeave, isEmpty);
  });

  test('host is never in toJoin even if absent from currentMembers', () {
    // Exercises the `..remove(host)` guard on toJoin: the host can be selected
    // without yet being listed as a member (e.g. mid topology refresh).
    final d = diffMembership(
      host: 'LR', currentMembers: {'KT'}, selected: {'LR', 'KT'});
    expect(d.toJoin, isEmpty);
    expect(d.toLeave, isEmpty);
  });

  test('a selected room that is its own active source is a conflict', () {
    final h = Household(
      rooms: const {
        'LR': RoomState(id: 'LR', name: 'Living', kind: RoomKind.soundbar, groupId: 'G_LR'),
        'OF': RoomState(id: 'OF', name: 'Office', kind: RoomKind.speaker, groupId: 'G_OF'),
        'BR': RoomState(id: 'BR', name: 'Bed', kind: RoomKind.speaker, groupId: 'G_BR'),
      },
      groups: const {
        'G_LR': GroupState(id: 'G_LR', coordinatorId: 'LR', memberIds: ['LR'],
            transport: PlaybackState.playing, track: Track(title: 'x')),
        'G_OF': GroupState(id: 'G_OF', coordinatorId: 'OF', memberIds: ['OF'],
            transport: PlaybackState.playing, track: Track(title: 'y')),
        'G_BR': GroupState(id: 'G_BR', coordinatorId: 'BR', memberIds: ['BR'],
            transport: PlaybackState.stopped),
      },
    );
    final c = roomsWithConflict(h, host: 'LR', selected: {'LR', 'OF', 'BR'});
    expect(c, {'OF'}); // OF plays its own stream; BR is idle; LR is the host
  });

  test('a selected room with no group is not a conflict', () {
    // Ungrouped rooms can appear transiently during topology churn; they must
    // not be flagged (the `gid == null` skip in roomsWithConflict).
    final h = Household(
      rooms: const {
        'LR': RoomState(
            id: 'LR', name: 'Living', kind: RoomKind.soundbar, groupId: 'G_LR'),
        'NG': RoomState(id: 'NG', name: 'NoGroup', kind: RoomKind.speaker),
      },
      groups: const {
        'G_LR': GroupState(
            id: 'G_LR',
            coordinatorId: 'LR',
            memberIds: ['LR'],
            transport: PlaybackState.playing,
            track: Track(title: 'x')),
      },
    );
    final c = roomsWithConflict(h, host: 'LR', selected: {'LR', 'NG'});
    expect(c, isEmpty);
  });
}
