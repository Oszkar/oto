import 'package:flutter/material.dart';
import '../../state/breakpoints.dart';

extension ResponsivePopExtension on BuildContext {
  /// Checks if the layout tier is wide, scheduling an automatic pop if so.
  /// Returns `true` if a pop was scheduled, indicating the widget should stop building.
  bool checkResponsivePop() {
    if (isWide) {
      final route = ModalRoute.of(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Re-check `isCurrent` at pop time, not schedule time: if a sheet or
        // dialog is now on top, or this route already popped from an earlier
        // callback, `route` is no longer current and popping would instead
        // dismiss whatever's on top (or cascade into the route below).
        if (mounted && (route?.isCurrent ?? false)) {
          Navigator.of(this).maybePop();
        }
      });
      return true;
    }
    return false;
  }

  /// Mirror of [checkResponsivePop] for a wide-only pane [Dialog]: if the
  /// layout tier goes narrow while it's open, dismiss the dialog and replace
  /// it with the full-screen phone route built by [openPhoneRoute]. Returns
  /// `true` if a swap was scheduled.
  bool checkResponsiveCollapse(WidgetBuilder openPhoneRoute) {
    if (!isWide) {
      final route = ModalRoute.of(this);
      final navigator = Navigator.of(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Same guard as checkResponsivePop: skip if something else (e.g. a
        // confirmation sheet) is now on top of this dialog's route.
        if (mounted && (route?.isCurrent ?? false)) {
          navigator.pop();
          navigator.push(MaterialPageRoute<void>(builder: openPhoneRoute));
        }
      });
      return true;
    }
    return false;
  }
}
