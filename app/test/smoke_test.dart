import 'package:flutter_test/flutter_test.dart';

/// Dart-only smoke test. Anything that goes over the FRB bridge needs a real
/// native library loaded — that's covered by `integration_test/`, which runs
/// on a device or emulator. This file exists so `flutter test` has at least
/// one passing test in CI without a device attached.
void main() {
  test('test harness is wired up', () {
    expect(1 + 1, equals(2));
  });
}
