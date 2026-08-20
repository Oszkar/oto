/// The showcase shell: a left rail of entries, a toolbar of theme/layout
/// toggles, and a phone-framed live preview of the selected screen.
///
/// Each preview is a self-contained `ProviderScope` + nested `MaterialApp` with
/// fixture overrides, so screens render (and stay interactive, optimistically)
/// against hand-authored data with no Rust backend. Hot reload makes it a live
/// design board: edit a widget, save, see it here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api.dart' as rust_api;
import '../src/state/commands.dart';
import '../src/state/discovery.dart';
import '../src/state/events.dart';
import '../src/state/home_view_state.dart';
import '../src/state/household.dart';
import '../src/state/now_playing.dart';
import '../src/state/prefs.dart';
import '../src/theme/accent.dart';
import '../src/theme/oto_theme.dart';
import 'entries.dart';
import 'fixtures.dart';

enum Viewport { phone, tablet, desktop }

const _viewportSizes = <Viewport, Size>{
  Viewport.phone: Size(390, 844),
  Viewport.tablet: Size(1024, 768),
  Viewport.desktop: Size(1440, 900),
};

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key});

  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  Brightness _brightness = Brightness.light;
  Accent _accent = Accent.teal;
  HomeLayout _layout = HomeLayout.cards;
  Viewport _viewport = Viewport.phone;
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'oto showcase',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7168)),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _Rail(
                selected: _selected,
                onSelect: (i) => setState(() => _selected = i),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    _Toolbar(
                      brightness: _brightness,
                      accent: _accent,
                      layout: _layout,
                      viewport: _viewport,
                      onBrightness: (b) => setState(() => _brightness = b),
                      onAccent: (a) => setState(() => _accent = a),
                      onLayout: (l) => setState(() => _layout = l),
                      onViewport: (v) => setState(() => _viewport = v),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ColoredBox(
                        color: const Color(0xFF2A2A2E),
                        child: _PreviewFrame(
                          // Rebuild the whole preview (fresh fixtures) when any
                          // of these change - resetting optimistic state on a
                          // toggle is fine for a design board.
                          key: ValueKey(
                            '$_selected-$_brightness-$_accent-$_layout-$_viewport',
                          ),
                          entry: entries[_selected],
                          brightness: _brightness,
                          accent: _accent,
                          layout: _layout,
                          viewport: _viewport,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grouped entry list down the left edge.
class _Rail extends StatelessWidget {
  const _Rail({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? lastSection;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.section != lastSection) {
        lastSection = e.section;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              e.section.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        );
      }
      children.add(
        ListTile(
          dense: true,
          selected: i == selected,
          title: Text(e.name),
          onTap: () => onSelect(i),
        ),
      );
    }
    return SizedBox(
      width: 232,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'oto showcase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: ListView(children: children)),
        ],
      ),
    );
  }
}

/// Theme + layout toggles above the preview.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.brightness,
    required this.accent,
    required this.layout,
    required this.viewport,
    required this.onBrightness,
    required this.onAccent,
    required this.onLayout,
    required this.onViewport,
  });

  final Brightness brightness;
  final Accent accent;
  final HomeLayout layout;
  final Viewport viewport;
  final ValueChanged<Brightness> onBrightness;
  final ValueChanged<Accent> onAccent;
  final ValueChanged<HomeLayout> onLayout;
  final ValueChanged<Viewport> onViewport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<Brightness>(
            segments: const [
              ButtonSegment(value: Brightness.light, label: Text('Light')),
              ButtonSegment(value: Brightness.dark, label: Text('Dark')),
            ],
            selected: {brightness},
            onSelectionChanged: (s) => onBrightness(s.first),
          ),
          SegmentedButton<HomeLayout>(
            segments: const [
              ButtonSegment(value: HomeLayout.cards, label: Text('Cards')),
              ButtonSegment(value: HomeLayout.stack, label: Text('Stack')),
            ],
            selected: {layout},
            onSelectionChanged: (s) => onLayout(s.first),
          ),
          SegmentedButton<Viewport>(
            segments: const [
              ButtonSegment(value: Viewport.phone, label: Text('Phone')),
              ButtonSegment(value: Viewport.tablet, label: Text('Tablet')),
              ButtonSegment(value: Viewport.desktop, label: Text('Desktop')),
            ],
            selected: {viewport},
            onSelectionChanged: (s) => onViewport(s.first),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in Accent.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _AccentDot(
                    accent: a,
                    selected: a == accent,
                    onTap: () => onAccent(a),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final Accent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: accent.light,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}

/// A fixed phone-sized frame that scales to fit the available pane.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    super.key,
    required this.entry,
    required this.brightness,
    required this.accent,
    required this.layout,
    required this.viewport,
  });

  final Entry entry;
  final Brightness brightness;
  final Accent accent;
  final HomeLayout layout;
  final Viewport viewport;

  @override
  Widget build(BuildContext context) {
    final size = _viewportSizes[viewport]!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          child: Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: ShowcasePreview(
              entry: entry,
              brightness: brightness,
              accent: accent,
              layout: layout,
              viewport: viewport,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single previewed screen: fixture-seeded providers + a nested `MaterialApp`
/// whose theme is driven by the (overridden) settings, exactly like the real
/// `OtoApp`. Public so the smoke test can pump it directly.
class ShowcasePreview extends StatelessWidget {
  const ShowcasePreview({
    super.key,
    required this.entry,
    required this.brightness,
    required this.accent,
    required this.layout,
    this.viewport = Viewport.phone,
  });

  final Entry entry;
  final Brightness brightness;
  final Accent accent;
  final HomeLayout layout;
  final Viewport viewport;

  @override
  Widget build(BuildContext context) {
    final seed = (
      mode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      accent: accent,
      layout: layout,
    );
    final size = _viewportSizes[viewport]!;
    return ProviderScope(
      overrides: [
        householdProvider.overrideWith(() => FixtureHousehold(entry.household)),
        discoveryProvider.overrideWith(InertDiscovery.new),
        changeEventsProvider.overrideWith(
          (ref) => const Stream<rust_api.ChangeEventDto>.empty(),
        ),
        commandApiProvider.overrideWithValue(const InertCommandApi()),
        positionApiProvider.overrideWithValue(const InertPositionApi()),
        settingsProvider.overrideWith(() => SeededSettings(seed)),
        if (entry.homeState != null)
          homeViewStateProvider.overrideWithValue(entry.homeState!),
        if (entry.nowPlaying != null)
          nowPlayingPositionProvider(
            entry.nowPlaying!.groupId,
          ).overrideWithValue(entry.nowPlaying!.position),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final s = ref.watch(settingsProvider);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: otoTheme(Brightness.light, s.accent),
            darkTheme: otoTheme(Brightness.dark, s.accent),
            themeMode: s.mode,
            // Override the MediaQuery size below the MaterialApp so the
            // previewed screen sees the selected viewport, not the real
            // window - this is what makes the Phone/Tablet/Desktop toggle
            // actually flip `context.layoutTier`.
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size),
                child: entry.build(),
              ),
            ),
          );
        },
      ),
    );
  }
}
