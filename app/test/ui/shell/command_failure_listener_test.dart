import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/command_failures.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/shell/command_failure_listener.dart';

Future<ProviderContainer> _pump(WidgetTester t) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: const CommandFailureListener(
          child: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('nothing is shown until a failure is reported', (t) async {
    await _pump(t);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a reported failure shows a SnackBar', (t) async {
    final container = await _pump(t);

    container
        .read(commandFailuresProvider.notifier)
        .report('Could not reach Kitchen');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not reach Kitchen'), findsOneWidget);
  });

  testWidgets('a burst shows only the newest failure, never a queue', (
    t,
  ) async {
    final container = await _pump(t);
    final notifier = container.read(commandFailuresProvider.notifier);

    // Three, not two: with `hideCurrentSnackBar` the second would still be
    // mid-exit-animation when the third arrives, and the queue would surface.
    notifier.report('Could not reach Kitchen');
    await t.pump();
    notifier.report('Could not reach Office');
    await t.pump();
    notifier.report('Could not reach Patio');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Could not reach Patio'), findsOneWidget);
    expect(find.text('Could not reach Kitchen'), findsNothing);
    expect(find.text('Could not reach Office'), findsNothing);

    // And the earlier ones are gone for good, not waiting behind it. Settle
    // the ENTRANCE animation first: the auto-dismiss timer is only armed once
    // it completes, so advancing the clock before that leaves the bar up
    // forever (verified against a bare ScaffoldMessenger, not just here).
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the same message twice re-announces', (t) async {
    final container = await _pump(t);
    final notifier = container.read(commandFailuresProvider.notifier);

    notifier.report('Could not reach Kitchen');
    await t.pumpAndSettle(); // entrance completes -> dismiss timer armed
    await t.pump(const Duration(seconds: 5)); // let it time out
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    notifier.report('Could not reach Kitchen');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Could not reach Kitchen'),
      findsOneWidget,
      reason:
          'a repeat failure must re-notify - this is what the monotonic id on '
          'CommandFailure is for',
    );
  });
}
