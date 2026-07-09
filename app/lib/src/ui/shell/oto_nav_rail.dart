import 'package:flutter/material.dart';

import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../widgets/oto_icon.dart';
import 'nav.dart';

/// The desktop three-pane leading rail (56px). Home is the only surface, so it
/// is a non-interactive active indicator; the Settings button opens the
/// Settings dialog. Rendered by [OtoScaffold] only at the desktop tier.
class OtoNavRail extends StatelessWidget {
  const OtoNavRail({super.key});

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return SizedBox(
      width: 56,
      child: ColoredBox(
        color: oto.surface,
        child: Column(
          children: [
            const SizedBox(height: Space.gutter12),
            // Home destination: active indicator (accent-soft chip). Home is
            // the only surface today, so this is decorative, not a button.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: oto.accentSoft,
                borderRadius: BorderRadius.circular(Radius_.art10),
              ),
              alignment: Alignment.center,
              child: OtoIcon('home', size: 20, color: oto.accent),
            ),
            const Spacer(),
            IconButton(
              key: const Key('rail-settings'),
              tooltip: 'Open settings',
              onPressed: () => openSettings(context),
              icon: OtoIcon('settings', size: 20, color: oto.ink2),
            ),
            const SizedBox(height: Space.gutter12),
          ],
        ),
      ),
    );
  }
}
