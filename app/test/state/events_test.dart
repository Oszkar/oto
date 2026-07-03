/// Tests for the event-stream keying in `events.dart`:
///   - `wireGenerationProvider` reflects the authoritative Rust generation and
///     recomputes when a wire is (re)installed, and
///   - `changeEventsProvider` re-subscribes EXACTLY once per new wire.
///
/// The re-subscribe is keyed on the wire GENERATION, not on a topology value
/// transition. The subtle case a value-equal fast `refreshTopology()` (a no-op
/// regroup publishes an unchanged `Topology`, so `discoveryProvider` does not
/// transition) must still re-subscribe, because the Rust wire was replaced and
/// its previous one-shot receiver is dead. That path is driven by
/// [wireInstallSignalProvider], which this suite bumps directly.
///
/// FRB is bypassed via two overridable seams: [wireGenerationReaderProvider]
/// (a controllable generation counter) and [changeEventStreamFactoryProvider]
/// (a counting stream factory, so a re-subscribe is observable as an extra
/// factory call). `discoveryProvider` is faked so `hasValue` can be driven
/// without a real LAN.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';

const _fakeTopology = rust_api.Topology(
  speakers: [
    rust_api.DiscoveredSpeaker(
      id: 'RINCON_KITCHEN',
      roomName: 'Kitchen',
      ip: '10.0.0.10',
    ),
  ],
  groups: [
    rust_api.DiscoveredGroup(
      id: 'RINCON_KITCHEN:0',
      coordinator: 'RINCON_KITCHEN',
      members: ['RINCON_KITCHEN'],
    ),
  ],
);

/// Discovery whose `build()` resolves immediately to the fixture (hasValue
/// latches true after the microtask drain).
class _DataDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async => _fakeTopology;
}

/// Discovery that never resolves — stays `AsyncLoading`, so `hasValue` is
/// false and no wire is installed.
class _LoadingDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() => Completer<rust_api.Topology>().future;
}

void main() {
  // Controllable generation the reader seam returns. Mutate between reads to
  // simulate the Rust generation bumping on a wire install.
  late BigInt generation;
  // How many times the change-event stream factory ran = number of
  // subscribeChangeEvents() calls = number of (re)subscriptions.
  late int subscribeCount;

  setUp(() {
    generation = BigInt.zero;
    subscribeCount = 0;
  });

  ProviderContainer makeContainer(Discovery Function() discovery) =>
      ProviderContainer(
        overrides: [
          discoveryProvider.overrideWith(discovery),
          wireGenerationReaderProvider.overrideWith((ref) => () => generation),
          changeEventStreamFactoryProvider.overrideWith(
            (ref) => () {
              subscribeCount++;
              return const Stream<rust_api.ChangeEventDto>.empty();
            },
          ),
        ],
      );

  group('wireGeneration', () {
    test('is null while discovery has no value', () async {
      final container = makeContainer(_LoadingDiscovery.new);
      addTearDown(container.dispose);
      container.listen(wireGenerationProvider, (_, _) {}, fireImmediately: true);

      expect(container.read(wireGenerationProvider), isNull);
    });

    test('reads the generation once discovery has a value', () async {
      generation = BigInt.from(7);
      final container = makeContainer(_DataDiscovery.new);
      addTearDown(container.dispose);
      container.listen(wireGenerationProvider, (_, _) {}, fireImmediately: true);

      await container.read(discoveryProvider.future);
      expect(container.read(wireGenerationProvider), BigInt.from(7));
    });
  });

  group('changeEvents', () {
    test('does not subscribe while no wire is installed', () async {
      final container = makeContainer(_LoadingDiscovery.new);
      addTearDown(container.dispose);
      container.listen(changeEventsProvider, (_, _) {}, fireImmediately: true);
      await pumpEventQueue();

      expect(subscribeCount, 0, reason: 'null generation must yield an empty stream');
    });

    test('subscribes once when the first wire is installed', () async {
      generation = BigInt.from(1);
      final container = makeContainer(_DataDiscovery.new);
      addTearDown(container.dispose);
      container.listen(changeEventsProvider, (_, _) {}, fireImmediately: true);

      await container.read(discoveryProvider.future);
      await pumpEventQueue();

      expect(subscribeCount, 1, reason: 'first wire → exactly one subscription');
    });

    test('re-subscribes on a value-equal refresh (install signal bumps the '
        'generation without a discovery transition)', () async {
      generation = BigInt.from(1);
      final container = makeContainer(_DataDiscovery.new);
      addTearDown(container.dispose);
      container.listen(changeEventsProvider, (_, _) {}, fireImmediately: true);

      await container.read(discoveryProvider.future);
      await pumpEventQueue();
      expect(subscribeCount, 1);

      // A no-op regroup: the Rust wire was replaced (generation bumps) but the
      // Topology value is unchanged, so discoveryProvider does NOT transition.
      // Only the install signal fires.
      generation = BigInt.from(2);
      container.read(wireInstallSignalProvider.notifier).bump();
      await pumpEventQueue();

      expect(
        subscribeCount,
        2,
        reason: 'a new wire generation must re-subscribe even without a '
            'discovery transition',
      );
    });

    test('does not re-subscribe when the generation is unchanged '
        '(one-shot receiver safety)', () async {
      generation = BigInt.from(1);
      final container = makeContainer(_DataDiscovery.new);
      addTearDown(container.dispose);
      container.listen(changeEventsProvider, (_, _) {}, fireImmediately: true);

      await container.read(discoveryProvider.future);
      await pumpEventQueue();
      expect(subscribeCount, 1);

      // Signal fires but the generation did NOT change (e.g. a failed install
      // that did not bump the Rust generation). Re-subscribing here would take
      // the wire's one-shot receiver twice and strand the stream — so it must
      // stay at one subscription.
      container.read(wireInstallSignalProvider.notifier).bump();
      await pumpEventQueue();

      expect(subscribeCount, 1, reason: 'unchanged generation must not re-subscribe');
    });
  });
}
