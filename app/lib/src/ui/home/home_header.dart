import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/breakpoints.dart';
import '../../state/household.dart';
import '../../state/model/household.dart';
import '../../state/prefs.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../settings/settings_section.dart';
import '../shell/nav.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_mark.dart';

/// The Home screen header: brand wordmark, "Speakers" title, a derived
/// `N rooms · M playing` subtitle, the Cards/Stack layout toggle, and a gear
/// that opens Settings. Ported from the design-system `V3HomeHeader` +
/// `V3LayoutToggle` (no search icon - omitted per the v0.6.0 spec).
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final text = Theme.of(context).textTheme;

    // Subtitle is derived from room/group state - the single source of truth, so
    // the count can never disagree with what the body renders.
    final roomCount = ref.watch(
      householdProvider.select((h) => h.rooms.length),
    );
    final playingCount = ref.watch(householdProvider.select(_activeGroupCount));
    final layout = ref.watch(currentHomeLayoutProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand row: mark + wordmark.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.screen18,
            Space.xs4,
            Space.screen18,
            0,
          ),
          child: Row(
            children: [
              const OtoMark(18),
              const SizedBox(width: Space.md8),
              Text('oto', style: TextStyles.label.copyWith(color: oto.ink2)),
            ],
          ),
        ),
        // Title row: "Speakers" + subtitle | layout toggle | gear.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.screen18,
            Space.sm6,
            Space.screen18,
            Space.card14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Speakers', style: text.headlineLarge),
                    const SizedBox(height: Space.xs4),
                    Text(
                      '$roomCount ${roomCount == 1 ? 'room' : 'rooms'} · '
                      '$playingCount playing',
                      style: TextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: oto.inkMute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.lg10),
              _LayoutToggle(
                value: layout,
                onChanged: (l) =>
                    ref.read(currentHomeLayoutProvider.notifier).setLayout(l),
              ),
              // On desktop the nav rail owns Settings, so the header gear would
              // be a second cogwheel - drop it there. Tablet (no rail) and phone
              // keep it as their only Settings entry point.
              if (!context.isDesktop) ...[
                const SizedBox(width: Space.lg10),
                _GearButton(onPressed: () => openSettings(context)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Count of distinct groups that are currently an active source (`hasActiveStream`).
int _activeGroupCount(Household h) =>
    h.groups.values.where((g) => g.hasActiveStream).length;

/// The Cards/Stack segmented toggle. Ported from `V3LayoutToggle`: a pill-shaped
/// [OtoColors.fillStrong] track holding two segments; the active one lifts to
/// [OtoColors.surface] with a card shadow.
class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.value, required this.onChanged});

  final HomeLayout value;
  final ValueChanged<HomeLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSegmentedControl<HomeLayout>(
      value: value,
      onChanged: onChanged,
      segmentWidth: 40,
      segmentHeight: 40,
      segments: const [
        SettingsSegment(
          key: Key('layout-toggle-cards'),
          value: HomeLayout.cards,
          semanticLabel: 'Cards layout',
          icon: 'layoutGrid',
        ),
        SettingsSegment(
          key: Key('layout-toggle-stack'),
          value: HomeLayout.stack,
          semanticLabel: 'Stack layout',
          icon: 'list',
        ),
      ],
    );
  }
}

/// The Settings gear - a bordered icon button, ported from `V3IconBtn`.
class _GearButton extends StatelessWidget {
  const _GearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Tooltip(
      message: 'Open settings',
      child: Semantics(
        label: 'Open settings',
        button: true,
        child: InkWell(
          key: const Key('header-settings'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radius_.art10),
          child: Container(
            width: Sizes.touchTarget44,
            height: Sizes.touchTarget44,
            decoration: BoxDecoration(
              border: Border.all(color: oto.line),
              borderRadius: BorderRadius.circular(Radius_.art10),
            ),
            alignment: Alignment.center,
            child: OtoIcon('settings', size: 17, color: oto.ink2),
          ),
        ),
      ),
    );
  }
}
