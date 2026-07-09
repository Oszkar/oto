/// Persists the Windows/Linux/macOS window size and position across
/// launches via `window_manager`.
///
/// [initWindowBounds] restores the last saved bounds before the window is
/// shown (falling back to a centered default size on first run), then
/// listens for resize/move and writes the live bounds back to prefs. A
/// no-op off desktop (Android/web never touch `window_manager`).
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const _kBounds = 'window_bounds'; // "left,top,width,height"

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

Rect? _rectFrom(String? s) {
  if (s == null) return null;
  final p = s.split(',').map(double.tryParse).toList();
  if (p.length != 4 || p.contains(null)) return null;
  return Rect.fromLTWH(p[0]!, p[1]!, p[2]!, p[3]!);
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
    final saved = _rectFrom(prefs.getString(_kBounds));
    final opts = WindowOptions(
      // First-run default lands above the 1200 desktop breakpoint so a fresh
      // install opens in the three-pane layout, not the narrower tablet tier.
      size: saved?.size ?? const Size(1280, 800),
      center: saved == null,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      if (saved != null) await windowManager.setPosition(saved.topLeft);
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
