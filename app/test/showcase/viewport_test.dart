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
import 'package:oto/src/ui/group/group_editor_screen.dart';

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

  for (final wide in [false, true]) {
    testWidgets('room menu keeps preview scope and viewport (wide=$wide)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      // Include the gallery's outer Navigator: standalone previews cannot
      // detect a dialog escaping the fixture ProviderScope.
      await tester.pumpWidget(const ShowcaseApp());
      await tester.tap(find.text(wide ? 'Ready' : 'Room detail (solo)'));
      await tester.pumpAndSettle();
      if (wide) {
        await tester.tap(find.text('Desktop'));
        await tester.pumpAndSettle();
      }
      final room = wide ? 'RINCON_BR' : 'RINCON_OF';
      await tester.tap(find.byKey(Key('room-kebab-$room')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('room-kebab-group-$room')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(GroupEditorBody), findsOneWidget);
      expect(find.byType(Dialog), wide ? findsOneWidget : findsNothing);
      expect(
        find.byType(GroupEditorScreen),
        wide ? findsNothing : findsOneWidget,
      );
    });
  }
}
