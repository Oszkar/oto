import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/source.dart';
import 'package:oto/src/state/model/track.dart';

Household _h() => Household(
  rooms: {
    'LR': const RoomState(
      id: 'LR',
      name: 'Living Room',
      kind: RoomKind.soundbar,
      groupId: 'G1',
    ),
    'KT': const RoomState(
      id: 'KT',
      name: 'Kitchen',
      kind: RoomKind.speaker,
      groupId: 'G1',
    ),
    'OF': const RoomState(
      id: 'OF',
      name: 'Office',
      kind: RoomKind.speaker,
      groupId: 'G2',
    ),
    'BR': const RoomState(
      id: 'BR',
      name: 'Bedroom',
      kind: RoomKind.speaker,
      groupId: 'G3',
    ),
  },
  groups: {
    'G1': const GroupState(
      id: 'G1',
      coordinatorId: 'LR',
      memberIds: ['LR', 'KT'],
      transport: PlaybackState.playing,
      track: Track(title: 'Black Star'),
    ),
    'G2': const GroupState(
      id: 'G2',
      coordinatorId: 'OF',
      memberIds: ['OF'],
      transport: PlaybackState.playing,
      track: Track(title: 'Strobe'),
    ),
    'G3': const GroupState(
      id: 'G3',
      coordinatorId: 'BR',
      memberIds: ['BR'],
      transport: PlaybackState.stopped,
    ),
  },
);

void main() {
  test('derives one source per active group, idle excluded', () {
    final s = sourcesFromHousehold(_h());
    expect(s.map((e) => e.label), [
      'Living Room + Kitchen',
      'Office',
    ]); // sorted, BR(stopped) excluded
    expect(s.first.memberCount, 2);
    expect(s.first.track!.title, 'Black Star');
  });

  test('a paused group with a track is still a source', () {
    final h = _h();
    final g = h.groups['G2']!.copyWith(transport: PlaybackState.paused);
    final s = sourcesFromHousehold(
      Household(rooms: h.rooms, groups: {...h.groups, 'G2': g}),
    );
    expect(s.any((e) => e.label == 'Office'), isTrue);
  });
}
