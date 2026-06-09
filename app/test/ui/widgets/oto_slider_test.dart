import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';

void main() {
  testWidgets('OtoSlider reports onChangeEnd after a drag', (t) async {
    double? ended;
    await t.pumpWidget(MaterialApp(
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
    ));
    await t.drag(find.byType(OtoSlider), const Offset(50, 0));
    await t.pumpAndSettle();
    expect(ended, isNotNull);
  });

  testWidgets('OtoSlider fires onChanged during a drag', (t) async {
    double? changed;
    await t.pumpWidget(MaterialApp(
      theme: otoTheme(Brightness.dark, Accent.teal),
      home: Scaffold(
        body: Center(
          child: OtoSlider(
            value: 0.3,
            onChanged: (v) => changed = v,
          ),
        ),
      ),
    ));
    await t.drag(find.byType(OtoSlider), const Offset(50, 0));
    await t.pumpAndSettle();
    expect(changed, isNotNull);
  });
}
