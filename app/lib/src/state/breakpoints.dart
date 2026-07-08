import 'package:flutter/widgets.dart';

/// Width tiers for the responsive shell. Compact is today's phone layout;
/// tablet adds the master-detail pane; desktop adds the nav rail.
enum LayoutTier { compact, tablet, desktop }

/// Named width thresholds for the shell. `tabletMin` reuses the seam
/// `OtoScaffold` shipped in v0.6.0 (was `wideBreakpoint`).
abstract final class Breakpoints {
  static const double tabletMin = 840;
  static const double desktopMin = 1200;
}

/// Pure tier selection - unit-testable without a widget tree.
LayoutTier layoutTierForWidth(double width) {
  if (width >= Breakpoints.desktopMin) return LayoutTier.desktop;
  if (width >= Breakpoints.tabletMin) return LayoutTier.tablet;
  return LayoutTier.compact;
}

/// Read the current tier from context (keyed on the window size, not a local
/// constraint - so a pane's inner width never flips the tier).
extension LayoutTierX on BuildContext {
  LayoutTier get layoutTier =>
      layoutTierForWidth(MediaQuery.sizeOf(this).width);
  bool get isWide => layoutTier != LayoutTier.compact;
  bool get isDesktop => layoutTier == LayoutTier.desktop;
}
