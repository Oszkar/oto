import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../shell/oto_scaffold.dart';
import '../widgets/pane_dismiss.dart';
import 'about_section.dart';
import 'appearance_settings.dart';
import 'device_list.dart';

/// Embeddable Settings content. Chrome-free (no `OtoScaffold`): [SettingsScreen]
/// wraps this for the phone route, and on wide layouts the same body renders
/// inside a centered dialog. The header dismiss control is a [PaneDismiss]
/// driven by [onDismiss].
class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              PaneDismiss(
                onDismiss: onDismiss,
                icon: 'chevronLeft',
                tooltip: 'Back',
                iconSize: 20, // preserve the pre-split OtoIcon default size
                buttonKey: const Key('settings-back'),
              ),
              const SizedBox(width: Space.xs4),
              Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.screen18,
                0,
                Space.screen18,
                Space.section22,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppearanceSettings(),
                  SizedBox(height: Space.section22),
                  DeviceList(),
                  SizedBox(height: Space.section22),
                  AboutSection(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen Settings route (phone). On wide layouts the same content is
/// rendered by `SettingsBody` inside a centered dialog instead.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => OtoScaffold(
    body: SettingsBody(onDismiss: () => Navigator.of(context).maybePop()),
  );
}
