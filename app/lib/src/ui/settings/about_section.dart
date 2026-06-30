import 'package:flutter/widgets.dart';

import '../../app_info.dart';
import 'settings_section.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSection(
      title: 'About',
      child: Column(
        children: [
          SettingsRow(
            icon: 'info',
            label: AppInfo.name,
            subtitle: AppInfo.description,
          ),
          SettingsRow(
            icon: 'tag',
            label: 'Version',
            subtitle: 'Version ${AppInfo.version}',
          ),
          SettingsRow(
            icon: 'wifi',
            label: 'Local network only',
            subtitle: 'Controls your own Sonos devices on your local network.',
          ),
          SettingsRow(
            icon: 'info',
            label: 'Not affiliated with Sonos',
            subtitle:
                'Sonos is referenced only for local device compatibility.',
            last: true,
          ),
        ],
      ),
    );
  }
}
