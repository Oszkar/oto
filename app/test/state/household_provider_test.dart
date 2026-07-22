// Provider-level tests for HouseholdNotifier's initial seeding.
//
// Guards the init-order bug codex flagged on PR #80: if discovery has already
// resolved to AsyncData before householdProvider is first built, the provider
// must still seed its skeleton (not return an empty Household).
import 'dart:async';

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


/// A second topology, value-DIFFERENT from [_topo] so republishing it actually
/// transitions `discoveryProvider` (FRB `Topology` has value equality, so an
/// identical re-publish would not fire the listener).
Topology _topoV2() => const Topology(
  speakers: [
    DiscoveredSpeaker(
      id: 'LR',
      roomName: 'Living Room',
      model: 'Beam',
      ip: '1',
    ),
    DiscoveredSpeaker(id: 'KT', roomName: 'Kitchen', model: 'Era 100', ip: '2'),
  ],
  groups: [
    DiscoveredGroup(id: 'G1', coordinator: 'LR', members: ['LR', 'KT']),
  ],
);

/// A [Discovery] whose publishes can be driven by hand, including the
/// pathological interleaving where `lastPublish` describes a DIFFERENT topology
/// than the one being published.
class _DrivableDiscovery extends Discovery {
  _DrivableDiscovery(this._initial);
  final Topology _initial;

  @override
  Future<Topology> build() async {
    lastPublish = (topology: _initial, source: TopologySource.userScan);
    return _initial;
  }

  void publishAs(Topology topo, TopologySource source) {
    lastPublish = (topology: topo, source: source);
    state = AsyncValue.data(topo);
  }

  /// Publish [topo] while `lastPublish` still points at [describes] - the race
  /// where a fast refresh lands between `build()` completing and Riverpod
  /// publishing its value.
  void publishWithStaleSource(Topology topo, Topology describes) {
    lastPublish = (topology: describes, source: TopologySource.userScan);
    state = AsyncValue.data(topo);
  }
}

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

  group('health reset on re-publish', () {
    /// Seed the household, then knock KT offline with a SubscriptionError.
    Future<({ProviderContainer container, _DrivableDiscovery discovery})>
    seedWithOfflineKt() async {
      final events = StreamController<ChangeEventDto>.broadcast();
      addTearDown(events.close);
      final discovery = _DrivableDiscovery(_topo());
      final container = ProviderContainer(
        overrides: [
          discoveryProvider.overrideWith(() => discovery),
          changeEventsProvider.overrideWith((ref) => events.stream),
        ],
      );
      addTearDown(container.dispose);

      // Hold the event provider open for the test's lifetime. It is
      // autoDispose, and without an explicit subscription here the emission
      // below lands before the household's own listen is live - the setup then
      // silently no-ops and every assertion in this group passes vacuously.
      container.listen(changeEventsProvider, (_, _) {});
      container.read(householdProvider);
      await container.read(discoveryProvider.future);
      // Let the event-stream subscription actually attach before adding: a
      // broadcast stream drops anything emitted while nobody is listening,
      // which would make the setup silently no-op and the assertions vacuous.
      await pumpEventQueue();
      events.add(const ChangeEventDto.subscriptionError(
        speakerId: 'KT',
        message: 'network',
      ));
      await pumpEventQueue();
      expect(container.read(householdProvider).rooms['KT']!.online, isFalse);

      return (container: container, discovery: discovery);
    }

    test('a user-scan publish clears it', () async {
      final (:container, :discovery) = await seedWithOfflineKt();

      discovery.publishAs(_topoV2(), TopologySource.userScan);
      await pumpEventQueue();

      expect(container.read(householdProvider).rooms['KT']!.online, isTrue);
    });

    test('an automatic publish carries it forward', () async {
      final (:container, :discovery) = await seedWithOfflineKt();

      discovery.publishAs(_topoV2(), TopologySource.automatic);
      await pumpEventQueue();

      expect(
        container.read(householdProvider).rooms['KT']!.online,
        isFalse,
        reason:
            'a background regroup must not flap a genuinely-off speaker back '
            'to online with no user action behind it',
      );
    });

    test('a source describing a different topology does NOT clear', () async {
      // The race: `lastPublish` says user-scan, but about some OTHER
      // topology. Identity-matching must reject it and carry health forward -
      // a missed reset (the user can scan again) beats a spurious one.
      final (:container, :discovery) = await seedWithOfflineKt();

      discovery.publishWithStaleSource(_topoV2(), _topo());
      await pumpEventQueue();

      expect(container.read(householdProvider).rooms['KT']!.online, isFalse);
    });
  });
}
