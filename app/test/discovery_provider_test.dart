import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/discovery.dart';

void main() {
  test('discovery provider is wired (compile-level proof, D2)', () {
    // The generated `discoveryProvider` only exists if discovery.dart
    // compiled — and discovery.dart calls the FRB `rust_api.discover()`
    // binding, so this also guards that the binding is present. The
    // live discovery call needs a LAN; that's the user-run Task 8.
    expect(discoveryProvider, isNotNull);
  });
}
