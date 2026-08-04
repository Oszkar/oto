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

/// A single 1920x1080 logical display.
const _single = Size(1920, 1080);

/// Two side-by-side 1920x1080 displays, as [displayEnvelope] over-estimates
/// them (it sums both axes; see its doc comment).
const _dual = Size(3840, 2160);

void main() {
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
      // 3840x2160 saved, now only a 1920x1080 display is attached.
      expect(
        sanitizedSize(const Size(3840, 2160), _single),
        const Size(1920, 1080),
      );
    });

    test('does not clamp below the minimum even on a tiny envelope', () {
      expect(
        sanitizedSize(const Size(1280, 800), const Size(200, 100)),
        const Size(640, 480),
      );
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

    test('rejects an origin below the bottom of the envelope', () {
      expect(sanitizedOrigin(const Offset(100, 1080), size, _single), isNull);
    });

    test('rejects an x so negative that no grabbable slab remains', () {
      // Only 100px of a 1280px window would remain on-screen - below the
      // 160px minimum-visible slab.
      expect(sanitizedOrigin(const Offset(-1180, 40), size, _single), isNull);
    });
  });

  group('displayEnvelope', () {
    test('falls back to the default size when no displays are reported', () {
      expect(displayEnvelope(const <Display>[]), const Size(1280, 800));
    });
  });
}
