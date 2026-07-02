import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';

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

  group('copyWith null-clearing', () {
    test('RoomState.copyWith can clear nullable fields to null', () {
      const r = RoomState(
        id: 'LR',
        name: 'Living Room',
        model: 'Beam',
        kind: RoomKind.soundbar,
        volume: 30,
        muted: true,
        online: true,
        groupId: 'G1',
      );
      final cleared = r.copyWith(
        volume: null,
        muted: null,
        model: null,
        groupId: null,
      );
      expect(cleared.volume, isNull);
      expect(cleared.muted, isNull);
      expect(cleared.model, isNull);
      expect(cleared.groupId, isNull);
      // Untouched fields keep their values.
      expect(cleared.id, 'LR');
      expect(cleared.name, 'Living Room');
      expect(cleared.kind, RoomKind.soundbar);
      expect(cleared.online, isTrue);
    });

    test('RoomState.copyWith with no args keeps every field', () {
      const r = RoomState(
        id: 'LR',
        name: 'LR',
        kind: RoomKind.speaker,
        volume: 30,
      );
      final same = r.copyWith();
      expect(same.volume, 30);
      expect(same.muted, isNull);
      expect(same, equals(r));
    });

    test('RoomState.copyWith sets a concrete value', () {
      const r = RoomState(id: 'LR', name: 'LR', kind: RoomKind.speaker);
      expect(r.copyWith(volume: 45).volume, 45);
    });

    test('GroupState.copyWith can clear nullable fields to null', () {
      const g = GroupState(
        id: 'G',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.playing,
        track: Track(title: 'X'),
        groupVolume: 40,
        groupMuted: true,
      );
      final cleared = g.copyWith(
        transport: null,
        track: null,
        groupVolume: null,
        groupMuted: null,
      );
      expect(cleared.transport, isNull);
      expect(cleared.track, isNull);
      expect(cleared.groupVolume, isNull);
      expect(cleared.groupMuted, isNull);
      // Untouched fields keep their values.
      expect(cleared.id, 'G');
      expect(cleared.coordinatorId, 'LR');
      expect(cleared.memberIds, ['LR']);
    });
  });
}
