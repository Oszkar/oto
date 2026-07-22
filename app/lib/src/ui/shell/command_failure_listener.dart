import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/command_failures.dart';

/// Renders [child] and surfaces every reported command failure as a SnackBar.
///
/// Lives at the shell so one listener covers every screen; the alternative
/// (each screen wiring its own) would drop notices for whichever screen forgot.
///
/// A new failure REPLACES the visible one instead of queueing behind it: a dead
/// speaker can fail several throttled sends from one volume drag, and the user
/// should see the current state of the world rather than dismiss a backlog.
/// That means `removeCurrentSnackBar`, not `hideCurrentSnackBar` - hide runs
/// the bar's normal exit animation and the next bar only appears once it
/// finishes, so a burst would still play through every message in turn.
class CommandFailureListener extends ConsumerWidget {
  const CommandFailureListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<CommandFailure?>(commandFailuresProvider, (_, next) {
      if (next == null) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next.message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
    });
    return child;
  }
}
