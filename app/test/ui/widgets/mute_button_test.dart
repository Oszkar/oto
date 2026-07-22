import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/theme/tokens.dart';
import 'package:oto/src/ui/widgets/mute_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: otoTheme(Brightness.light, Accent.teal),
  home: Scaffold(body: Center(child: child)),
);

MuteButton _button({
  required bool? muted,
  bool enabled = true,
  VoidCallback? onToggle,
}) => MuteButton(
  key: const Key('m'),
  muted: muted,
  enabled: enabled,
  size: 12,
  color: const Color(0xFF000000),
  label: 'Kitchen',
  onToggle: onToggle ?? () {},
);

void main() {
  testWidgets('unmuted: shows the volume glyph and toggles on tap', (t) async {
    var taps = 0;
    await t.pumpWidget(_host(_button(muted: false, onToggle: () => taps++)));

    expect(find.byTooltip('Mute Kitchen'), findsOneWidget);
    await t.tap(find.byKey(const Key('m')));
    expect(taps, 1);
  });

  testWidgets('muted: tooltip flips to unmute', (t) async {
    await t.pumpWidget(_host(_button(muted: true)));

    expect(find.byTooltip('Unmute Kitchen'), findsOneWidget);
  });

  testWidgets('null muted renders as unmuted', (t) async {
    await t.pumpWidget(_host(_button(muted: null)));

    expect(find.byTooltip('Mute Kitchen'), findsOneWidget);
  });

  testWidgets('disabled: no tap fires', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _host(_button(muted: false, enabled: false, onToggle: () => taps++)),
    );

    await t.tap(find.byKey(const Key('m')), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('keeps a 44px touch target around a 12px glyph', (t) async {
    await t.pumpWidget(_host(_button(muted: false)));

    final size = t.getSize(find.byKey(const Key('m')));
    expect(size.width, greaterThanOrEqualTo(Sizes.touchTarget44));
    expect(size.height, greaterThanOrEqualTo(Sizes.touchTarget44));
  });
}
