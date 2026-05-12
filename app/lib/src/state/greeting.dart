import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;

part 'greeting.g.dart';

/// Demo provider — calls the Rust `greet` function over the FRB bridge.
///
/// Once real Sonos providers exist this can go away. It exists in the scaffold
/// to prove that Riverpod, the FRB bridge, and `ConsumerWidget` are wired up
/// end-to-end.
@riverpod
String greeting(Ref ref, {required String name}) {
  return rust_api.greet(name: name);
}
