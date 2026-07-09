import 'dart:async';

/// Trailing throttle: at most one [run] action fires per [window]; a burst
/// collapses to the latest. [dispose] cancels any pending action without
/// firing it (drag-release fires its final value directly, so flushing here
/// would double-fire - see `commands.dart` `_ThrottledScalar.end`).
class Throttle {
  Throttle(this.window);
  final Duration window;
  Timer? _timer;
  void Function()? _pending;

  void run(void Function() action) {
    _pending = action;
    _timer ??= Timer(window, _fire);
  }

  void _fire() {
    final p = _pending;
    _pending = null;
    _timer = null;
    p?.call();
  }

  void dispose() => _timer?.cancel();
}
