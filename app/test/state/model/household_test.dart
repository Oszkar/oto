// Guards the value-equality contract codex flagged on PR #80: Household uses
// `mapEquals` (order-independent) for ==, so hashCode must also be
// order-independent, else two equal Households can hash differently and break
// hashed collections.
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';

void main() {
  test('Household == and hashCode are order-independent over its maps', () {
    const lr = RoomState(
      id: 'LR',
      name: 'Living Room',
      kind: RoomKind.soundbar,
      groupId: 'G1',
    );
    const kt = RoomState(
      id: 'KT',
      name: 'Kitchen',
      kind: RoomKind.speaker,
      groupId: 'G1',
    );
    const g1 = GroupState(
      id: 'G1',
      coordinatorId: 'LR',
      memberIds: ['LR', 'KT'],
    );

    // Same entries, different insertion order.
    final a = Household(rooms: {'LR': lr, 'KT': kt}, groups: {'G1': g1});
    final b = Household(rooms: {'KT': kt, 'LR': lr}, groups: {'G1': g1});

    expect(a == b, isTrue, reason: 'mapEquals is order-independent');
    expect(
      a.hashCode,
      b.hashCode,
      reason: 'equal Households must hash equal (Dart == / hashCode contract)',
    );
  });
}
