import 'package:flutter/material.dart';

import '../../theme/oto_colors.dart';
import 'oto_icon.dart';

/// The leading dismiss control for an embeddable `*Body` header. Renders a
/// dismiss [IconButton] wired to [onDismiss] when non-null (route/dialog use),
/// or collapses to a [collapsedWidth] spacer when null (pane use, where there is
/// no dismiss affordance) so the header's centered content stays balanced.
class PaneDismiss extends StatelessWidget {
  const PaneDismiss({
    super.key,
    required this.onDismiss,
    required this.icon,
    this.iconSize = 18,
    this.buttonKey,
    this.collapsedWidth = 48,
  });

  final VoidCallback? onDismiss;
  final String icon;
  final double iconSize;
  final Key? buttonKey;
  final double collapsedWidth;

  @override
  Widget build(BuildContext context) {
    if (onDismiss == null) return SizedBox(width: collapsedWidth);
    return IconButton(
      key: buttonKey,
      onPressed: onDismiss,
      icon: OtoIcon(icon, size: iconSize, color: context.oto.ink2),
    );
  }
}
