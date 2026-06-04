/// Tests for `discoveryProvider`: asserts the terminal `AsyncValue.data`
/// and `AsyncValue.error` states the provider exposes.
///
/// Since v0.5.1 `discoveryProvider` is a class-based async Notifier
/// ([Discovery]) so it can expose `refreshTopology()`. The test seam is now
/// `overrideWith(() => FakeNotifier())` (not `overrideWithValue`): the fake's
/// `build()` returns the fixture or throws, yielding the terminal data/error
/// state synchronously for a `ProviderContainer.read`.
///
/// FRB and a real LAN are bypassed entirely. The compile-level smoke that the
/// generated provider name resolves is implicit (test won't compile otherwise).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/discovery.dart';

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

/// Fake [Discovery] whose `build()` returns the fixture synchronously (the
/// returned value, not a Future, so the container reads `AsyncValue.data`
/// immediately).
class _DataDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async => _fakeTopology;
}

/// Fake [Discovery] whose `build()` throws, so the container surfaces
/// `AsyncValue.error`.
class _ErrorDiscovery extends Discovery {
  @override
  Future<rust_api.Topology> build() async =>
      throw rust_api.DiscoveryError.noDevicesFound();
}

void main() {
  group('discoveryProvider', () {
    // Listen (keeping the autoDispose provider mounted across the async gap)
    // and pump microtasks until the loading state settles into the terminal
    // AsyncValue. We assert on the AsyncValue rather than awaiting
    // `provider.future`: a class-Notifier `build()` that throws races
    // autoDispose, so `.future` surfaces a `StateError: disposed during
    // loading` instead of the real error (this Riverpod) — the AsyncValue is
    // the stable seam the old `overrideWithValue` test relied on.
    Future<AsyncValue<rust_api.Topology>> settledState(
      ProviderContainer container,
    ) async {
      AsyncValue<rust_api.Topology>? last;
      container.listen(
        discoveryProvider,
        (_, next) => last = next,
        fireImmediately: true,
      );
      // Drain all pending microtasks so the Notifier's build() future settles
      // (success → AsyncData, throw → AsyncError) before we read the state.
      await pumpEventQueue();
      return last!;
    }

    test('exposes AsyncValue.data on success', () async {
      final container = ProviderContainer(
        overrides: [discoveryProvider.overrideWith(_DataDiscovery.new)],
      );
      addTearDown(container.dispose);

      final state = await settledState(container);
      expect(state.hasValue, isTrue);
      expect(state.value, equals(_fakeTopology));
    });

    test('exposes DiscoveryError as AsyncValue.error', () async {
      final container = ProviderContainer(
        overrides: [discoveryProvider.overrideWith(_ErrorDiscovery.new)],
      );
      addTearDown(container.dispose);

      final state = await settledState(container);
      expect(state.hasError, isTrue);
      expect(state.error, isA<rust_api.DiscoveryError>());
    });
  });
}
