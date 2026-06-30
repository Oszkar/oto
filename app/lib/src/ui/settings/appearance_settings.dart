import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/prefs.dart';
import '../../theme/accent.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../widgets/oto_icon.dart';
import 'settings_section.dart';

class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSection(
      title: 'Appearance',
      child: Column(
        children: [
          SettingsRow(
            icon: 'moon',
            label: 'Theme',
            trailing: SettingsSegmentedControl<ThemeMode>(
              value: settings.mode,
              onChanged: notifier.setThemeMode,
              segments: const [
                SettingsSegment(
                  value: ThemeMode.system,
                  label: 'System',
                  key: Key('settings-theme-system'),
                ),
                SettingsSegment(
                  value: ThemeMode.light,
                  label: 'Light',
                  key: Key('settings-theme-light'),
                ),
                SettingsSegment(
                  value: ThemeMode.dark,
                  label: 'Dark',
                  key: Key('settings-theme-dark'),
                ),
              ],
            ),
          ),
          SettingsRow(
            icon: 'palette',
            label: 'Accent',
            trailing: AccentPicker(
              value: settings.accent,
              onChanged: notifier.setAccent,
            ),
          ),
          SettingsRow(
            icon: 'layoutGrid',
            label: 'Default home layout',
            trailing: SettingsSegmentedControl<HomeLayout>(
              value: settings.layout,
              onChanged: notifier.setHomeLayout,
              segments: const [
                SettingsSegment(
                  value: HomeLayout.cards,
                  label: 'Cards',
                  key: Key('settings-layout-cards'),
                ),
                SettingsSegment(
                  value: HomeLayout.stack,
                  label: 'Stack',
                  key: Key('settings-layout-stack'),
                ),
              ],
            ),
            last: true,
          ),
        ],
      ),
    );
  }
}

class AccentPicker extends StatelessWidget {
  const AccentPicker({super.key, required this.value, required this.onChanged});

  final Accent value;
  final ValueChanged<Accent> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final accent in Accent.values) ...[
          _AccentSwatch(
            key: Key('settings-accent-${accent.name}'),
            accent: accent,
            active: accent == value,
            onTap: () => onChanged(accent),
          ),
          if (accent != Accent.values.last) const SizedBox(width: Space.sm6),
        ],
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    super.key,
    required this.accent,
    required this.active,
    required this.onTap,
  });

  final Accent accent;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    final brightness = Theme.of(context).brightness;
    final color = brightness == Brightness.dark ? accent.dark : accent.light;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? oto.ink : oto.lineStrong,
            width: active ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: active
              ? OtoIcon('check', size: 13, color: oto.onAccent)
              : null,
        ),
      ),
    );
  }
}
