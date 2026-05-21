/// Tests for `speakerStateProvider` (family) and `playbackCommandsProvider`:
/// asserts the terminal `AsyncValue.data` / `AsyncValue.error` states the
/// `speakerStateProvider` exposes when its result is injected via
/// `overrideWithValue`, and exercises the `overrideWithValue` seam for
/// the command facade (no logic of its own to assert today — real
/// command-layer behaviour is v0.5). These do *not* observe a real
/// loading→data/error transition; the async-throwing override that would
/// yield one races autoDispose on Riverpod 3.0.3.
///
/// `overrideWithValue(AsyncValue.…)` (restored in Riverpod 3.0.2) is the
/// canonical async-test seam for this scenario.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/playback.dart';

void main() {
  group('speakerStateProvider', () {
    const speakerId = 'RINCON_KITCHEN';
    const fakeState = rust_api.SpeakerStateDto(volume: 42, muted: false);

    test('exposes AsyncValue.data on success', () {
      final container = ProviderContainer(
        overrides: [
          speakerStateProvider(speakerId)
              .overrideWithValue(const AsyncValue.data(fakeState)),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(speakerStateProvider(speakerId));
      expect(state.hasValue, isTrue);
      expect(state.value, equals(fakeState));
    });

    test('exposes CommandError as AsyncValue.error', () {
      final error = rust_api.CommandError.notFound(speakerId);
      final container = ProviderContainer(
        overrides: [
          speakerStateProvider(speakerId)
              .overrideWithValue(AsyncValue.error(error, StackTrace.empty)),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(speakerStateProvider(speakerId));
      expect(state.hasError, isTrue);
      expect(state.error, equals(error));
    });
  });

  group('playbackCommandsProvider', () {
    test('overrideWithValue exposes a test seam for v0.5', () {
      // The provider returns a `const PlaybackCommands()` facade whose
      // methods are bare pass-throughs to the FRB bindings — no logic
      // to assert today. This proves the override seam works so a v0.5
      // command-layer implementation can be swapped in for tests.
      final container = ProviderContainer(
        overrides: [
          playbackCommandsProvider.overrideWithValue(const _FakeCommands()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(playbackCommandsProvider), isA<_FakeCommands>());
    });
  });
}

class _FakeCommands extends PlaybackCommands {
  const _FakeCommands();
}
