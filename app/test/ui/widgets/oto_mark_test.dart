import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/widgets/oto_mark.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: otoTheme(brightness, Accent.teal),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('OtoMark renders the brand mark at the given size', (t) async {
    await t.pumpWidget(_wrap(const OtoMark(28)));
    expect(find.byType(SvgPicture), findsOneWidget);
    final size = t.getSize(find.byType(OtoMark));
    expect(size.width, 28);
    expect(size.height, 28);
  });

  testWidgets('OtoMark renders in dark mode (white-asset branch)', (t) async {
    await t.pumpWidget(_wrap(const OtoMark(28), brightness: Brightness.dark));
    expect(find.byType(SvgPicture), findsOneWidget);
    final size = t.getSize(find.byType(OtoMark));
    expect(size.width, 28);
    expect(size.height, 28);
  });
}
