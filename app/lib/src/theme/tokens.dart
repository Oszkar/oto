import 'package:flutter/widgets.dart';

/// Design tokens: spacing, radius, the type scale, and elevation.
///
/// These mirror `docs/design-system/handoff/design-tokens.json`. Sizes are in
/// logical pixels (== Flutter logical px, 1:1). Type tracking from the JSON is
/// given in `em`; Flutter's `letterSpacing` is logical px, so each style here
/// pre-multiplies the em tracking by its font size.

/// Font families. Bundled TTFs (see `pubspec.yaml`); no system fallback.
abstract final class Fonts {
  static const String sans = 'Geist';
  static const String mono = 'GeistMono';
}

/// Named spacing steps. Use these rather than literals.
abstract final class Space {
  static const double xs4 = 4;
  static const double sm6 = 6;
  static const double md8 = 8;
  static const double lg10 = 10;
  static const double gutter12 = 12;
  static const double card14 = 14;
  static const double screen18 = 18;
  static const double section22 = 22;
}

/// Corner radii. Trailing underscore avoids clashing with Flutter's [Radius].
// ignore: camel_case_types
abstract final class Radius_ {
  static const double xs4 = 4;
  static const double sm6 = 6;
  static const double control7 = 7;
  static const double input9 = 9;
  static const double art10 = 10;
  static const double button12 = 12;
  static const double card16 = 16;

  /// Fully-round (pill) controls.
  static const double pill999 = 999;
}

/// The oto type scale, as ready-to-use [TextStyle]s on the Geist family.
///
/// Tracking is converted from `em` to logical px (`size * em`) because Flutter's
/// `letterSpacing` is in logical pixels. `height` is the JSON `lineHeight`.
abstract final class TextStyles {
  /// Now Playing title.
  static const TextStyle displayLg = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 34 * -0.025,
    height: 1.05,
  );

  /// Screen header — e.g. "Speakers".
  static const TextStyle titleScreen = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: 26 * -0.025,
    height: 1.05,
  );

  /// Section / room-detail title, empty-state heads.
  static const TextStyle titleSection = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 22 * -0.02,
  );

  /// Card / row / group title.
  static const TextStyle titleCard = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 14.5 * -0.005,
  );

  /// Default body.
  static const TextStyle body = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 14 * -0.005,
  );

  /// Empty-state copy, secondary body.
  static const TextStyle bodySm = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  /// Buttons, field labels, now-playing meta.
  static const TextStyle label = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  /// Row subtitle, status line.
  static const TextStyle caption = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
  );

  /// Pills, small meta.
  static const TextStyle micro = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
  );

  /// Section eyebrows — "GROUP VOLUME", "ROOM LEVELS". Render uppercase at the
  /// call site (`text.toUpperCase()`); the style only carries the tracking.
  static const TextStyle overline = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 10.5 * 0.06,
  );

  /// Group count badge.
  static const TextStyle badge = TextStyle(
    fontFamily: Fonts.sans,
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
  );
}

/// Drop shadows. Flat cards use a hairline border (see `OtoColors.line`), not a
/// shadow — `card` is the subtle lift; `float`/`floatLg` are for the floating
/// group bar / bottom strip.
abstract final class Elevation {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> float = [
    BoxShadow(
      color: Color(0x14000000), // rgba(0,0,0,0.08)
      offset: Offset(0, 6),
      blurRadius: 18,
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> floatLg = [
    BoxShadow(
      color: Color(0x1A000000), // rgba(0,0,0,0.10)
      offset: Offset(0, 8),
      blurRadius: 22,
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];
}
