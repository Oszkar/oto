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

/// Conservative logical-pixel bounds on where the desktop can reach.
///
/// `PlatformDispatcher` exposes each display's physical size and DPR but NOT
/// its virtual-desktop offset, so the true multi-monitor rectangle is not
/// reachable without taking a direct `screen_retriever` dependency. We bound it
/// by the two arrangements that actually occur - all displays in one **row**
/// (widths sum, height is the tallest) or one **column** (heights sum, width is
/// the widest) - and treat an origin as plausible if it fits either.
///
/// That never rejects a genuinely on-screen position, and is strictly tighter
/// than summing both axes, which would invent a bottom-right corner no display
/// covers: two side-by-side 1920x1080 monitors are a 3840x1080 desktop, not
/// 3840x2160. An L-shaped arrangement can still slip an off-screen origin
/// through, which is the residual this cannot close without real offsets.
///
/// TODO(v0.7): exact validation needs per-display offsets (`screen_retriever`);
/// folded into the hardening bucket rather than taken as a dependency here.
typedef DesktopBounds = ({Size row, Size column});

/// `Display.size` is physical; window_manager positions in logical pixels.
/// Split out so [desktopBounds] takes plain sizes - `Display` has no public
/// constructor, so it cannot be faked in a unit test.
Iterable<Size> _logicalSizes(Iterable<Display> displays) => displays.map((d) {
  final dpr = d.devicePixelRatio > 0 ? d.devicePixelRatio : 1.0;
  return Size(d.size.width / dpr, d.size.height / dpr);
});

@visibleForTesting
DesktopBounds desktopBounds(Iterable<Size> logicalSizes) {
  var sumW = 0.0, sumH = 0.0, maxW = 0.0, maxH = 0.0;
  for (final s in logicalSizes) {
    final w = s.width;
    final h = s.height;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) continue;
    sumW += w;
    sumH += h;
    maxW = max(maxW, w);
    maxH = max(maxH, h);
  }
  // No usable displays reported (headless / early startup): fall back to the
  // default size so only absurd origins are rejected.
  if (sumW <= 0 || sumH <= 0) {
    return (row: _kDefaultSize, column: _kDefaultSize);
  }
  return (row: Size(sumW, maxH), column: Size(maxW, sumH));
}

/// The widest and tallest a restored window may legitimately be: a window can
/// span monitors, so each axis is bounded by that axis's largest tiling.
Size _maxWindowSize(DesktopBounds b) =>
    Size(max(b.row.width, b.column.width), max(b.row.height, b.column.height));

/// The size to restore, or null to fall back to [_kDefaultSize].
///
/// Rejects degenerate/absent sizes outright; clamps an over-large one (a rect
/// saved on a since-removed larger monitor) down to what the displays can hold.
@visibleForTesting
Size? sanitizedSize(Size? saved, DesktopBounds bounds) {
  if (saved == null) return null;
  if (saved.width < _kMinSize.width || saved.height < _kMinSize.height) {
    return null;
  }
  final limit = _maxWindowSize(bounds);
  return Size(
    saved.width.clamp(_kMinSize.width, max(_kMinSize.width, limit.width)),
    saved.height.clamp(_kMinSize.height, max(_kMinSize.height, limit.height)),
  );
}

/// The origin to restore, or null to centre instead.
///
/// A rect saved on a since-disconnected monitor reopens off-screen, so require
/// a [_kMinVisible] slab to fall inside one of [DesktopBounds]' two tilings -
/// checked per tiling, so a wide x is not paired with a tall y unless a single
/// arrangement allows both. `top` may not be negative (a title bar above the
/// desktop is not grabbable); `left` may be, because a monitor placed to the
/// left of the primary yields legitimate negative x.
@visibleForTesting
Offset? sanitizedOrigin(Offset saved, Size size, DesktopBounds bounds) {
  bool fits(Size extent) =>
      saved.dx >= -(size.width - _kMinVisible.width) &&
      saved.dx + _kMinVisible.width <= extent.width &&
      saved.dy >= 0 &&
      saved.dy + _kMinVisible.height <= extent.height;
  return fits(bounds.row) || fits(bounds.column) ? saved : null;
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
    final bounds = desktopBounds(
      _logicalSizes(PlatformDispatcher.instance.displays),
    );
    final size = sanitizedSize(saved?.size, bounds);
    final origin = size == null
        ? null
        : sanitizedOrigin(saved!.topLeft, size, bounds);
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
