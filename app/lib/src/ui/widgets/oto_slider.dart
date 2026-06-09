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
/// release.
class OtoSlider extends StatelessWidget {
  const OtoSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  /// Current value, clamped to `0..1` on build.
  final double value;

  /// Fires with the live value during a drag.
  final ValueChanged<double> onChanged;

  /// Fires once with the final value when the drag is released.
  final ValueChanged<double>? onChangeEnd;

  /// Thin visual track height.
  static const double _trackHeight = 4;

  /// Minimum tappable height — clears the 44px touch-target floor.
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
