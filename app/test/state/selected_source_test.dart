import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/selected_source.dart';

import 'fixture_household.dart';

final _household = Household(
  rooms: {
    'LR': const RoomState(
      id: 'LR',
      name: 'Living Room',
      kind: RoomKind.speaker,
      groupId: 'G_ACTIVE',
    ),
    'OF': const RoomState(
      id: 'OF',
      name: 'Office',
      kind: RoomKind.speaker,
      groupId: 'G_IDLE',
    ),
  },
  groups: {
    'G_ACTIVE': const GroupState(
      id: 'G_ACTIVE',
      coordinatorId: 'LR',
      memberIds: ['LR'],
      transport: PlaybackState.playing,
    ),
    'G_IDLE': const GroupState(
      id: 'G_IDLE',
      coordinatorId: 'OF',
      memberIds: ['OF'],
      transport: PlaybackState.stopped,
    ),
  },
);

ProviderContainer _container(Household household) {
  final container = ProviderContainer(
    overrides: [
      householdProvider.overrideWith(() => FixtureHousehold(household)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('defaults to the first active source when nothing is selected', () {
    expect(_container(_household).read(resolvedSourceProvider), 'G_ACTIVE');
  });

  test('honors an explicit selection of an existing (even idle) group', () {
    final container = _container(_household);
    container.read(selectedSourceProvider.notifier).select('G_IDLE');
    expect(container.read(resolvedSourceProvider), 'G_IDLE');
  });

  test('falls back to the default when the selected group is gone', () {
    final container = _container(_household);
    container.read(selectedSourceProvider.notifier).select('G_MISSING');
    expect(container.read(resolvedSourceProvider), 'G_ACTIVE');
  });

  test('resolves to null when there is no selection and no sources', () {
    final container = _container(const Household());
    expect(container.read(resolvedSourceProvider), isNull);
  });
}
