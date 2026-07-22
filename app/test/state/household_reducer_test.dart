import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/state/household_reducer.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/room_state.dart';

Topology _topo() => const Topology(
  speakers: [
    DiscoveredSpeaker(
      id: 'LR',
      roomName: 'Living Room',
      model: 'Beam',
      ip: '1',
    ),
    DiscoveredSpeaker(id: 'KT', roomName: 'Kitchen', model: 'One SL', ip: '2'),
  ],
  groups: [
    DiscoveredGroup(id: 'G1', coordinator: 'LR', members: ['LR', 'KT']),
  ],
);

void main() {
  test('fromTopology builds rooms+groups with group assignment', () {
    final h = householdFromTopology(_topo());
    expect(h.rooms['LR']!.groupId, 'G1');
    expect(h.rooms['LR']!.kind, RoomKind.soundbar);
    expect(h.groups['G1']!.memberIds, ['LR', 'KT']);
  });

  test('applyEvent Volume/Playback/GroupVolume update the right entity', () {
    var h = householdFromTopology(_topo());
    h = applyEvent(h, const ChangeEventDto.volume(speakerId: 'KT', volume: 42));
    expect(h.rooms['KT']!.volume, 42);
    h = applyEvent(
      h,
      const ChangeEventDto.playback(
        groupId: 'G1',
        state: PlaybackStateDto.playing,
      ),
    );
    expect(h.groups['G1']!.transport, PlaybackState.playing);
    h = applyEvent(
      h,
      const ChangeEventDto.groupVolume(groupId: 'G1', volume: 36),
    );
    expect(h.groups['G1']!.groupVolume, 36);
  });

  test('regroup preserves per-speaker volume', () {
    var h = householdFromTopology(_topo());
    h = applyEvent(h, const ChangeEventDto.volume(speakerId: 'KT', volume: 42));
    // New topology: KT split into its own group G2.
    const topo2 = Topology(
      speakers: [
        DiscoveredSpeaker(
          id: 'LR',
          roomName: 'Living Room',
          model: 'Beam',
          ip: '1',
        ),
        DiscoveredSpeaker(
          id: 'KT',
          roomName: 'Kitchen',
          model: 'One SL',
          ip: '2',
        ),
      ],
      groups: [
        DiscoveredGroup(id: 'G1b', coordinator: 'LR', members: ['LR']),
        DiscoveredGroup(id: 'G2', coordinator: 'KT', members: ['KT']),
      ],
    );
    final h2 = householdFromTopology(topo2, previous: h);
    expect(h2.rooms['KT']!.volume, 42, reason: 'volume survives regroup');
    expect(h2.rooms['KT']!.groupId, 'G2');
  });

  test(
    'regroup carries group transport + track by coordinator (stable across group-id change)',
    () {
      var h = householdFromTopology(_topo()); // G1: coord LR, members [LR, KT]
      h = applyEvent(
        h,
        const ChangeEventDto.playback(
          groupId: 'G1',
          state: PlaybackStateDto.playing,
        ),
      );
      h = applyEvent(
        h,
        const ChangeEventDto.track(
          groupId: 'G1',
          track: TrackDto(title: 'Black Star'),
        ),
      );
      h = applyEvent(
        h,
        const ChangeEventDto.groupVolume(groupId: 'G1', volume: 36),
      );
      // Regroup: same coordinator LR, NEW group id G1b.
      const topo2 = Topology(
        speakers: [
          DiscoveredSpeaker(
            id: 'LR',
            roomName: 'Living Room',
            model: 'Beam',
            ip: '1',
          ),
          DiscoveredSpeaker(
            id: 'KT',
            roomName: 'Kitchen',
            model: 'One SL',
            ip: '2',
          ),
        ],
        groups: [
          DiscoveredGroup(id: 'G1b', coordinator: 'LR', members: ['LR']),
          DiscoveredGroup(id: 'G2', coordinator: 'KT', members: ['KT']),
        ],
      );
      final h2 = householdFromTopology(topo2, previous: h);
      expect(
        h2.groups['G1b']!.transport,
        PlaybackState.playing,
        reason: 'transport carries by coordinator across new group id',
      );
      expect(
        h2.groups['G1b']!.track!.title,
        'Black Star',
        reason: 'track carries by coordinator',
      );
      expect(
        h2.groups['G1b']!.groupVolume,
        36,
        reason: 'group volume carries by coordinator',
      );
      expect(
        h2.groups['G2']!.transport,
        isNull,
        reason: 'a brand-new coordinator (KT) has no carried state',
      );
    },
  );

  test('event for unknown id is ignored', () {
    final h = householdFromTopology(_topo());
    expect(
      () => applyEvent(
        h,
        const ChangeEventDto.volume(speakerId: 'GHOST', volume: 9),
      ),
      returnsNormally,
    );
  });

  test('clearHealth resets a carried unreachable flag', () {
    final stale = householdFromTopology(_topo());
    final offline = stale.copyWith(
      rooms: {
        ...stale.rooms,
        'KT': stale.rooms['KT']!.copyWith(online: false),
      },
    );

    final fresh = householdFromTopology(
      _topo(),
      previous: offline,
      clearHealth: true,
    );

    expect(
      fresh.rooms['KT']!.online,
      isTrue,
      reason: 'a user-initiated scan stops asserting a stale unreachable flag',
    );
  });

  test('without clearHealth an unreachable room stays unreachable', () {
    final stale = householdFromTopology(_topo());
    final offline = stale.copyWith(
      rooms: {
        ...stale.rooms,
        'KT': stale.rooms['KT']!.copyWith(online: false),
      },
    );

    final fresh = householdFromTopology(_topo(), previous: offline);

    expect(
      fresh.rooms['KT']!.online,
      isFalse,
      reason:
          'the automatic fast-refresh path must not flap an off speaker back '
          'to online with no user action behind it',
    );
  });

  test('clearHealth leaves volume/mute carry-over untouched', () {
    final stale = householdFromTopology(_topo());
    final seeded = stale.copyWith(
      rooms: {
        ...stale.rooms,
        'KT': stale.rooms['KT']!.copyWith(volume: 42, muted: true),
      },
    );

    final fresh = householdFromTopology(
      _topo(),
      previous: seeded,
      clearHealth: true,
    );

    expect(fresh.rooms['KT']!.volume, 42);
    expect(fresh.rooms['KT']!.muted, isTrue);
  });
}
