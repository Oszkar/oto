/// Locally-derived, read-only playback position for the Now Playing screen.
///
/// The backend deliberately does NOT event playback position (backend-true
/// core: see ARCHITECTURE / sonos-notes). So we derive the position bar from
/// the last transport anchor plus the wall clock: the pure [positionAt] is the
/// tested core, and [NowPlayingPosition] orchestrates the anchor bookkeeping +
/// a ~500 ms tick around it.
///
/// Anchors come from two sources:
///   1. Local transport transitions (track change re-anchors at Duration.zero;
///      pause snapshots the elapsed position; resume re-anchors from frozen).
///   2. A live SOAP read ([PositionApi.trackPosition]) fired on screen-open,
///      track-change, or resume-to-playing - this provides the real mid-track
///      position and the track duration (which is not carried by GENA events).
///
/// There is no seek/scrub and no backend position event - never claim one
/// exists.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../rust/api.dart' as rust_api;
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

/// What the Now Playing bar needs: the locally-ticking [position] and the
/// track [duration] (the bar's max), or null when unknown.
class NowPlayingProgress {
  final Duration position;
  final Duration? duration;
  const NowPlayingProgress(this.position, this.duration);

  @override
  bool operator ==(Object other) =>
      other is NowPlayingProgress &&
      position == other.position &&
      duration == other.duration;

  @override
  int get hashCode => Object.hash(position, duration);
}

/// Injectable indirection over the FRB `track_position` read, so tests can
/// override it without touching Rust (mirrors [CommandApi]).
class PositionApi {
  const PositionApi();
  Future<rust_api.TrackPositionDto> trackPosition(String groupId) =>
      rust_api.trackPosition(groupId: groupId);
}

@riverpod
PositionApi positionApi(Ref ref) => const PositionApi();

/// Wall-clock source, injectable for deterministic tests. Defaults to the real
/// clock; only tests override it (production behavior is unchanged).
@riverpod
DateTime Function() clock(Ref ref) => DateTime.now;

/// A ticking, locally-derived playback position for one group, keyed by
/// `groupId`. Emits a [NowPlayingProgress] with the current position and the
/// track duration (null when unknown); recomputes via a ~500 ms timer while
/// playing and freezes otherwise.
///
/// Anchor bookkeeping lives on instance fields and is reconciled in [build]
/// (which re-runs whenever the watched group's `track`/`transport` changes):
///   - `Track` change -> anchor at [Duration.zero] (optimistic), then a SOAP
///     read reconciles to the real position and sets the duration;
///   - non-playing -> playing (no track change) -> anchor at the FROZEN
///     position just computed (never 0), `anchorTime = now`, then SOAP read;
///   - first open -> SOAP read to supply the real mid-track position + duration.
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
  // Track duration from the last SOAP read; null until first read completes.
  Duration? _max;
  // Whether the first build has already fired the open-read.
  bool _opened = false;
  // Monotonic token: a newer _readAnchor invalidates older in-flight reads, so
  // a slow SOAP response for a previous track/transition can't clobber the
  // current anchor when it lands late.
  int _readGeneration = 0;

  /// A stable identity for a track across rebuilds: prefer `id`, then `uri`,
  /// then `title`. `uri` is included because a URI-only track (e.g. a radio
  /// stream with no id/title) is real content per [Track.hasContent] - keying
  /// on id/title alone would treat two distinct streams as the same track and
  /// miss the re-anchor. Distinct tracks with none of the three are treated as
  /// the same (best-effort).
  static String? _trackKey(Track? t) =>
      t == null ? null : (t.id ?? t.uri ?? t.title);

  @override
  NowPlayingProgress build(String groupId) {
    // Watch the whole household and pick our group. `build` re-runs on any
    // household change; the anchor math below only reacts to this group's
    // track/transport, so an unrelated room's volume tick is a cheap no-op.
    final group = ref.watch(householdProvider).groups[groupId];
    final transport = group?.transport ?? PlaybackState.stopped;
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
      _anchorPosition = Duration.zero; // optimistic; read reconciles below
      _anchorTime = now;
      _max = null; // new track: forget the old total until the read lands
    } else if (leftPlaying) {
      // Pause/stop: snapshot the elapsed position so the frozen bar holds the
      // true current position (NOT the stale anchor it advanced from).
      _anchorPosition = positionAt(
        now,
        anchorTime: _anchorTime,
        anchorPosition: _anchorPosition,
        state: PlaybackState.playing,
        max: _max,
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
        max: _max,
      );
      _anchorTime = now;
    }

    // Fire a SOAP read on the authoritative transitions: first open, a track
    // change, or a resume. Event-triggered, never a loop. The result re-anchors
    // (fixing a mid-track open/join showing 0) and sets _max (duration).
    // NOTE: on resumedToPlaying the read may apply a small position correction
    // if the device's reported position differs from the locally-frozen value -
    // this is by design, the device is authoritative.
    final opening = !_opened;
    _opened = true;
    if (opening || trackChanged || resumedToPlaying) {
      _readAnchor(groupId);
    }

    _seenTrack = trackKey != null || _seenTrack;
    _lastTrackKey = trackKey;
    _lastTransport = transport;

    // (Re)build the ticker: run only while playing; freeze otherwise.
    _timer?.cancel();
    _timer = null;
    if (transport == PlaybackState.playing) {
      _timer = Timer.periodic(_tick, (_) {
        state = NowPlayingProgress(
          positionAt(
            clock(),
            anchorTime: _anchorTime,
            anchorPosition: _anchorPosition,
            state: PlaybackState.playing,
            max: _max,
          ),
          _max,
        );
      });
    }
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    return NowPlayingProgress(
      positionAt(
        now,
        anchorTime: _anchorTime,
        anchorPosition: _anchorPosition,
        state: transport,
        max: _max,
      ),
      _max,
    );
  }

  /// Fire the SOAP read; on completion re-anchor from the device's reported
  /// position and set the track duration. Failures are swallowed (the bar keeps
  /// ticking off the last good anchor) - LAN reads are best-effort.
  void _readAnchor(String groupId) {
    final generation = ++_readGeneration;
    final clock = ref.read(clockProvider);
    ref
        .read(positionApiProvider)
        .trackPosition(groupId)
        .then((p) {
          // Guard: the provider may have been disposed before this async callback
          // fires (e.g. test teardown, navigation away). Setting state after
          // dispose throws in Riverpod. ref.mounted is false once disposed.
          if (!ref.mounted) return;
          if (generation != _readGeneration)
            return; // a newer read superseded this one
          final pos = p.positionSecs;
          final dur = p.durationSecs;
          _max = dur == null ? null : Duration(seconds: dur.toInt());
          if (pos != null) {
            _anchorPosition = Duration(seconds: pos.toInt());
            // NOTE: anchorTime is the read-RESPONSE time, not the request-issue
            // time - so there is a sub-tick (~half RTT, 10-50ms) systematic offset;
            // negligible at the 500ms tick resolution.
            _anchorTime = clock();
          }
          state = NowPlayingProgress(
            positionAt(
              clock(),
              anchorTime: _anchorTime,
              anchorPosition: _anchorPosition,
              state: _lastTransport ?? PlaybackState.stopped,
              max: _max,
            ),
            _max,
          );
        })
        .catchError((_) {});
  }
}
