/// Smoke test for the design-system showcase: pumps every catalogue entry in
/// both brightnesses and asserts it renders without throwing.
///
/// Crucially this test does NOT call `RustLib.init()`, so if any entry's screen
/// reaches for a real Rust FFI at render time it throws here - the guard that
/// keeps the showcase backend-free as screens evolve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/showcase/entries.dart';
import 'package:oto/showcase/showcase_app.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';

void main() {
  Future<void> pumpEntry(
    WidgetTester tester,
    Entry entry,
    Brightness brightness,
  ) async {
    // Phone-sized surface so phone-first layouts don't spuriously overflow.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ShowcasePreview(
        entry: entry,
        brightness: brightness,
        accent: Accent.teal,
        layout: HomeLayout.cards,
      ),
    );
    // A few discrete pumps to let the nested MaterialApp + providers settle,
    // without pumpAndSettle (which would hang on any periodic ticker).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.takeException(),
      isNull,
      reason: '${entry.section} / ${entry.name} (${brightness.name}) threw',
    );
    // Every screen puts up at least one Scaffold.
    expect(find.byType(Scaffold), findsWidgets);
  }

  testWidgets('catalogue is non-empty', (tester) async {
    expect(entries, isNotEmpty);
  });

  for (final entry in entries) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'renders ${entry.section} / ${entry.name} (${brightness.name})',
        (tester) => pumpEntry(tester, entry, brightness),
      );
    }
  }
}
