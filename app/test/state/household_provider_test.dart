// Provider-level tests for HouseholdNotifier's initial seeding.
//
// Guards the init-order bug codex flagged on PR #80: if discovery has already
// resolved to AsyncData before householdProvider is first built, the provider
// must still seed its skeleton (not return an empty Household).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/household.dart';

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

class _FakeDiscovery extends Discovery {
  _FakeDiscovery(this._topoVal);
  final Topology _topoVal;
  @override
  Future<Topology> build() async => _topoVal;
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    discoveryProvider.overrideWith(() => _FakeDiscovery(_topo())),
    changeEventsProvider.overrideWith(
      (ref) => const Stream<ChangeEventDto>.empty(),
    ),
  ],
);

void main() {
  test(
    'seeds household when discovery already resolved before first build',
    () async {
      final container = _container();
      addTearDown(container.dispose);

      // The ordering codex flagged: discovery completes BEFORE the UI first
      // reads household state.
      await container.read(discoveryProvider.future);

      final h = container.read(householdProvider);
      expect(
        h.rooms,
        isNotEmpty,
        reason:
            'household must seed from already-resolved discovery, not stay empty',
      );
      expect(h.rooms['LR']?.groupId, 'G1');
      expect(h.groups['G1']?.memberIds, ['LR', 'KT']);
    },
  );

  test('empty at build while discovery loads, then seeds on resolve', () async {
    final container = _container();
    addTearDown(container.dispose);

    // First build while discovery is still loading -> empty skeleton.
    final initial = container.read(householdProvider);
    expect(initial.rooms, isEmpty);

    // Discovery resolves -> the listener folds the topology in.
    await container.read(discoveryProvider.future);
    final seeded = container.read(householdProvider);
    expect(seeded.rooms['LR']?.groupId, 'G1');
  });
}
