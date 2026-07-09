// Body-renders tests for NowPlayingBody: the chrome-free content embedded
// by both NowPlayingScreen (phone) and, on wide layouts, the detail pane.
// Mirrors the harness in now_playing_test.dart (same `wrap()` fixture from
// `_fixtures.dart`), but pumps the body directly with no `OtoScaffold`
// ancestor to prove it is embeddable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';

import '../home/_fixtures.dart';

void main() {
  testWidgets(
    'onDismiss null renders with no OtoScaffold and no dismiss chevron',
    (t) async {
      final h = wrap(
        const NowPlayingBody(groupId: 'G_OF'),
        household: playingHousehold(),
      );
      await t.pumpWidget(h.widget);

      expect(find.text('Strobe'), findsOneWidget);
      expect(find.byKey(const Key('np-dismiss-G_OF')), findsNothing);
    },
  );

  testWidgets(
    'onDismiss non-null shows the dismiss chevron and invokes the callback',
    (t) async {
      var dismissed = false;
      final h = wrap(
        NowPlayingBody(groupId: 'G_OF', onDismiss: () => dismissed = true),
        household: playingHousehold(),
      );
      await t.pumpWidget(h.widget);

      expect(find.byKey(const Key('np-dismiss-G_OF')), findsOneWidget);
      await t.tap(find.byKey(const Key('np-dismiss-G_OF')));
      await t.pump();

      expect(dismissed, isTrue);
    },
  );
}
