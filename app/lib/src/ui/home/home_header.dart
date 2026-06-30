import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/household.dart';
import '../../state/model/household.dart';
import '../../state/prefs.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../settings/settings_screen.dart';
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
    final layout = ref.watch(settingsProvider.select((s) => s.layout));

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
                    ref.read(settingsProvider.notifier).setHomeLayout(l),
              ),
              const SizedBox(width: Space.lg10),
              _GearButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
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
    return Container(
      padding: const EdgeInsets.all(Space.xs4),
      decoration: BoxDecoration(
        color: context.oto.fillStrong,
        borderRadius: BorderRadius.circular(Radius_.input9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            key: const Key('layout-toggle-cards'),
            icon: 'layoutGrid',
            active: value == HomeLayout.cards,
            onTap: () => onChanged(HomeLayout.cards),
          ),
          const SizedBox(width: 2),
          _Segment(
            key: const Key('layout-toggle-stack'),
            icon: 'list',
            active: value == HomeLayout.stack,
            onTap: () => onChanged(HomeLayout.stack),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final bool active;
  final VoidCallback onTap;

  static const double _w = 40;
  static const double _h = 36;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: _w,
        height: _h,
        decoration: BoxDecoration(
          color: active ? oto.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(Radius_.control7),
          boxShadow: active ? Elevation.card : null,
        ),
        alignment: Alignment.center,
        child: OtoIcon(icon, size: 14, color: active ? oto.ink : oto.inkMute),
      ),
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
    return InkWell(
      key: const Key('header-settings'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(Radius_.art10),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: oto.line),
          borderRadius: BorderRadius.circular(Radius_.art10),
        ),
        alignment: Alignment.center,
        child: OtoIcon('settings', size: 17, color: oto.ink2),
      ),
    );
  }
}
