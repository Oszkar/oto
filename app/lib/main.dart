import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oto/src/rust/frb_generated.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/ui/shell/oto_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
    ],
    child: const OtoApp(),
  ));
}
