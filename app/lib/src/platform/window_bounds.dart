/// Persists the Windows/Linux/macOS window size and position across
/// launches via `window_manager`.
///
/// [initWindowBounds] restores the last saved bounds before the window is
/// shown (falling back to a centered default size on first run, and to a
/// centered *saved* size when the saved origin is no longer on any attached
/// display), then listens for resize/move and writes the live bounds back to
/// prefs. A no-op off desktop (Android/web never touch `window_manager`).
library;

import 'dart:io' show Platform;
import 'dart:math' show max;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _kBounds = 'window_bounds'; // "left,top,width,height"

/// Smallest window we will restore. A saved rect below this is treated as
/// corrupt rather than clamped: a near-zero window presents to the user as
/// "the app didn't launch", which is the failure this guard exists to prevent.
const _kMinSize = Size(640, 480);

/// Slab of window that must land inside [_displayEnvelope] for a restored
/// origin to be considered reachable - roughly a grabbable piece of title bar.
const _kMinVisible = Size(160, 48);

/// First-run size. Above the 1200 desktop breakpoint so a fresh install opens
/// in the three-pane layout, not the narrower tablet tier.
const _kDefaultSize = Size(1280, 800);

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

Rect? _rectFrom(String? s) {
  if (s == null) return null;
  final p = s.split(',').map(double.tryParse).toList();
  if (p.length != 4 || p.contains(null)) return null;
  if (p.any((v) => !v!.isFinite)) return null;
  return Rect.fromLTWH(p[0]!, p[1]!, p[2]!, p[3]!);
}

/// Conservative logical-pixel extent of the attached displays.
///
/// `PlatformDispatcher` exposes each display's physical size and DPR but NOT
/// its virtual-desktop offset, so the true multi-monitor rectangle is not
/// reachable without taking a direct `screen_retriever` dependency. Summing
/// the logical extents is deliberately an over-estimate: it bounds how far a
/// legitimate origin can sit from the primary display without ever rejecting
/// a position that is genuinely on-screen.
@visibleForTesting
Size displayEnvelope(Iterable<Display> displays) {
  var w = 0.0;
  var h = 0.0;
  for (final d in displays) {
    final dpr = d.devicePixelRatio > 0 ? d.devicePixelRatio : 1.0;
    w += d.size.width / dpr;
    h += d.size.height / dpr;
  }
  // No displays reported (headless / early startup): fall back to the default
  // size as the envelope so only absurd origins are rejected.
  return w > 0 && h > 0 ? Size(w, h) : _kDefaultSize;
}

/// The size to restore, or null to fall back to [_kDefaultSize].
///
/// Rejects degenerate/absent sizes outright; clamps an over-large one (a rect
/// saved on a since-removed larger monitor) down to the current envelope.
@visibleForTesting
Size? sanitizedSize(Size? saved, Size envelope) {
  if (saved == null) return null;
  if (saved.width < _kMinSize.width || saved.height < _kMinSize.height) {
    return null;
  }
  return Size(
    saved.width.clamp(_kMinSize.width, max(_kMinSize.width, envelope.width)),
    saved.height.clamp(
      _kMinSize.height,
      max(_kMinSize.height, envelope.height),
    ),
  );
}

/// The origin to restore, or null to centre instead.
///
/// A rect saved on a since-disconnected monitor reopens off-screen, so require
/// a [_kMinVisible] slab to fall inside the envelope. `top` may not be negative
/// (a title bar above the desktop is not grabbable); `left` may be, because a
/// monitor placed to the left of the primary yields legitimate negative x.
@visibleForTesting
Offset? sanitizedOrigin(Offset saved, Size size, Size envelope) {
  final leftOk =
      saved.dx >= -(size.width - _kMinVisible.width) &&
      saved.dx + _kMinVisible.width <= envelope.width;
  final topOk =
      saved.dy >= 0 && saved.dy + _kMinVisible.height <= envelope.height;
  return leftOk && topOk ? saved : null;
}

/// Restore the last window size + position on desktop startup, then persist
/// on resize/move. No-op off desktop (Android/web never call window_manager).
Future<void> initWindowBounds(SharedPreferences prefs) async {
  if (!_isDesktop) return;
  // Best-effort: window persistence is a UX nicety, never a launch blocker.
  // If a window_manager channel call fails, swallow it and let the platform
  // runner show the window at its default size (mirrors the graceful
  // degradation of android_multicast_lock).
  try {
    await windowManager.ensureInitialized();
    // Restored bounds are untrusted: the monitor they were saved on may be
    // gone, and a corrupt rect must not produce an invisible or zero-size
    // window. Size and origin are validated independently so a still-sane size
    // survives an unreachable origin.
    final saved = _rectFrom(prefs.getString(_kBounds));
    final envelope = displayEnvelope(PlatformDispatcher.instance.displays);
    final size = sanitizedSize(saved?.size, envelope);
    final origin = size == null
        ? null
        : sanitizedOrigin(saved!.topLeft, size, envelope);
    final opts = WindowOptions(
      size: size ?? _kDefaultSize,
      center: origin == null,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      if (origin != null) await windowManager.setPosition(origin);
      await windowManager.show();
    });
    windowManager.addListener(_BoundsPersister(prefs));
  } catch (_) {
    // A broken persist path must not prevent the app from starting.
  }
}

/// Writes the live window rect back to prefs on every resize/move. No
/// debounce - a straight write per event is fine for a desktop app.
class _BoundsPersister extends WindowListener {
  _BoundsPersister(this._prefs);
  final SharedPreferences _prefs;

  Future<void> _save() async {
    // These fire from unawaited listener callbacks, so a throw here would
    // become an unhandled future error - keep it self-contained + best-effort.
    try {
      final b = await windowManager.getBounds();
      await _prefs.setString(
        _kBounds,
        '${b.left},${b.top},${b.width},${b.height}',
      );
    } catch (_) {
      // A failed bounds write is inconsequential.
    }
  }

  @override
  void onWindowResized() => _save();

  @override
  void onWindowMoved() => _save();
}
