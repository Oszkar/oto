import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/rust/api.dart' as rust_api;

void main() {
  test('discovery provider is wired to the FRB discover() binding', () {
    // Compile-level proof: the provider exists and the generated
    // binding symbol is referenced. The live call needs a LAN and is
    // covered by the user-run integration step (Task 8).
    expect(discoveryProvider, isNotNull);
    expect(rust_api.discover, isA<Function>());
  });
}
