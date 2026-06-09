import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_screen.dart';

/// The shell's Home entry point. Renders the assembled [HomeScreen]; the shell
/// (`OtoApp`) points [MaterialApp.home] at this widget.
///
/// Kept a thin [ConsumerWidget] so the shell wiring stays stable; [HomeScreen]
/// owns the scaffold and all Home state.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const HomeScreen();
  }
}
