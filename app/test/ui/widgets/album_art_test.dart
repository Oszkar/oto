import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/widgets/album_art.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: otoTheme(Brightness.light, Accent.teal),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('AlbumArt(null) shows the placeholder, not an Image', (t) async {
    await t.pumpWidget(_wrap(const AlbumArt(null)));
    expect(find.byKey(const Key('album-art-placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
