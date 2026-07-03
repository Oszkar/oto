/// Entry point for the oto design-system showcase - a fixture-driven, live
/// gallery of every screen and presentation state.
///
///   flutter run -t lib/showcase/main.dart
///
/// Dev-only tooling: this target is never part of the shipped app. It renders
/// real screens against hand-authored fixtures with no LAN or Sonos hardware,
/// and hot reload turns it into a live design board. See `showcase_app.dart`.
library;

import 'package:flutter/widgets.dart';

import 'showcase_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Deliberately NO `RustLib.init()`: the showcase drives zero FFI (every
  // backend-touching provider is overridden with a fixture double), so skipping
  // init keeps it truly backend-free and makes any accidental Rust call
  // fail-fast instead of silently reaching for a native library. The smoke test
  // enforces the same contract by pumping every entry without init.
  runApp(const ShowcaseApp());
}
