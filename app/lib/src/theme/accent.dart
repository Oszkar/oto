import 'package:flutter/material.dart';

/// User-selectable accent hue. Default is [Accent.teal].
///
/// Each accent carries its resolved swatch for light and dark themes plus a
/// pre-blended "soft" variant (the same hue at low alpha) used for badges and
/// pills. Soft alphas: light `0.14` (`0x24`), dark `0.22` (`0x38`).
enum Accent {
  teal(Color(0xFF0F7A72), Color(0xFF5DD6C8), Color(0x240F7A72), Color(0x385DD6C8)),
  indigo(Color(0xFF3F4CB8), Color(0xFF8A96FF), Color(0x243F4CB8), Color(0x388A96FF)),
  amber(Color(0xFFA85A1A), Color(0xFFF0B070), Color(0x24A85A1A), Color(0x38F0B070)),
  slate(Color(0xFF3A4554), Color(0xFFA8B3C2), Color(0x243A4554), Color(0x38A8B3C2));

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
