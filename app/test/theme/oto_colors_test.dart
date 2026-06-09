// The first three tests are reproduced verbatim from the task spec, which uses
// `Color.opacity` and `as OtoColors` casts the analyzer now flags as
// deprecated/unnecessary. Suppressing file-wide keeps the spec block intact.
// ignore_for_file: deprecated_member_use, unnecessary_cast

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/oto_colors.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';

void main() {
  test('dark OtoColors uses true-dark surfaces and descending-alpha inks', () {
    final c = OtoColors.dark(Accent.teal);
    expect(c.bg, const Color(0xFF0E0E10));
    // inks are one base at descending alpha
    expect(c.ink.opacity, greaterThan(c.ink2.opacity));
    expect(c.ink2.opacity, greaterThan(c.inkMute.opacity));
    expect(c.inkMute.opacity, greaterThan(c.inkFaint.opacity));
  });

  test('lerp returns a same-type extension at t=0/1', () {
    final a = OtoColors.light(Accent.teal);
    final b = OtoColors.dark(Accent.teal);
    expect(a.lerp(b, 0), isA<OtoColors>());
    expect((a.lerp(b, 0) as OtoColors).bg, a.bg);
    expect((a.lerp(b, 1) as OtoColors).bg, b.bg);
  });

  test('otoTheme attaches OtoColors and applies accent', () {
    final t = otoTheme(Brightness.light, Accent.indigo);
    final oc = t.extension<OtoColors>()!;
    expect(oc.accent, Accent.indigo.light);
    expect(t.textTheme.bodyMedium!.fontFamily, 'Geist');
  });

  // --- Additional assertions (allowed by the task) ---

  test('lerp midpoint returns an OtoColors and is not identical to either end',
      () {
    final a = OtoColors.light(Accent.teal);
    final b = OtoColors.dark(Accent.teal);
    final mid = a.lerp(b, 0.5);
    expect(mid, isA<OtoColors>());
    // bg should be interpolated, not equal to either endpoint.
    expect((mid as OtoColors).bg, isNot(a.bg));
    expect(mid.bg, isNot(b.bg));
  });

  test('lerp against a non-OtoColors extension returns this', () {
    final a = OtoColors.light(Accent.teal);
    expect(a.lerp(null, 0.5), same(a));
  });

  test('accentSoft is wired from the accent swatch per brightness', () {
    final light = OtoColors.light(Accent.amber);
    final dark = OtoColors.dark(Accent.amber);
    expect(light.accent, Accent.amber.light);
    expect(light.accentSoft, Accent.amber.softLight);
    expect(dark.accent, Accent.amber.dark);
    expect(dark.accentSoft, Accent.amber.softDark);
  });

  test('copyWith overrides a single field and preserves the rest', () {
    final base = OtoColors.light(Accent.teal);
    const newBg = Color(0xFF123456);
    final copy = base.copyWith(bg: newBg);
    expect(copy.bg, newBg);
    expect(copy.surface, base.surface);
    expect(copy.accent, base.accent);
    expect(copy.inkFaint, base.inkFaint);
  });

  test('dark inks all derive from the same white base', () {
    final c = OtoColors.dark(Accent.teal);
    // Same RGB (white), only alpha differs.
    for (final ink in [c.ink, c.ink2, c.inkMute, c.inkFaint]) {
      expect(ink.r, 1.0);
      expect(ink.g, 1.0);
      expect(ink.b, 1.0);
    }
  });
}
