/// Tests for `discoveryProvider`: asserts the terminal `AsyncValue.data`
/// and `AsyncValue.error` states the provider exposes when its result is
/// injected via `overrideWithValue`. These do *not* observe an actual
/// loading→data/error transition — the async-throwing override form that
/// would yield one races autoDispose on Riverpod 3.0.3 (provider gets
/// disposed during the loading state before the throw can propagate,
/// surfacing as `StateError: provider disposed during loading`).
/// `overrideWithValue(AsyncValue.…)` (restored in Riverpod 3.0.2) is the
/// canonical async-test seam for this scenario.
///
/// FRB and a real LAN are bypassed entirely. The compile-level smoke
/// that the generated provider name resolves is implicit (test won't
/// compile otherwise).
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
