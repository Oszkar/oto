import 'package:flutter/material.dart';

import 'accent.dart';
import 'oto_colors.dart';
import 'tokens.dart';

/// Builds the oto [ThemeData] for the given [brightness] and [accent].
///
/// The accent seeds Material's [ColorScheme] via [ColorScheme.fromSeed]; the
/// bespoke roles ride along as an [OtoColors] [ThemeExtension]. Geist is the
/// default `fontFamily`, and the design type scale is mapped onto the standard
/// [TextTheme] slots so Material widgets inherit it.
ThemeData otoTheme(Brightness brightness, Accent accent) {
  final oc = brightness == Brightness.dark
      ? OtoColors.dark(accent)
      : OtoColors.light(accent);

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: Fonts.sans,
    scaffoldBackgroundColor: oc.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: oc.accent,
      brightness: brightness,
    ).copyWith(surface: oc.surface),
    textTheme: _textTheme(oc.ink),
  );

  return base.copyWith(extensions: [oc]);
}

/// Maps the oto type scale onto Material's [TextTheme] slots, colored with the
/// primary ink. Slots not in the design scale fall back to nearby tokens.
TextTheme _textTheme(Color ink) {
  TextStyle s(TextStyle t) => t.copyWith(color: ink);
  return TextTheme(
    displayLarge: s(TextStyles.displayLg),
    displayMedium: s(TextStyles.displayLg),
    displaySmall: s(TextStyles.titleScreen),
    headlineLarge: s(TextStyles.titleScreen),
    headlineMedium: s(TextStyles.titleSection),
    headlineSmall: s(TextStyles.titleSection),
    titleLarge: s(TextStyles.titleSection),
    titleMedium: s(TextStyles.titleCard),
    titleSmall: s(TextStyles.titleCard),
    bodyLarge: s(TextStyles.body),
    bodyMedium: s(TextStyles.body),
    bodySmall: s(TextStyles.bodySm),
    labelLarge: s(TextStyles.label),
    labelMedium: s(TextStyles.micro),
    labelSmall: s(TextStyles.caption),
  );
}
