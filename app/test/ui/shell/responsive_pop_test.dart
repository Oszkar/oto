// checkResponsivePop() auto-dismisses a phone-only route once the layout
// tier goes wide. It must not fire when something else (a confirmation
// sheet, a dialog) is on top of it - otherwise it dismisses that instead of
// the route it owns, and a further rebuild can cascade into popping the
// route beneath it too.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/ui/shell/responsive_pop.dart';

class _PopProbeScreen extends StatelessWidget {
  const _PopProbeScreen();

  @override
  Widget build(BuildContext context) {
    if (context.checkResponsivePop()) return const SizedBox.shrink();
    return const Text('probe-screen');
  }
}

void main() {
  Future<void> pumpWide(WidgetTester tester, {required Size size}) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('pops the probe screen when the tier goes wide', (tester) async {
    await pumpWide(tester, size: const Size(500, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _PopProbeScreen()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('probe-screen'), findsOneWidget);

    await pumpWide(tester, size: const Size(1200, 800));
    await tester.pumpAndSettle();

    expect(find.text('probe-screen'), findsNothing);
  });

  testWidgets('does not pop the probe screen while a sheet is on top of it', (
    tester,
  ) async {
    await pumpWide(tester, size: const Size(500, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _PopProbeScreen()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheetContext = tester.element(find.text('probe-screen'));
    unawaited(
      showModalBottomSheet<void>(
        context: sheetContext,
        builder: (_) => const SizedBox(height: 100, child: Text('sheet')),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    await pumpWide(tester, size: const Size(1200, 800));
    await tester.pumpAndSettle();

    // The sheet should still be up - checkResponsivePop must not have
    // dismissed it in place of the probe screen it actually owns. And the
    // probe screen's own route must still be on the stack (not popped
    // through to the 'open' button beneath it), i.e. no cascading pop.
    expect(find.text('sheet'), findsOneWidget);
    expect(find.text('open'), findsNothing);
  });
}
