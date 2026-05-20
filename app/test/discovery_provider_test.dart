/// Tests for `discoveryProvider`: drives the AsyncValue loading → data
/// and loading → error transitions via a `ProviderContainer` override,
/// without touching FRB or a real LAN. The compile-level smoke that the
/// generated provider name resolves is implicit (test won't compile
/// otherwise).
///
/// Uses `overrideWithValue(AsyncValue.…)` — restored in Riverpod 3.0.2
/// as the canonical async-test seam — instead of async-throwing
/// overrides (which race autoDispose and produce `StateError: provider
/// disposed during loading` here).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/discovery.dart';

void main() {
  group('discoveryProvider', () {
    const fakeTopology = rust_api.Topology(
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

    test('exposes AsyncValue.data on success', () {
      final container = ProviderContainer(
        overrides: [
          discoveryProvider.overrideWithValue(const AsyncValue.data(fakeTopology)),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(discoveryProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, equals(fakeTopology));
    });

    test('exposes DiscoveryError as AsyncValue.error', () {
      final error = rust_api.DiscoveryError.noDevicesFound();
      final container = ProviderContainer(
        overrides: [
          discoveryProvider.overrideWithValue(AsyncValue.error(error, StackTrace.empty)),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(discoveryProvider);
      expect(state.hasError, isTrue);
      expect(state.error, equals(error));
    });
  });
}
