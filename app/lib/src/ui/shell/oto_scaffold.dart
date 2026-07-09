import 'package:flutter/material.dart';

import '../../state/breakpoints.dart';
import '../../theme/oto_colors.dart';

/// App scaffold. Compact (<840): the phone body. Wide (>=840) when a [detail]
/// pane is supplied: grid body + detail pane, plus a leading [rail] at desktop.
class OtoScaffold extends StatelessWidget {
  const OtoScaffold({super.key, required this.body, this.detail, this.rail});

  final Widget body;

  /// Wide-only detail pane (Now Playing). Null -> compact-only screen.
  final Widget? detail;

  /// Desktop-only leading nav rail. Ignored below the desktop breakpoint.
  final Widget? rail;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    // Key the branch off the SAME MediaQuery-derived tier the child widgets use
    // (context.isWide / layoutTier). Reading LayoutBuilder constraints here would
    // be a second source of truth that can diverge from the children when this
    // scaffold is embedded under a narrower parent - a compact shell whose body
    // already thinks it is wide (strip suppressed, no pane), or the reverse.
    final tier = context.layoutTier;
    if (tier == LayoutTier.compact || detail == null) {
      return Scaffold(
        backgroundColor: oto.bg,
        body: SafeArea(child: body),
      );
    }
    return Scaffold(
      backgroundColor: oto.bg,
      body: SafeArea(
        child: Row(
          children: [
            if (tier == LayoutTier.desktop && rail != null) ...[
              rail!,
              VerticalDivider(width: 1, thickness: 1, color: oto.line),
            ],
            Expanded(child: body),
            VerticalDivider(width: 1, thickness: 1, color: oto.line),
            SizedBox(
              width: tier == LayoutTier.desktop ? 340 : 320,
              child: detail!,
            ),
          ],
        ),
      ),
    );
  }
}
