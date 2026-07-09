import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_colors.dart';
import 'package:oto/src/ui/shell/oto_app.dart';

void main() {
  testWidgets('OtoApp applies themeMode + accent from settings', (t) async {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'dark',
      'accent': 'indigo',
    });
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        ],
        child: const OtoApp(),
      ),
    );
    // HomePage now renders HomeScreen; this test only reads MaterialApp theme
    // props via a single pump() (no discovery / FRB wired here, so we avoid
    // pumpAndSettle and just assert on MaterialApp's theme).
    await t.pump();

    final app = t.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme!.extension<OtoColors>()!.accent, Accent.indigo.dark);
  });
}
