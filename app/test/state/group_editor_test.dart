import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/group_editor.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';

/// A household notifier whose value can be mutated at runtime, to simulate an
/// external topology change while the group editor is open.
class _MutableHousehold extends HouseholdNotifier {
  _MutableHousehold(this._fixture);
  Household _fixture;
  @override
  Household build() => _fixture;
  void set(Household h) {
    _fixture = h;
    state = h;
  }
}

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

  test('selection rebases when group membership changes externally', () async {
    // Regression (codex review): if another client groups/ungroups a room while
    // the editor is open, the selection must track the external add/remove so a
    // no-op Save cannot silently undo it.
    Household hh(List<String> members) => Household(
      rooms: {
        for (final m in members)
          m: RoomState(id: m, name: m, kind: RoomKind.speaker, groupId: 'G'),
      },
      groups: {
        'G': GroupState(id: 'G', coordinatorId: 'LR', memberIds: members),
      },
    );
    final notifier = _MutableHousehold(hh(['LR']));
    final container = ProviderContainer(
      overrides: [householdProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    // Keep the provider alive so its internal ref.listen is active.
    final sub = container.listen(
      groupEditorSelectionProvider('LR'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    expect(container.read(groupEditorSelectionProvider('LR')), {'LR'});

    // KT joins the group externally -> selection must include it.
    notifier.set(hh(['LR', 'KT']));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(groupEditorSelectionProvider('LR')), {'LR', 'KT'});

    // KT leaves externally -> selection must drop it.
    notifier.set(hh(['LR']));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(groupEditorSelectionProvider('LR')), {'LR'});
  });
}
