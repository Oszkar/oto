/// v0.4 end-to-end skeleton acceptance test. Drives MockWire via
/// `dev_discover_mock` and asserts the full Dart->Rust->Dart event
/// loop works: seed Volume events arrive, mutation auto-emits, and an
/// adversarial SubscriptionError pushed via `MockWire::push_event`
/// surfaces in Dart.
///
/// Run on a connected Windows desktop (this is a Windows-host slice):
///
/// ```text
/// cd app && flutter test integration_test/v0_4_events_test.dart -d windows
/// ```
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oto/src/rust/api.dart' as api;
import 'package:oto/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  test('v0.4 end-to-end: discover -> seed Volume -> mutation -> error', () async {
    // 1. Discover via MockWire. This auto-invokes subscribe_speakers.
    final topology = await api.devDiscoverMock();
    expect(topology.speakers.length, 3);

    // 2. Subscribe to the unified event stream.
    final events = <api.ChangeEventDto>[];
    final seedComplete = Completer<void>();
    final sub = api.subscribeChangeEvents().listen((event) {
      events.add(event);
      // Seed phase: 3 Volume events (one per speaker) arrive.
      if (events.length == 3 && !seedComplete.isCompleted) {
        seedComplete.complete();
      }
    });

    await seedComplete.future.timeout(const Duration(seconds: 5));

    // All three seed events are Volume.
    for (final ev in events.take(3)) {
      expect(ev, isA<api.ChangeEventDto_Volume>());
    }

    // 3. Mutation: set volume on Kitchen -> ChangeEventDto.Volume arrives.
    events.clear();
    await api.setVolume(speakerId: 'RINCON_KITCHEN', volume: 75);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(events, hasLength(1));
    final volEv = events.first;
    expect(volEv, isA<api.ChangeEventDto_Volume>());
    volEv as api.ChangeEventDto_Volume;
    expect(volEv.speakerId, 'RINCON_KITCHEN');
    expect(volEv.volume, 75);

    // 4. Adversarial: a SubscriptionError pushed onto the held MockWire
    //    surfaces in Dart unchanged.
    events.clear();
    await api.devPushSubscriptionErrorOnMock(
      speakerId: 'RINCON_GHOST',
      message: 'synthesized for integration test',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(events, hasLength(1));
    final errEv = events.first;
    expect(errEv, isA<api.ChangeEventDto_SubscriptionError>());
    errEv as api.ChangeEventDto_SubscriptionError;
    expect(errEv.speakerId, 'RINCON_GHOST');
    expect(errEv.message, 'synthesized for integration test');

    // Don't `await sub.cancel()`: it waits for the Rust loop's next
    // `sink.add(...)` to fail before returning, but the loop is now
    // blocked in `rx.recv()` waiting for the next event (we have no
    // more events to push). Fire-and-forget cancel; the Rust loop
    // will tear down naturally when the cdylib unloads at process
    // exit, or on the next `discover()` (Sender drop -> recv Err).
    unawaited(sub.cancel());
  });
}
