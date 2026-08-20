/// Tests for the restored-window-bounds validation in `window_bounds.dart`.
///
/// Saved bounds are untrusted: the monitor a rect was saved on may be gone by
/// the next launch, and a corrupt prefs value must not produce an invisible or
/// zero-size window - both present to the user as "the app didn't launch".
/// Only the pure geometry helpers are covered here; `initWindowBounds` itself
/// needs `window_manager`'s platform channels.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/platform/window_bounds.dart';

/// One 1920x1080 display. Both tilings collapse to the same rectangle.
const _single = (row: Size(1920, 1080), column: Size(1920, 1080));

/// Two 1920x1080 displays. Side by side the desktop is 3840x1080; stacked it is
/// 1920x2160. `desktopBounds` cannot tell which, so it reports both - and the
/// origin check must never combine a wide x with a tall y across them.
const _dual = (row: Size(3840, 1080), column: Size(1920, 2160));

void main() {
  group('desktopBounds', () {
    test('reports both tilings for two equal displays', () {
      final b = desktopBounds(const [Size(1920, 1080), Size(1920, 1080)]);
      expect(b.row, const Size(3840, 1080));
      expect(b.column, const Size(1920, 2160));
    });

    test('does not invent a corner no display covers', () {
      final b = desktopBounds(const [Size(1920, 1080), Size(1920, 1080)]);
      expect(
        b.row.height,
        1080,
        reason: 'a row of monitors is no taller than the tallest one',
      );
      expect(
        b.column.width,
        1920,
        reason: 'a column of monitors is no wider than the widest one',
      );
    });

    test('falls back to the default size when no displays are reported', () {
      final b = desktopBounds(const <Size>[]);
      expect(b.row, const Size(1280, 800));
      expect(b.column, const Size(1280, 800));
    });

    test('skips a display with a degenerate size', () {
      final b = desktopBounds(const [Size(1920, 1080), Size.zero]);
      expect(b.row, const Size(1920, 1080));
    });
  });

  group('sanitizedSize', () {
    test('null saved size falls through to the caller default', () {
      expect(sanitizedSize(null, _single), isNull);
    });

    test('rejects a zero size', () {
      expect(sanitizedSize(Size.zero, _single), isNull);
    });

    test('rejects a degenerate size below the minimum', () {
      expect(sanitizedSize(const Size(1280, 3), _single), isNull);
      expect(sanitizedSize(const Size(4, 800), _single), isNull);
    });

    test('passes a normal saved size through unchanged', () {
      expect(
        sanitizedSize(const Size(1280, 800), _single),
        const Size(1280, 800),
      );
    });

    test('clamps a size saved on a since-removed larger monitor', () {
      expect(
        sanitizedSize(const Size(3840, 2160), _single),
        const Size(1920, 1080),
      );
    });

    test('allows a window spanning a row of monitors', () {
      // 3000px wide is legitimate across two side-by-side 1920s.
      expect(
        sanitizedSize(const Size(3000, 900), _dual),
        const Size(3000, 900),
      );
    });

    test('does not clamp below the minimum even on a tiny desktop', () {
      const tiny = (row: Size(200, 100), column: Size(200, 100));
      expect(sanitizedSize(const Size(1280, 800), tiny), const Size(640, 480));
    });
  });

  group('sanitizedOrigin', () {
    const size = Size(1280, 800);

    test('accepts an on-screen origin', () {
      expect(
        sanitizedOrigin(const Offset(100, 60), size, _single),
        const Offset(100, 60),
      );
    });

    test('accepts a negative x (monitor to the left of the primary)', () {
      expect(
        sanitizedOrigin(const Offset(-400, 40), size, _dual),
        const Offset(-400, 40),
      );
    });

    test('accepts an x on the second monitor of a row', () {
      expect(
        sanitizedOrigin(const Offset(2000, 40), size, _dual),
        const Offset(2000, 40),
      );
    });

    test('accepts a y on the second monitor of a column', () {
      expect(
        sanitizedOrigin(const Offset(100, 1500), size, _dual),
        const Offset(100, 1500),
      );
    });

    test('rejects a wide x paired with a tall y (no tiling covers both)', () {
      // The finding this guards: summing both axes would call 3840x2160 valid
      // desktop space, so (2000, 1500) would pass. Neither tiling allows it -
      // the row is only 1080 tall, the column only 1920 wide.
      expect(sanitizedOrigin(const Offset(2000, 1500), size, _dual), isNull);
    });

    test('rejects an origin on a since-disconnected monitor', () {
      // Saved at x=1920 on a second display; only the primary remains.
      expect(sanitizedOrigin(const Offset(1920, 100), size, _single), isNull);
    });

    test(
      'rejects a negative y (title bar above the desktop is ungrabbable)',
      () {
        expect(sanitizedOrigin(const Offset(100, -1), size, _single), isNull);
      },
    );

    test('rejects an origin below the bottom of the desktop', () {
      expect(sanitizedOrigin(const Offset(100, 1080), size, _single), isNull);
    });

    test('rejects an x so negative that no grabbable slab remains', () {
      // Only 100px of a 1280px window would remain on-screen - below the
      // 160px minimum-visible slab.
      expect(sanitizedOrigin(const Offset(-1180, 40), size, _single), isNull);
    });
  });
}
