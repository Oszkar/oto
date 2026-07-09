import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/group/group_editor_screen.dart';

import '../home/_fixtures.dart';

// ---------------------------------------------------------------------------
// Test-specific wrap helper: pushes GroupEditorScreen as a route over a
// dummy home page so that Navigator.maybePop() actually pops the route. The
// shared `wrap()` in _fixtures puts the widget as the home-route body, where
// maybePop() silently does nothing (nothing to pop to).
// ---------------------------------------------------------------------------

class EditorHandle {
  EditorHandle(this.widget, this._resolveGrouping);
  final Widget widget;
  final SpyGrouping? Function() _resolveGrouping;
  List<String> get groupingCalls => _resolveGrouping()?.calls ?? const [];
}

EditorHandle wrapEditor(String hostId, {required Household household}) {
  SpyGrouping? grouping;
  final widget = ProviderScope(
    overrides: [
      householdProvider.overrideWith(() => FixtureHousehold(household)),
      playbackControllerProvider.overrideWith((ref) => SpyPlayback(ref)),
      groupingControllerProvider.overrideWith(
        (ref) => grouping = SpyGrouping(ref),
      ),
      positionApiProvider.overrideWithValue(const StubPositionApi()),
    ],
    child: MaterialApp(
      theme: otoTheme(Brightness.light, Accent.teal),
      // Push the editor over a dummy home scaffold so maybePop works.
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-editor'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => GroupEditorScreen(hostId: hostId),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return EditorHandle(widget, () => grouping);
}

void main() {
  group('GroupEditorScreen', () {
    testWidgets('save joins newly-selected and leaves deselected', (t) async {
      final h = wrapEditor('LR', household: groupEditHousehold());
      await t.pumpWidget(h.widget);
      await t.tap(find.byKey(const Key('open-editor')));
      await t.pumpAndSettle();

      // BR starts unselected; tap its row to add it.
      await t.tap(find.byKey(const Key('group-row-BR')));
      // KT starts selected; tap its row to remove it.
      await t.tap(find.byKey(const Key('group-row-KT')));
      await t.pump();
      await t.tap(find.byKey(const Key('group-save')));
      await t.pumpAndSettle();
      expect(
        h.groupingCalls,
        containsAll(['joinGroup(BR,LR)', 'leaveGroup(KT)']),
      );
    });

    testWidgets(
      'conflict sub-line appears when selected room has active stream',
      (t) async {
        // groupEditWithConflictHousehold: BR is in G_BR which is playing.
        final h = wrapEditor('LR', household: groupEditWithConflictHousehold());
        await t.pumpWidget(h.widget);
        await t.tap(find.byKey(const Key('open-editor')));
        await t.pumpAndSettle();

        // BR is unselected initially, so no conflict yet.
        expect(find.text('Will stop current playback'), findsNothing);
        // Select BR - now it conflicts because G_BR has an active stream.
        await t.tap(find.byKey(const Key('group-row-BR')));
        await t.pump();
        expect(find.text('Will stop current playback'), findsOneWidget);
      },
    );

    testWidgets('ungroup-all leaves non-host members and does not leave host', (
      t,
    ) async {
      final h = wrapEditor('LR', household: groupEditHousehold());
      await t.pumpWidget(h.widget);
      await t.tap(find.byKey(const Key('open-editor')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('group-ungroup-all')));
      await t.pumpAndSettle();
      expect(find.text('Ungroup all rooms?'), findsOneWidget);

      await t.tap(find.byKey(const Key('group-confirm-ungroup-all')));
      await t.pumpAndSettle();
      // KT is a non-host member; should be left.
      expect(h.groupingCalls, contains('leaveGroup(KT)'));
      // Host LR must NOT be left.
      expect(h.groupingCalls, isNot(contains('leaveGroup(LR)')));
    });

    testWidgets('ungroup-all cancel issues no grouping calls', (t) async {
      final h = wrapEditor('LR', household: groupEditHousehold());
      await t.pumpWidget(h.widget);
      await t.tap(find.byKey(const Key('open-editor')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('group-ungroup-all')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('group-cancel-ungroup-all')));
      await t.pumpAndSettle();

      expect(find.byType(GroupEditorScreen), findsOneWidget);
      final joinLeave = h.groupingCalls
          .where((c) => c.startsWith('joinGroup') || c.startsWith('leaveGroup'))
          .toList();
      expect(joinLeave, isEmpty);
    });

    testWidgets(
      'save with no changes issues no grouping calls but still pops',
      (t) async {
        final h = wrapEditor('LR', household: groupEditHousehold());
        await t.pumpWidget(h.widget);
        await t.tap(find.byKey(const Key('open-editor')));
        await t.pumpAndSettle();
        expect(find.byType(GroupEditorScreen), findsOneWidget);

        // No selection changes - tap save immediately.
        await t.tap(find.byKey(const Key('group-save')));
        await t.pumpAndSettle();

        // Screen should be gone (popped back to home).
        expect(find.byType(GroupEditorScreen), findsNothing);
        // No join/leave calls issued.
        final joinLeave = h.groupingCalls
            .where(
              (c) => c.startsWith('joinGroup') || c.startsWith('leaveGroup'),
            )
            .toList();
        expect(joinLeave, isEmpty);
      },
    );

    testWidgets('tapping host row is a no-op (host stays selected)', (t) async {
      final h = wrapEditor('LR', household: groupEditHousehold());
      await t.pumpWidget(h.widget);
      await t.tap(find.byKey(const Key('open-editor')));
      await t.pumpAndSettle();

      // The host checkbox should be visible.
      expect(find.byKey(const Key('group-check-LR')), findsOneWidget);
      // Tap the host row - toggle is a no-op on the host.
      await t.tap(find.byKey(const Key('group-row-LR')));
      await t.pump();
      // HOST badge should still be visible.
      expect(find.text('HOST'), findsOneWidget);
      // Saving after a no-op host tap still produces no commands.
      await t.tap(find.byKey(const Key('group-save')));
      await t.pumpAndSettle();
      final joinLeave = h.groupingCalls
          .where((c) => c.startsWith('joinGroup') || c.startsWith('leaveGroup'))
          .toList();
      expect(joinLeave, isEmpty);
    });
  });
}
