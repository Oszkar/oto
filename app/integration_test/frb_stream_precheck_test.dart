/// v0.4 FRB Stream surface pre-check (DEV-ONLY, integration test).
///
/// Empirically verifies that FRB v2's `Stream<T>` surface behaves the way
/// the v0.4 spec assumes — before `StateManager`'s event-stream is
/// designed against it. The three Rust dev-only fns under test live in
/// `native/src/api.rs` and will be removed when `subscribe_change_events`
/// lands.
///
/// Findings note (filled in after first run):
/// `docs/superpowers/specs/2026-05-22-v0.4-frb-precheck-findings.md`.
///
/// Not gated by CI (same as `simple_test.dart` — Flutter's
/// `integration_test` needs a display/device target). Run on a connected
/// Windows desktop or Android device with:
///
/// ```text
/// flutter test integration_test/frb_stream_precheck_test.dart
/// ```
///
/// Three assertions cover the four FRB-stream questions from the v0.4
/// spec § 3.2 that are testable headlessly. The fifth (hot-reload
/// behaviour) is observed manually via `flutter run` and recorded in the
/// findings doc directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oto/src/rust/api.dart' as rust;
import 'package:oto/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());

  test('dev_tick_stream emits exactly `count` ticks and completes', () async {
    final stream = rust.devTickStream(intervalMs: 50, count: 5);
    final received = <BigInt>[];
    await stream.forEach(received.add);
    expect(received, equals([0, 1, 2, 3, 4].map(BigInt.from).toList()));
  });

  test('dev_tick_stream cancellation is observed by Rust', () async {
    // Snapshot the cancel counter before, run a long-count stream,
    // cancel mid-flight, then read the counter again. A Rust-side
    // increment proves `sink.add(...).is_err()` after a Dart cancel —
    // i.e. cancellation is detectable without polling.
    final before = await rust.devCancelObservationsCount();

    final stream = rust.devTickStream(intervalMs: 50, count: 100);
    final received = <BigInt>[];
    final sub = stream.listen(received.add);

    // Let ~3 ticks land, then cancel.
    await Future<void>.delayed(const Duration(milliseconds: 175));
    await sub.cancel();

    // Give Rust one more sleep cycle to attempt the next `sink.add` and
    // observe the failure (50 ms loop + slack).
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final after = await rust.devCancelObservationsCount();

    expect(
      after,
      greaterThan(before),
      reason: 'sink.add did not return Err after Dart subscription cancel; '
          'cancellation is not detectable',
    );
    // Loosely: we expected ~3 ticks. Don't assert exact count — timing
    // is flaky on slow CI / busy hosts. Just that some arrived.
    expect(received, isNotEmpty);
  });

  test('dev_error_stream propagates error to onError', () async {
    final stream = rust.devErrorStream();
    final received = <BigInt>[];
    Object? caughtError;

    try {
      await stream.forEach(received.add);
    } catch (e) {
      caughtError = e;
    }

    expect(received, hasLength(3));
    expect(
      caughtError,
      isNotNull,
      reason: 'sink.add_error(...) on the Rust side did not surface as a '
          'Dart Stream error in Stream.forEach',
    );
    expect(
      caughtError.toString(),
      contains('intentional error'),
      reason: 'Rust error message not preserved across the FRB boundary',
    );
  });
}
