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

import 'package:oto/src/rust/frb_generated.dart';
import 'showcase_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise the bridge so the app runs in a realistic environment. The
  // showcase itself drives zero FFI (all backend-touching providers are
  // overridden), but init keeps parity with the real `main.dart`.
  await RustLib.init();
  runApp(const ShowcaseApp());
}
