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

  test('returns an unmodifiable list', () {
    final s = sourcesFromHousehold(_h());
    expect(() => s.clear(), throwsUnsupportedError);
  });

  test('a paused group with a track is still a source', () {
    final h = _h();
    final g = h.groups['G2']!.copyWith(transport: PlaybackState.paused);
    final s = sourcesFromHousehold(
      Household(rooms: h.rooms, groups: {...h.groups, 'G2': g}),
    );
    expect(s.any((e) => e.label == 'Office'), isTrue);
  });

  group('hasActiveStream - phantom-source guards', () {
    // Sonos emits an EMPTY track (all fields null) on stop/clear, and the
    // reducer can't null a track back out, so a stopped group keeps a
    // non-null-but-empty track. None of these may count as a source.
    test('stopped group with an empty track is NOT a source', () {
      const g = GroupState(
        id: 'G',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.stopped,
        track: Track(), // empty: all fields null
      );
      expect(g.hasActiveStream, isFalse);
    });

    test('paused/transitioning with an empty or absent track is NOT a source', () {
      const pausedEmpty = GroupState(
        id: 'G',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.paused,
        track: Track(),
      );
      const transitioningNoTrack = GroupState(
        id: 'G',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.transitioning,
      );
      expect(pausedEmpty.hasActiveStream, isFalse);
      expect(transitioningNoTrack.hasActiveStream, isFalse);
    });

    test('playing with no metadata yet IS a source', () {
      // `playing` counts even before the Track event lands (radio / line-in /
      // the brief pre-metadata window) - exercised by the integration test.
      const g = GroupState(
        id: 'G',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.playing,
      );
      expect(g.hasActiveStream, isTrue);
    });

    test('paused with a content-bearing track IS a source (resumable)', () {
      const g = GroupState(
        id: 'G',
        coordinatorId: 'LR',
        memberIds: ['LR'],
        transport: PlaybackState.paused,
        track: Track(title: 'Strobe'),
      );
      expect(g.hasActiveStream, isTrue);
    });
  });
}
