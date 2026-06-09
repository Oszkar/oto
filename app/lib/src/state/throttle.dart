import 'dart:async';

/// Trailing throttle: at most one [run] action fires per [window]; a burst
/// collapses to the latest. [flush] fires the pending action now.
class Throttle {
  Throttle(this.window);
  final Duration window;
  Timer? _timer;
  void Function()? _pending;

  void run(void Function() action) {
    _pending = action;
    _timer ??= Timer(window, _fire);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    _fire();
  }

  void _fire() {
    final p = _pending;
    _pending = null;
    _timer = null;
    p?.call();
  }

  void dispose() => _timer?.cancel();
}
