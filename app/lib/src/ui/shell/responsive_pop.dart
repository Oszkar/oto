import 'package:flutter/widgets.dart';
import '../../state/breakpoints.dart';

extension ResponsivePopExtension on BuildContext {
  /// Checks if the layout tier is wide, scheduling an automatic pop if so.
  /// Returns `true` if a pop was scheduled, indicating the widget should stop building.
  bool checkResponsivePop() {
    if (isWide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(this).maybePop();
        }
      });
      return true;
    }
    return false;
  }
}
