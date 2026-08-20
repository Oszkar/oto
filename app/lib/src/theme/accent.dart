import 'package:flutter/material.dart';

/// User-selectable accent hue. Default is [Accent.teal].
///
/// Each accent carries its resolved swatch for light and dark themes plus a
/// pre-blended "soft" variant (the same hue at low alpha) used for badges and
/// pills. Soft alphas: light `0.14` (`0x24`), dark `0.22` (`0x38`).
///
/// The light swatches are constrained by their own soft variant: accent text
/// on `accentSoft` over `surface` (the group member-count badge, 12px/w700 -
/// small text, so WCAG AA wants 4.5:1) is the tightest pairing in the theme.
/// Teal and amber were tuned to clear it; indigo (5.8:1) and slate (7.7:1)
/// already did. Dark mode passes everywhere by a wide margin. Re-check this
/// ratio before changing any light swatch.
enum Accent {
  teal(
    // 4.79:1 on softLight-over-white (was #0F7A72 at 4.28:1 - below AA).
    Color(0xFF0E7168),
    Color(0xFF5DD6C8),
    Color(0x240E7168),
    Color(0x385DD6C8),
  ),
  indigo(
    Color(0xFF3F4CB8),
    Color(0xFF8A96FF),
    Color(0x243F4CB8),
    Color(0x388A96FF),
  ),
  amber(
    // 4.85:1 on softLight-over-white (was #A85A1A at 4.19:1 - below AA).
    Color(0xFF9A5015),
    Color(0xFFF0B070),
    Color(0x249A5015),
    Color(0x38F0B070),
  ),
  slate(
    Color(0xFF3A4554),
    Color(0xFFA8B3C2),
    Color(0x243A4554),
    Color(0x38A8B3C2),
  );

  const Accent(this.light, this.dark, this.softLight, this.softDark);

  /// Resolved swatch for the light theme.
  final Color light;

  /// Resolved swatch for the dark theme.
  final Color dark;

  /// Soft (low-alpha) variant for the light theme - badges, pills.
  final Color softLight;

  /// Soft (low-alpha) variant for the dark theme - badges, pills.
  final Color softDark;
}
