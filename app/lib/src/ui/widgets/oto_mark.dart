import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The oto brand mark — the nested-rooms glyph.
///
/// Renders the bundled brand SVG, picking the black or white variant by the
/// current [Brightness]. The SVGs are a faithful render of the design-system
/// `OtoMark` component (nested rounded rects), so we use them directly rather
/// than redrawing in a [CustomPainter].
class OtoMark extends StatelessWidget {
  const OtoMark(this.size, {super.key});

  /// Side length in logical px.
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      'assets/brand/oto-mark-${dark ? 'white' : 'black'}.svg',
      width: size,
      height: size,
    );
  }
}
