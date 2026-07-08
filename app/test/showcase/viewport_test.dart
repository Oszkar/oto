/// Proves the showcase Phone/Tablet/Desktop toggle actually flips the layout
/// tier the previewed screen sees, by pinning `ShowcasePreview.viewport` and
/// capturing `context.layoutTier` from a probe entry.
library;

// `Viewport` here is the showcase's phone/tablet/desktop selector, not
// Flutter's scrolling `Viewport` widget - hide the latter to disambiguate.
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/showcase/entries.dart';
import 'package:oto/showcase/showcase_app.dart';
import 'package:oto/src/state/breakpoints.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';

void main() {
  LayoutTier? captured;

  final probe = Entry(
    section: 'Probe',
    name: 'Tier capture',
    household: const Household(),
    build: () => Builder(
      builder: (context) {
        captured = context.layoutTier;
        return const SizedBox.shrink();
      },
    ),
  );

  setUp(() => captured = null);

  Future<void> pumpAt(WidgetTester tester, Viewport viewport) async {
    await tester.pumpWidget(
      ShowcasePreview(
        entry: probe,
        brightness: Brightness.light,
        accent: Accent.teal,
        layout: HomeLayout.cards,
        viewport: viewport,
      ),
    );
    await tester.pump();
  }

  testWidgets('Viewport.desktop yields LayoutTier.desktop', (tester) async {
    await pumpAt(tester, Viewport.desktop);
    expect(captured, LayoutTier.desktop);
  });

  testWidgets('Viewport.phone yields LayoutTier.compact', (tester) async {
    await pumpAt(tester, Viewport.phone);
    expect(captured, LayoutTier.compact);
  });
}
