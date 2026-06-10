import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/state/model/group_state.dart';

void main() {
  group('positionAt clamping', () {
    final t0 = DateTime(2026, 1, 1);
    test('clamps below zero to Duration.zero', () {
      final p = positionAt(
        t0,
        anchorTime: t0.add(const Duration(seconds: 5)),
        anchorPosition: Duration.zero,
        state: PlaybackState.playing,
      );
      // now is BEFORE the anchor, so raw is negative; clamp to zero.
      expect(p, Duration.zero);
    });
    test('clamps above max (track duration)', () {
      final p = positionAt(
        t0.add(const Duration(seconds: 500)),
        anchorTime: t0,
        anchorPosition: Duration.zero,
        state: PlaybackState.playing,
        max: const Duration(seconds: 100),
      );
      expect(p, const Duration(seconds: 100));
    });
    test('stopped is frozen at the anchor position', () {
      final p = positionAt(
        t0.add(const Duration(seconds: 9)),
        anchorTime: t0,
        anchorPosition: const Duration(seconds: 7),
        state: PlaybackState.stopped,
      );
      expect(p, const Duration(seconds: 7));
    });
  });

  final anchor = DateTime(2026, 1, 1, 0, 0, 0);
  test('position advances by wall-clock while playing', () {
    final p = positionAt(anchor.add(const Duration(seconds: 5)),
        anchorTime: anchor, anchorPosition: Duration.zero, state: PlaybackState.playing);
    expect(p, const Duration(seconds: 5));
  });
  test('position is frozen while paused', () {
    final p = positionAt(anchor.add(const Duration(seconds: 5)),
        anchorTime: anchor, anchorPosition: const Duration(seconds: 2), state: PlaybackState.paused);
    expect(p, const Duration(seconds: 2));
  });
  test('position advances from a non-zero anchor (resume case)', () {
    final p = positionAt(anchor.add(const Duration(seconds: 3)),
        anchorTime: anchor, anchorPosition: const Duration(seconds: 12), state: PlaybackState.playing);
    expect(p, const Duration(seconds: 15));
  });
}
