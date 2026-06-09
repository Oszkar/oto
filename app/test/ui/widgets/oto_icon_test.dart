import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/widgets/oto_icon.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: otoTheme(Brightness.light, Accent.teal),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('custom name renders an SvgPicture', (t) async {
    await t.pumpWidget(_wrap(const OtoIcon('soundbar')));
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('standard name renders a lucide Icon (not an SvgPicture)', (
    t,
  ) async {
    await t.pumpWidget(_wrap(const OtoIcon('play')));
    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });
}
