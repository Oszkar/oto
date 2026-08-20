import 'package:flutter/material.dart';

import '../../theme/oto_colors.dart';

/// A thin, themed horizontal slider over the normalized range `0..1`.
///
/// Wraps a Material [Slider] in a [SliderTheme] that pulls its colors from
/// [OtoColors] (accent active track, [OtoColors.fillStrong] inactive track) and
/// gives it a thin track plus a small thumb. The visual track is slim, but the
/// control reserves a [_hitHeight]px-tall row and a 22px overlay radius so the
/// touch target clears the >=44px floor.
///
/// [onChanged] fires continuously during a drag; [onChangeEnd] fires once on
/// release. A null [onChanged] renders a non-interactive slider - the idiomatic
/// Material way to show a read-only or unknown value, rather than a draggable
/// no-op.
///
/// Non-interactive covers two different things, and [readOnly] tells them
/// apart, because they should not look alike:
///
///  - a read-only **indicator** ([readOnly] true, e.g. the Now Playing progress
///    bar), which keeps the accent tokens because there is no control to
///    disable in the first place; and
///  - a **control that is currently unavailable** ([readOnly] false, e.g. a
///    volume whose speaker is offline or whose value has not been reported),
///    which renders in muted tokens so it does not read as interactive.
///
/// Either way the colors come from [OtoColors]: Material's disabled slots
/// default to `colorScheme.onSurface` and would otherwise bypass the token
/// layer entirely.
class OtoSlider extends StatelessWidget {
  const OtoSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.readOnly = false,
  });

  /// Current value, clamped to `0..1` on build.
  final double value;

  /// Fires with the live value during a drag. When null, the slider is
  /// non-interactive; [readOnly] decides how that reads visually.
  final ValueChanged<double>? onChanged;

  /// Fires once with the final value when the drag is released.
  final ValueChanged<double>? onChangeEnd;

  /// True when this is a read-only indicator rather than an unavailable
  /// control. Only meaningful while [onChanged] is null.
  final bool readOnly;

  /// Thin visual track height.
  static const double _trackHeight = 4;

  /// Minimum tappable height - clears the 44px touch-target floor.
  static const double _hitHeight = 44;

  /// Overlay radius; half of [_hitHeight] so the hit-slop fills the row.
  static const double _overlayRadius = 22;

  /// Small thumb radius for a slim control.
  static const double _thumbRadius = 6;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return SizedBox(
      height: _hitHeight,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: _trackHeight,
          activeTrackColor: oto.accent,
          inactiveTrackColor: oto.fillStrong,
          thumbColor: oto.accent,
          // The disabled variants are separate SliderThemeData slots; leaving
          // them unset makes Material fill them from `colorScheme.onSurface`,
          // bypassing the token layer entirely.
          disabledActiveTrackColor: readOnly ? oto.accent : oto.inkFaint,
          disabledInactiveTrackColor: readOnly ? oto.fillStrong : oto.fill,
          disabledThumbColor: readOnly ? oto.accent : oto.inkFaint,
          overlayColor: oto.accent.withValues(alpha: 0.12),
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: _thumbRadius,
          ),
          overlayShape: const RoundSliderOverlayShape(
            overlayRadius: _overlayRadius,
          ),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: value.clamp(0, 1),
          min: 0,
          max: 1,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    );
  }
}
