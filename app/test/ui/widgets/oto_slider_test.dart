import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_colors.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';

void main() {
  testWidgets('OtoSlider reports onChangeEnd after a drag', (t) async {
    double? ended;
    await t.pumpWidget(
      MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: Scaffold(
          body: Center(
            child: OtoSlider(
              value: 0.3,
              onChanged: (_) {},
              onChangeEnd: (v) => ended = v,
            ),
          ),
        ),
      ),
    );
    await t.drag(find.byType(OtoSlider), const Offset(50, 0));
    await t.pumpAndSettle();
    expect(ended, isNotNull);
  });

  testWidgets('OtoSlider fires onChanged during a drag', (t) async {
    double? changed;
    await t.pumpWidget(
      MaterialApp(
        theme: otoTheme(Brightness.dark, Accent.teal),
        home: Scaffold(
          body: Center(
            child: OtoSlider(value: 0.3, onChanged: (v) => changed = v),
          ),
        ),
      ),
    );
    await t.drag(find.byType(OtoSlider), const Offset(50, 0));
    await t.pumpAndSettle();
    expect(changed, isNotNull);
  });

  testWidgets('OtoSlider with null onChanged is disabled (non-interactive)', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: const Scaffold(
          body: Center(child: OtoSlider(value: 0.5, onChanged: null)),
        ),
      ),
    );
    // A null onChanged disables the underlying Material Slider - the idiomatic
    // non-interactive state, not a draggable no-op.
    final slider = t.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
  });

  // A read-only indicator (the Now Playing progress bar) and an unavailable
  // control (an offline room's volume) are both non-interactive, but must not
  // look alike - the indicator keeps the accent, the control reads as muted.
  // Both paths must come from the token layer: Material's disabled slots
  // default to `colorScheme.onSurface`.
  for (final (label, readOnly, activeMatches) in <(String, bool, bool)>[
    ('readOnly keeps the accent tokens', true, true),
    ('an unavailable control renders in muted tokens', false, false),
  ]) {
    testWidgets('OtoSlider $label', (t) async {
      final theme = otoTheme(Brightness.light, Accent.teal);
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: OtoSlider(value: 0.5, onChanged: null, readOnly: readOnly),
            ),
          ),
        ),
      );

      final oto = theme.extension<OtoColors>()!;
      final data = SliderTheme.of(t.element(find.byType(Slider)));
      expect(data.disabledActiveTrackColor == oto.accent, activeMatches);
      expect(data.disabledThumbColor == oto.accent, activeMatches);
      expect(
        data.disabledActiveTrackColor,
        isNot(theme.colorScheme.onSurface),
        reason: 'must come from the oto tokens, not Material defaults',
      );
    });
  }
}
