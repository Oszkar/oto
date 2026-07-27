import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oto/src/platform/window_bounds.dart';
import 'package:oto/src/rust/frb_generated.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/ui/shell/oto_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // #104: this is the one startup path with no graceful-degradation option -
  // every other failure mode in the app (discovery, subscriptions, the
  // multicast lock) is explicit and recoverable, but a throw from either of
  // these two awaits used to leave a permanently blank window with the error
  // only in the log. Fall back to a minimal, dependency-free failure surface
  // instead - it must not itself depend on the Rust bridge or a ProviderScope,
  // since either of those is exactly what may have just failed to initialize.
  SharedPreferences? prefs;
  Object? startupError;
  try {
    await RustLib.init();
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    startupError = e;
  }
  if (startupError != null || prefs == null) {
    runApp(_StartupFailureApp(error: startupError ?? 'Unknown startup error'));
    return;
  }

  await initWindowBounds(prefs);
  runApp(
    ProviderScope(
      overrides: [
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
      ],
      child: const OtoApp(),
    ),
  );
}

/// Last-resort failure surface: no Rust bridge, no ProviderScope, no oto
/// theme - just enough Material to tell the user startup failed instead of
/// showing a blank window.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'oto failed to start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
