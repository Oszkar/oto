import 'package:flutter/material.dart';

import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/oto_scaffold.dart';
import '../widgets/oto_icon.dart';

/// Placeholder Settings screen. The real Settings UI lands in v0.6.2; for now
/// the Home header's gear pushes this so the route exists and is testable.
class SettingsStub extends StatelessWidget {
  const SettingsStub({super.key});

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return OtoScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg10,
              Space.md8,
              Space.screen18,
              Space.card14,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const OtoIcon('chevronDown'),
                ),
                const SizedBox(width: Space.xs4),
                Text('Settings', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              'Coming in v0.6.2',
              style: TextStyles.body.copyWith(color: oto.inkMute),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
