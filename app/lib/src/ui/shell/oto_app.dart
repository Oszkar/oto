import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/prefs.dart';
import '../../theme/oto_theme.dart';
import 'home_page.dart';

/// Root app widget. Drives [MaterialApp]'s light/dark themes and [ThemeMode]
/// from [settingsProvider], so changing the accent or mode rebuilds the app.
class OtoApp extends ConsumerWidget {
  const OtoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'oto',
      debugShowCheckedModeBanner: false,
      theme: otoTheme(Brightness.light, settings.accent),
      darkTheme: otoTheme(Brightness.dark, settings.accent),
      themeMode: settings.mode,
      home: const HomePage(),
    );
  }
}
