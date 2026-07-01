import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../widgets/oto_icon.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs4),
          child: Text(
            title,
            style: TextStyles.overline.copyWith(color: oto.inkMute),
          ),
        ),
        const SizedBox(height: Space.sm6),
        Container(
          decoration: BoxDecoration(
            color: oto.surface,
            border: Border.all(color: oto.line),
            borderRadius: BorderRadius.circular(Radius_.art10),
            boxShadow: Elevation.card,
          ),
          child: child,
        ),
      ],
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.last = false,
  });

  final String icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: oto.line)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter12,
        vertical: Space.lg10,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: oto.fill,
              borderRadius: BorderRadius.circular(Radius_.control7),
            ),
            alignment: Alignment.center,
            child: OtoIcon(icon, size: 16, color: oto.ink2),
          ),
          const SizedBox(width: Space.gutter12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyles.titleCard.copyWith(color: oto.ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xs4),
                  Text(
                    subtitle!,
                    style: TextStyles.caption.copyWith(color: oto.inkMute),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Space.gutter12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class SettingsSegment<T> {
  const SettingsSegment({
    required this.value,
    required this.key,
    this.label,
    this.icon,
  }) : assert(label != null || icon != null);

  final T value;
  final Key key;
  final String? label;
  final String? icon;
}

class SettingsSegmentedControl<T> extends StatelessWidget {
  const SettingsSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.segmentWidth,
    this.segmentMinWidth = 52,
    this.segmentHeight = 34,
  });

  final T value;
  final List<SettingsSegment<T>> segments;
  final ValueChanged<T> onChanged;
  final double? segmentWidth;
  final double segmentMinWidth;
  final double segmentHeight;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Container(
      padding: const EdgeInsets.all(Space.xs4),
      decoration: BoxDecoration(
        color: oto.fillStrong,
        borderRadius: BorderRadius.circular(Radius_.input9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments) ...[
            _SegmentButton<T>(
              key: segment.key,
              active: segment.value == value,
              segment: segment,
              onChanged: onChanged,
              width: segmentWidth,
              minWidth: segmentMinWidth,
              height: segmentHeight,
            ),
            if (segment != segments.last) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    super.key,
    required this.active,
    required this.segment,
    required this.onChanged,
    required this.width,
    required this.minWidth,
    required this.height,
  });

  final bool active;
  final SettingsSegment<T> segment;
  final ValueChanged<T> onChanged;
  final double? width;
  final double minWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Semantics(
      label: segment.label ?? segment.icon,
      button: true,
      selected: active,
      focusable: true,
      onTap: () => onChanged(segment.value),
      excludeSemantics: true,
      child: FocusableActionDetector(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onChanged(segment.value);
              return null;
            },
          ),
        },
        mouseCursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(segment.value),
          child: Container(
            width: width,
            height: height,
            constraints: width == null
                ? BoxConstraints(minWidth: minWidth)
                : null,
            padding: width == null
                ? const EdgeInsets.symmetric(horizontal: Space.lg10)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: active ? oto.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(Radius_.control7),
              boxShadow: active ? Elevation.card : null,
            ),
            alignment: Alignment.center,
            child: segment.icon == null
                ? Text(
                    segment.label!,
                    style: TextStyles.label.copyWith(
                      color: active ? oto.ink : oto.inkMute,
                    ),
                  )
                : OtoIcon(
                    segment.icon!,
                    size: 14,
                    color: active ? oto.ink : oto.inkMute,
                  ),
          ),
        ),
      ),
    );
  }
}
