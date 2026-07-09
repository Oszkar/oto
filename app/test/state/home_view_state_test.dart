import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/home_view_state.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';

import 'fixture_household.dart';

const _emptyTopology = rust_api.Topology(speakers: [], groups: []);

const _oneRoomTopology = rust_api.Topology(
  speakers: [
    rust_api.DiscoveredSpeaker(
      id: 'RINCON_OFFICE',
      roomName: 'Office',
      ip: '10.0.0.10',
      model: 'Move 2',
    ),
  ],
  groups: [
    rust_api.DiscoveredGroup(
      id: 'RINCON_OFFICE:0',
      coordinator: 'RINCON_OFFICE',
      members: ['RINCON_OFFICE'],
    ),
  ],
);

const _cachedHousehold = Household(
  rooms: {
    'RINCON_OFFICE': RoomState(
      id: 'RINCON_OFFICE',
      name: 'Office',
      model: 'Move 2',
      kind: RoomKind.speaker,
      volume: 30,
      online: true,
      groupId: 'RINCON_OFFICE:0',
    ),
  },
  groups: {
    'RINCON_OFFICE:0': GroupState(
      id: 'RINCON_OFFICE:0',
      coordinatorId: 'RINCON_OFFICE',
      memberIds: ['RINCON_OFFICE'],
      transport: PlaybackState.stopped,
    ),
  },
);

class _LoadingDiscovery extends Discovery {
  final _completer = Completer<rust_api.Topology>();

  @override
  Future<rust_api.Topology> build() => _completer.future;
}

class _CompletingDiscovery extends Discovery {
  final _completer = Completer<rust_api.Topology>();

  void complete(rust_api.Topology topology) => _completer.complete(topology);

  @override
  Future<rust_api.Topology> build() => _completer.future;
}

class _DataDiscovery extends Discovery {
  _DataDiscovery(this._topology);

  final rust_api.Topology _topology;

  @override
  Future<rust_api.Topology> build() async => _topology;
}

class _ErrorDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async =>
      throw rust_api.DiscoveryError.noDevicesFound();
}

class _SequenceDiscovery extends Discovery {
  _SequenceDiscovery(this._next);

  final Future<rust_api.Topology> Function() _next;

  @override
  Future<rust_api.Topology> build() => _next();
}

