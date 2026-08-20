import 'package:flutter/material.dart';

import 'accent.dart';

/// The oto non-Material color roles, attached to [ThemeData] as a
/// [ThemeExtension]. Material's [ColorScheme] covers the seeded accent surfaces;
/// these are the bespoke roles the design system needs on top (the inks, fills,
/// hairlines, status colors, and the resolved accent pair).
///
/// The four inks (`ink`/`ink2`/`inkMute`/`inkFaint`) are derived from ONE base
/// color at descending alpha - white for dark, near-black for light - so text
/// hierarchy is a single hue at four opacities, not four hand-picked hexes.
///
/// Read it from a widget via the [OtoColorsX] extension: `context.oto.ink`.
@immutable
class OtoColors extends ThemeExtension<OtoColors> {
  const OtoColors({
    required this.bg,
    required this.surface,
    required this.elevated,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.ink2,
    required this.inkMute,
    required this.inkFaint,
    required this.fill,
    required this.fillStrong,
    required this.onAccent,
    required this.danger,
    required this.accent,
    required this.accentSoft,
  });

  /// App background.
  final Color bg;

  /// Card / sheet surface.
  final Color surface;

  /// Raised surface (one step forward - popovers, floating bars).
  final Color elevated;

  /// Hairline divider.
  final Color line;

  /// Emphasized border.
  final Color lineStrong;

  /// Primary text.
  final Color ink;

  /// Secondary text / icons.
  final Color ink2;

  /// Meta, captions (AA-passing).
  final Color inkMute;

  /// Decorative only - never use for load-bearing text. This is the lowest-alpha
  /// ink, below the AA contrast floor; reserve it for ornamental fills, faint
  /// separators, and disabled glyphs where legibility is not required.
  final Color inkFaint;

  /// Subtle button / track background.
  final Color fill;

  /// Pressed / active fill.
  final Color fillStrong;

  /// Text/icon color on top of [accent].
  final Color onAccent;

  /// Destructive (ungroup, clear, offline).
  final Color danger;

  /// Resolved accent swatch for the current brightness.
  final Color accent;

  /// Soft (low-alpha) accent - badges, pills.
  final Color accentSoft;

  /// Light-theme roles. Inks derive from a near-black base at descending alpha.
  factory OtoColors.light(Accent a) {
    const inkBase = Color(0xFF0F0F0F); // rgb(15,15,15)
    const fillBase = Color(0xFF141414); // rgb(20,20,20)
    return OtoColors(
      bg: const Color(0xFFF6F5F1),
      surface: const Color(0xFFFFFFFF),
      elevated: const Color(0xFFFFFFFF),
      line: fillBase.withValues(alpha: 0.07),
      lineStrong: fillBase.withValues(alpha: 0.16),
      ink: inkBase.withValues(alpha: 0.96),
      ink2: inkBase.withValues(alpha: 0.78),
      inkMute: inkBase.withValues(alpha: 0.58),
      inkFaint: inkBase.withValues(alpha: 0.46),
      fill: fillBase.withValues(alpha: 0.035),
      fillStrong: fillBase.withValues(alpha: 0.07),
      onAccent: const Color(0xFFFFFFFF),
      danger: const Color(0xFFB34A3A),
      accent: a.light,
      accentSoft: a.softLight,
    );
  }

  /// Dark-theme roles. Inks derive from a white base at descending alpha.
  factory OtoColors.dark(Accent a) {
    const inkBase = Color(0xFFFFFFFF); // rgb(255,255,255)
    const fillBase = Color(0xFFFFFFFF); // rgb(255,255,255)
    return OtoColors(
      bg: const Color(0xFF0E0E10),
      surface: const Color(0xFF16161A),
      elevated: const Color(0xFF22222A),
      line: fillBase.withValues(alpha: 0.07),
      lineStrong: fillBase.withValues(alpha: 0.14),
      ink: inkBase.withValues(alpha: 0.95),
      ink2: inkBase.withValues(alpha: 0.78),
      inkMute: inkBase.withValues(alpha: 0.62),
      inkFaint: inkBase.withValues(alpha: 0.46),
      fill: fillBase.withValues(alpha: 0.04),
      fillStrong: fillBase.withValues(alpha: 0.10),
      onAccent: const Color(0xFF0E0E10),
      danger: const Color(0xFFE08A7A),
      accent: a.dark,
      accentSoft: a.softDark,
    );
  }

  @override
  OtoColors copyWith({
    Color? bg,
    Color? surface,
    Color? elevated,
    Color? line,
    Color? lineStrong,
    Color? ink,
    Color? ink2,
    Color? inkMute,
    Color? inkFaint,
    Color? fill,
    Color? fillStrong,
    Color? onAccent,
    Color? danger,
    Color? accent,
    Color? accentSoft,
  }) {
    return OtoColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      elevated: elevated ?? this.elevated,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      inkMute: inkMute ?? this.inkMute,
      inkFaint: inkFaint ?? this.inkFaint,
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
    );
  }

  @override
  OtoColors lerp(ThemeExtension<OtoColors>? other, double t) {
    if (other is! OtoColors) return this;
    return OtoColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      inkMute: Color.lerp(inkMute, other.inkMute, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      fillStrong: Color.lerp(fillStrong, other.fillStrong, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }
}

/// Sugar for reading [OtoColors] from a [BuildContext]: `context.oto.ink`.
extension OtoColorsX on BuildContext {
  OtoColors get oto => Theme.of(this).extension<OtoColors>()!;
}
