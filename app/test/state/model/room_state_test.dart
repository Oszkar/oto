import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/room_state.dart';

void main() {
  group('roomKindFromModel', () {
    test('soundbar models map to RoomKind.soundbar', () {
      expect(roomKindFromModel('Beam'), RoomKind.soundbar);
      expect(roomKindFromModel('Arc'), RoomKind.soundbar);
      expect(roomKindFromModel('Ray'), RoomKind.soundbar);
      expect(roomKindFromModel('Playbar'), RoomKind.soundbar);
      expect(roomKindFromModel('Playbase'), RoomKind.soundbar);
    });

    test('case-insensitive substring match', () {
      expect(roomKindFromModel('Sonos BEAM (Gen 2)'), RoomKind.soundbar);
      expect(roomKindFromModel('sonos arc ultra'), RoomKind.soundbar);
    });

    test('non-soundbar models map to RoomKind.speaker', () {
      expect(roomKindFromModel('Era 100'), RoomKind.speaker);
      expect(roomKindFromModel('One SL'), RoomKind.speaker);
    });

    test('null maps to RoomKind.speaker', () {
      expect(roomKindFromModel(null), RoomKind.speaker);
    });
  });

  group('value equality', () {
    test('GroupState compares memberIds by value, not identity', () {
      // Two DISTINCT, non-const list instances with identical contents.
      final a = GroupState(id: 'G', coordinatorId: 'a', memberIds: ['a', 'b']);
      final b = GroupState(
        id: 'G',
        coordinatorId: 'a',
        memberIds: List.of(<String>['a', 'b']),
      );
      // Guard against the #1 bug: identity-based list equality/hash.
      expect(identical(a.memberIds, b.memberIds), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('RoomState with identical fields is equal', () {
      const a = RoomState(
        id: 'LR',
        name: 'Living Room',
        model: 'Beam',
        kind: RoomKind.soundbar,
        volume: 30,
        muted: false,
        online: true,
        groupId: 'G1',
      );
      const b = RoomState(
        id: 'LR',
        name: 'Living Room',
        model: 'Beam',
        kind: RoomKind.soundbar,
        volume: 30,
        muted: false,
        online: true,
        groupId: 'G1',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