ProviderContainer _container({
  required Discovery Function() discovery,
  Household household = const Household(),
}) {
  final container = ProviderContainer(
    overrides: [
      discoveryProvider.overrideWith(discovery),
      householdProvider.overrideWith(() => FixtureHousehold(household)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<HomeViewState> _settledState(ProviderContainer container) async {
  HomeViewState? last;
  container.listen(
    homeViewStateProvider,
    (_, next) => last = next,
    fireImmediately: true,
  );
  await pumpEventQueue();
  return last!;
}

ProviderContainer _containerWithRealHousehold({
  required Discovery Function() discovery,
}) {
  final container = ProviderContainer(
    overrides: [
      discoveryProvider.overrideWith(discovery),
      changeEventsProvider.overrideWith(
        (ref) => const Stream<rust_api.ChangeEventDto>.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('homeViewStateProvider', () {
    test('initial loading when discovery is loading and no cache exists', () {
      final container = _container(discovery: _LoadingDiscovery.new);

      expect(container.read(homeViewStateProvider), isA<HomeInitialLoading>());
    });

    test(
      'discovering with cache when discovery is loading and household exists',
      () {
        final container = _container(
          discovery: _LoadingDiscovery.new,
          household: _cachedHousehold,
        );

        final state = container.read(homeViewStateProvider);
        expect(state, isA<HomeDiscoveringWithCache>());
        expect((state as HomeDiscoveringWithCache).household, _cachedHousehold);
      },
    );

    test('empty when discovery succeeds with no speakers', () async {
      final container = _container(
        discovery: () => _DataDiscovery(_emptyTopology),
      );

      final state = await _settledState(container);
      expect(state, isA<HomeEmpty>());
    });

    test('ready when discovery succeeds and household exists', () async {
      final container = _container(
        discovery: () => _DataDiscovery(_oneRoomTopology),
        household: _cachedHousehold,
      );

      final state = await _settledState(container);
      expect(state, isA<HomeReady>());
      expect((state as HomeReady).household, _cachedHousehold);
    });

    test(
      'non-empty topology with an unseeded household shows loading, not empty Ready',
      () async {
        // Discovery resolved with a speaker, but the household reducer hasn't
        // folded it yet (empty household) - a transient settle frame.
        final container = _container(
          discovery: () => _DataDiscovery(_oneRoomTopology),
          // household defaults to const Household() (empty).
        );

        final state = await _settledState(container);
        expect(
          state,
          isA<HomeInitialLoading>(),
          reason:
              'must not flash an empty HomeReady before the household seeds',
        );
      },
    );

    test(
      'ready from real household never carries an empty household',
      () async {
        final discovery = _CompletingDiscovery();
        final container = _containerWithRealHousehold(
          discovery: () => discovery,
        );
        final states = <HomeViewState>[];
        container.listen(
          homeViewStateProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        discovery.complete(_oneRoomTopology);
        await pumpEventQueue();

        final readyStates = states.whereType<HomeReady>().toList();
        expect(readyStates, isNotEmpty);
        expect(
          readyStates,
          everyElement(
            isA<HomeReady>().having(
              (state) => state.household.rooms,
              'rooms',
              isNotEmpty,
            ),
          ),
        );
      },
    );

    test(
      'error without cache when discovery fails before any household exists',
      () async {
        final container = _container(discovery: _ErrorDiscovery.new);

        final state = await _settledState(container);
        expect(state, isA<HomeDiscoveryFailedNoCache>());
        expect(
          (state as HomeDiscoveryFailedNoCache).error,
          isA<rust_api.DiscoveryError>(),
        );
      },
    );

    test(
      'error with cache when discovery fails after household exists',
      () async {
        final container = _container(
          discovery: _ErrorDiscovery.new,
          household: _cachedHousehold,
        );

        final state = await _settledState(container);
        expect(state, isA<HomeDiscoveryFailedWithCache>());
        expect(
          (state as HomeDiscoveryFailedWithCache).error,
          isA<rust_api.DiscoveryError>(),
        );
        expect(state.household, _cachedHousehold);
      },
    );

    test('retry after no-cache failure returns to initial loading', () async {
      final retry = Completer<rust_api.Topology>();
      var buildCount = 0;
      final container = _container(
        discovery: () => _SequenceDiscovery(() {
          buildCount++;
          if (buildCount == 1) {
            throw rust_api.DiscoveryError.noDevicesFound();
          }
          return retry.future;
        }),
      );

      expect(await _settledState(container), isA<HomeDiscoveryFailedNoCache>());

      unawaited(container.read(discoveryProvider.notifier).rediscover());
      await pumpEventQueue();

      expect(container.read(homeViewStateProvider), isA<HomeInitialLoading>());
    });

    test(
      'retry after cached failure returns to discovering with cache',
      () async {
        final retry = Completer<rust_api.Topology>();
        var buildCount = 0;
        final container = _container(
          discovery: () => _SequenceDiscovery(() {
            buildCount++;
            if (buildCount == 1) {
              throw rust_api.DiscoveryError.noDevicesFound();
            }
            return retry.future;
          }),
          household: _cachedHousehold,
        );

        expect(
          await _settledState(container),
          isA<HomeDiscoveryFailedWithCache>(),
        );

        unawaited(container.read(discoveryProvider.notifier).rediscover());
        await pumpEventQueue();

        final state = container.read(homeViewStateProvider);
        expect(state, isA<HomeDiscoveringWithCache>());
        expect((state as HomeDiscoveringWithCache).household, _cachedHousehold);
      },
    );
  });

  group('HomeViewState value equality', () {
    test('HomeReady compares by household', () {
      expect(HomeReady(_cachedHousehold), HomeReady(_cachedHousehold));
      expect(
        HomeReady(_cachedHousehold) == const HomeReady(Household()),
        isFalse,
      );
    });

    test('singleton states are value-equal', () {
      expect(const HomeInitialLoading(), const HomeInitialLoading());
      expect(const HomeEmpty(), const HomeEmpty());
      expect(const HomeInitialLoading() == const HomeEmpty(), isFalse);
    });

    test('failure states compare by their fields', () {
      final err = rust_api.DiscoveryError.noDevicesFound();
      expect(HomeDiscoveryFailedNoCache(err), HomeDiscoveryFailedNoCache(err));
      expect(
        HomeDiscoveryFailedWithCache(_cachedHousehold, err),
        HomeDiscoveryFailedWithCache(_cachedHousehold, err),
      );
      expect(
        HomeDiscoveringWithCache(_cachedHousehold),
        HomeDiscoveringWithCache(_cachedHousehold),
      );
    });
  });
}
