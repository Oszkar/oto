import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../shell/oto_scaffold.dart';
import '../widgets/oto_icon.dart';
import 'about_section.dart';
import 'appearance_settings.dart';
import 'device_list.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                  key: const Key('settings-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const OtoIcon('chevronLeft'),
                ),
                const SizedBox(width: Space.xs4),
                Text('Settings', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                Space.screen18,
                0,
                Space.screen18,
                Space.section22,
              ),
              child: Column(
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
        ],
      ),
    );
  }
}
