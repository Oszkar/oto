import 'package:flutter/material.dart';

import '../../theme/oto_colors.dart';

/// App scaffold with an adaptive seam. v0.6.0 always renders the compact
/// (phone) layout; v0.6.3 will branch a wide layout at [wideBreakpoint]
/// (tablet master-detail / desktop three-pane).
class OtoScaffold extends StatelessWidget {
  const OtoScaffold({super.key, required this.body});

  /// The compact (phone) body slot. The only layout in v0.6.0.
  final Widget body;

  /// Reserved for v0.6.3 (tablet master-detail / desktop three-pane). The
  /// [LayoutBuilder] seam below is a no-op until then.
  static const double wideBreakpoint = 840;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // TODO(v0.6.3): branch a wide layout here.
        // final wide = constraints.maxWidth >= wideBreakpoint;
        return Scaffold(
          backgroundColor: context.oto.bg,
          body: SafeArea(child: body),
        );
      },
    );
  }
}
