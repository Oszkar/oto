import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/sources.dart';

import 'fixture_household.dart';

Household _household({int? lrVolume}) => Household(
  rooms: {
    'LR': RoomState(
      id: 'LR',
      name: 'Living Room',
      kind: RoomKind.speaker,
      groupId: 'G1',
      volume: lrVolume,
    ),
  },
  groups: {
    'G1': const GroupState(
      id: 'G1',
      coordinatorId: 'LR',
      memberIds: ['LR'],
      transport: PlaybackState.playing,
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
  test('does not notify when an unrelated field changes the household', () {
    final container = _container(_household(lrVolume: 10));
    var notifications = 0;
    container.listen(sourcesProvider, (_, _) => notifications++);

    // Volume is not part of a Source (id / label / track / memberCount), so the
    // derived list is value-equal after this change.
    container.read(householdProvider.notifier).setOptimisticVolume('LR', 55);

    expect(container.read(sourcesProvider).length, 1);
    expect(
      notifications,
      0,
      reason: 'an unrelated household delta must not rebuild source consumers',
    );
  });

  test('notifies when the source set actually changes', () {
    final container = _container(_household(lrVolume: 10));
    var notifications = 0;
    container.listen(sourcesProvider, (_, _) => notifications++);

    // Stopping the group drops it out of the active-source list.
    container
        .read(householdProvider.notifier)
        .setOptimisticTransport('G1', PlaybackState.stopped);

    expect(container.read(sourcesProvider), isEmpty);
    expect(
      notifications,
      1,
      reason: 'a genuine change to the source list emits exactly one notify',
    );
  });
}
