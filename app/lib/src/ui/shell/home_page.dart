import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/topology.dart';
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
    // Activate the dormant topology-follow side-effect controller for the app
    // lifetime (it's a keep-alive provider that does nothing until watched).
    // While Home is up, a `TopologyChanged` event debounces into a fast
    // re-pull, so a regroup refreshes the UI without a manual re-discover
    // (spec §1 / ARCHITECTURE). We ignore the return: the controller exposes
    // no state, it just needs to be kept alive.
    ref.watch(topologyControllerProvider);
    return const HomeScreen();
  }
}
