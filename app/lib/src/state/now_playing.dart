/// Locally-derived, read-only playback position for the Now Playing screen.
///
/// The backend deliberately does NOT event playback position (backend-true
/// core: see ARCHITECTURE / sonos-notes). So we derive the position bar from
/// the last transport anchor plus the wall clock: the pure [positionAt] is the
/// tested core, and [NowPlayingPosition] orchestrates the anchor bookkeeping +
/// a ~500 ms tick around it.
///
/// There is no seek/scrub and no backend position event - never claim one
/// exists. Anchors come only from observable transport transitions:
///   - a `Track` change re-anchors at [Duration.zero];
///   - a non-playing -> playing transition re-anchors from the FROZEN position
///     (NOT 0), so resume continues from where it paused.
///
/// Documented limitation: a mid-track JOIN (we start observing a group that is
/// already mid-track) shows the position from 0, because there is no backend
/// anchor for the elapsed time. It self-corrects on the next `Track` change.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'household.dart';
import 'model/group_state.dart';
import 'model/track.dart';

part 'now_playing.g.dart';

/// Pure position math. Returns [anchorPosition] when [state] is not
/// [PlaybackState.playing] (frozen); otherwise [anchorPosition] plus the
/// wall-clock elapsed since [anchorTime]. The result is clamped to
/// `>= Duration.zero`, and to `<= max` when a [max] (track duration) is given.
Duration positionAt(
  DateTime now, {
  required DateTime anchorTime,
  required Duration anchorPosition,
  required PlaybackState state,
  Duration? max,
}) {
  final raw = state == PlaybackState.playing
      ? anchorPosition + now.difference(anchorTime)
      : anchorPosition;
  var clamped = raw < Duration.zero ? Duration.zero : raw;
  if (max != null && clamped > max) clamped = max;
  return clamped;
}

/// Wall-clock source, injectable for deterministic tests. Defaults to the real
/// clock; only tests override it (production behavior is unchanged).
@riverpod
DateTime Function() clock(Ref ref) => DateTime.now;

/// A ticking, locally-derived playback position for one group, keyed by
/// `groupId`. Emits the current [Duration] position; recomputes via a ~500 ms
/// timer while playing and freezes otherwise.
///
/// Anchor bookkeeping lives on instance fields and is reconciled in [build]
/// (which re-runs whenever the watched group's `track`/`transport` changes):
///   - `Track` change -> anchor at [Duration.zero], `anchorTime = now`;
///   - non-playing -> playing (no track change) -> anchor at the FROZEN
///     position just computed (never 0), `anchorTime = now`.
@riverpod
class NowPlayingPosition extends _$NowPlayingPosition {
  /// ~500 ms tick: fine enough for a smooth bar, LAN-irrelevant (local only).
  static const _tick = Duration(milliseconds: 500);

  DateTime _anchorTime = DateTime.now();
  Duration _anchorPosition = Duration.zero;
  // Identity of the last-seen track, to detect a track change. Null until a
  // track is first seen; a transition between any two distinct keys re-anchors.
  String? _lastTrackKey;
  bool _seenTrack = false;
  PlaybackState? _lastTransport;
  Timer? _timer;

  /// A stable identity for a track across rebuilds: prefer `id`, fall back to
  /// `title`. Distinct tracks with neither are treated as the same (best-effort).
  static String? _trackKey(Track? t) => t == null ? null : (t.id ?? t.title);

  @override
  Duration build(String groupId) {
    // Watch the whole household and pick our group. `build` re-runs on any
    // household change; the anchor math below only reacts to this group's
    // track/transport, so an unrelated room's volume tick is a cheap no-op.
    final group = ref.watch(householdProvider).groups[groupId];
    final transport = group?.transport ?? PlaybackState.stopped;
    final duration = group?.track?.duration;
    final trackKey = _trackKey(group?.track);

    // Single wall-clock source, injectable for deterministic tests.
    final clock = ref.read(clockProvider);
    final now = clock();
    final trackChanged = _seenTrack && trackKey != _lastTrackKey;
    final leftPlaying =
        !trackChanged &&
        _lastTransport == PlaybackState.playing &&
        transport != PlaybackState.playing;
    final resumedToPlaying =
        !trackChanged &&
        _lastTransport != null &&
        _lastTransport != PlaybackState.playing &&
        transport == PlaybackState.playing;

    if (trackChanged) {
      // New track: restart from 0.
      _anchorPosition = Duration.zero;
      _anchorTime = now;
    } else if (leftPlaying) {
      // Pause/stop: snapshot the elapsed position so the frozen bar holds the
      // true current position (NOT the stale anchor it advanced from).
      _anchorPosition = positionAt(
        now,
        anchorTime: _anchorTime,
        anchorPosition: _anchorPosition,
        state: PlaybackState.playing,
        max: duration,
      );
      _anchorTime = now;
    } else if (resumedToPlaying) {
      // Resume: re-anchor from the FROZEN position just before resuming, NOT 0,
      // with anchorTime = now so it ticks forward from there.
      _anchorPosition = positionAt(
        now,
        anchorTime: _anchorTime,
        anchorPosition: _anchorPosition,
        // The pre-resume state is non-playing, so this returns the frozen value.
        state: _lastTransport!,
        max: duration,
      );
      _anchorTime = now;
    }

    _seenTrack = trackKey != null || _seenTrack;
    _lastTrackKey = trackKey;
    _lastTransport = transport;

    // (Re)build the ticker: run only while playing; freeze otherwise.
    _timer?.cancel();
    _timer = null;
    if (transport == PlaybackState.playing) {
      _timer = Timer.periodic(_tick, (_) {
        state = positionAt(
          clock(),
          anchorTime: _anchorTime,
          anchorPosition: _anchorPosition,
          state: PlaybackState.playing,
          max: duration,
        );
      });
    }
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    return positionAt(
      now,
      anchorTime: _anchorTime,
      anchorPosition: _anchorPosition,
      state: transport,
      max: duration,
    );
  }
}
