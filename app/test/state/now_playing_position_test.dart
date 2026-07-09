// Notifier-level regression tests for the [NowPlayingPosition] re-anchor state
// machine - the novel, riskiest part of Now Playing (the pure `positionAt` and
// the static widget render are covered elsewhere).
//
// Wiring (mirrors `commands_test.dart`): the REAL `householdProvider` is driven
// off Rust via an overridden `discoveryProvider` (fake topology seed) plus an
// overridden `changeEventsProvider` (a controllable `StreamController`) - so the
// real household reducer folds the events we push. The wall clock is injected
// via `clockProvider` so transport transitions are evaluated against a fake,
// monotonic `fakeNow` we advance by hand. No real 500 ms timer is needed:
// rebuilds are driven by household mutations + the fake clock, fully
// deterministically.
//
// `positionApiProvider` is overridden with `_FakePositionApi` so SOAP reads
// return controllable position + duration values without touching Rust.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/now_playing.dart';

/// Two solo groups so we have an UNRELATED group (`G2`) to mutate without
/// touching `G1`'s track/transport (the spurious-re-anchor guard test).
const _topo = Topology(
  speakers: [
    DiscoveredSpeaker(
      id: 'LR',
      roomName: 'Living Room',
      model: 'Beam',
      ip: '1',
    ),
    DiscoveredSpeaker(id: 'KT', roomName: 'Kitchen', model: 'One SL', ip: '2'),
  ],
  groups: [
    DiscoveredGroup(id: 'G1', coordinator: 'LR', members: ['LR']),
    DiscoveredGroup(id: 'G2', coordinator: 'KT', members: ['KT']),
  ],
);

class _FakeDiscovery extends Discovery {
  @override
  Future<Topology> build() async => _topo;
}

/// Fake PositionApi that returns controllable position and duration values
/// without touching Rust. Defaults to position=0, duration=240s so track-change
/// tests (which expect ~0) still hold after the read reconciles.
class _FakePositionApi extends PositionApi {
  _FakePositionApi();
  int? nextPositionSecs = 0;
  int? nextDurationSecs = 240;

  @override
  Future<TrackPositionDto> trackPosition(String groupId) async =>
      TrackPositionDto(
        positionSecs: nextPositionSecs == null
            ? null
            : BigInt.from(nextPositionSecs!),
        durationSecs: nextDurationSecs == null
            ? null
            : BigInt.from(nextDurationSecs!),
      );
}

/// A controllable PositionApi whose every call returns a future backed by an
/// explicit [Completer], appended to [completers] in call order. Tests can
/// resolve completers manually to exercise out-of-order completion.
class _CompleterPositionApi extends PositionApi {
  _CompleterPositionApi(this.completers);
  final List<Completer<TrackPositionDto>> completers;

  @override
  Future<TrackPositionDto> trackPosition(String groupId) {
    final c = Completer<TrackPositionDto>();
    completers.add(c);
    return c.future;
  }
}

/// A handle over the wired-up container: push events, advance the clock, and
/// re-read the position. `events.add(...)` folds through the real reducer; we
/// pump microtasks so the `householdProvider` listener applies it before the
/// next position read re-runs `build` with the (possibly advanced) fake clock.
class _Harness {
  _Harness(this.container, this._events, this._setNow, this._watch, this.fake);
  final ProviderContainer container;
  final StreamController<ChangeEventDto> _events;
  final void Function(DateTime) _setNow;
  final String _watch;
  final _FakePositionApi fake;

  DateTime _now = DateTime(2026, 1, 1);

  /// Advance the fake wall-clock by [d].
  void advance(Duration d) {
    _now = _now.add(d);
    _setNow(_now);
  }

  /// Push an event through the real change-event stream and let the household
  /// listener fold it (microtask drain), then force the watched group's `build`
  /// to re-run AT THE CURRENT CLOCK. Reading eagerly after each step is what
  /// makes the state machine deterministic: each transport transition is
  /// evaluated against the `fakeNow` in effect when that event arrived (a
  /// deferred read would collapse several transitions into one rebuild and
  /// anchor against the wrong clock).
  ///
  /// Two drains: the first allows the household listener to fold the event and
  /// re-run `build`; the second drains the microtask queue so any `_readAnchor`
  /// `.then` callbacks (which run on microtasks) have also applied.
  Future<void> push(ChangeEventDto e) async {
    _events.add(e);
    await Future<void>.delayed(Duration.zero);
    container.read(nowPlayingPositionProvider(_watch));
    // Drain one more microtask turn so _readAnchor .then reconciliation lands.
    await Future<void>.delayed(Duration.zero);
    container.read(nowPlayingPositionProvider(_watch));
  }

  /// Current locally-derived position for [groupId] (re-runs `build`).
  Duration position(String groupId) =>
      container.read(nowPlayingPositionProvider(groupId)).position;
}

/// Build the harness: fake discovery seed + controllable event stream + a
/// mutable fake clock + a fake PositionApi. Keeps `G1`'s position provider
/// listened so it stays alive and rebuilds on every household change.
Future<_Harness> _harness({String watch = 'G1'}) async {
  final events = StreamController<ChangeEventDto>.broadcast();
  var fakeNow = DateTime(2026, 1, 1);
  final fake = _FakePositionApi();
  final container = ProviderContainer(
    overrides: [
      discoveryProvider.overrideWith(_FakeDiscovery.new),
      changeEventsProvider.overrideWith((ref) => events.stream),
      clockProvider.overrideWithValue(() => fakeNow),
      positionApiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(events.close);

  // Instantiate the household notifier (starts its listens) and resolve the
  // seed so the groups exist before we drive transitions.
  container.read(householdProvider);
  await container.read(discoveryProvider.future);

  // Keep the watched group's position alive across mutations so its `build`
  // re-runs (instance fields + anchor bookkeeping persist between rebuilds).
  container.listen(nowPlayingPositionProvider(watch), (_, _) {});

  // Drain the open-read microtask that fires during the first build.
  await Future<void>.delayed(Duration.zero);

  return _Harness(container, events, (n) => fakeNow = n, watch, fake);
}

const _trackA = ChangeEventDto.track(
  groupId: 'G1',
  track: TrackDto(id: 'a', title: 'Strobe'),
);
const _trackB = ChangeEventDto.track(
  groupId: 'G1',
  track: TrackDto(id: 'b', title: 'Ghosts n Stuff'),
);
const _play = ChangeEventDto.playback(
  groupId: 'G1',
  state: PlaybackStateDto.playing,
);
const _pause = ChangeEventDto.playback(
  groupId: 'G1',
  state: PlaybackStateDto.paused,
);

/// Within ~50 ms (well inside the assertions' second-scale tolerances).
Matcher _approx(Duration target) => predicate<Duration>(
  (p) => (p - target).abs() < const Duration(milliseconds: 50),
  'within 50ms of ${target.inMilliseconds}ms',
);

void main() {
  test('advances by wall-clock while playing', () async {
    final h = await _harness();
    await h.push(_trackA);
    await h.push(_play); // non-playing -> playing: anchors at fakeNow, pos 0.
    expect(h.position('G1'), _approx(Duration.zero));

    h.advance(const Duration(seconds: 5));
    // Re-run build via an UNRELATED mutation so the anchor is untouched but the
    // fake clock has moved: position should reflect +5s.
    await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 30));
    expect(h.position('G1'), _approx(const Duration(seconds: 5)));
  });

  test('track change resets to 0 (not the old advanced value)', () async {
    final h = await _harness();
    await h.push(_trackA);
    await h.push(_play);
    h.advance(const Duration(seconds: 7));
    await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 10));
    expect(
      h.position('G1'),
      _approx(const Duration(seconds: 7)),
      reason: 'sanity: advanced before the track change',
    );

    await h.push(_trackB); // distinct track key -> re-anchor at 0.
    expect(
      h.position('G1'),
      _approx(Duration.zero),
      reason: 'a new track restarts the position at 0, NOT the advanced 7s',
    );
  });

  test(
    'resume continues from the FROZEN position, not 0 (load-bearing)',
    () async {
      final h = await _harness();
      await h.push(_trackA);
      await h.push(_play);

      h.advance(const Duration(seconds: 10));
      await h.push(
        _pause,
      ); // playing -> paused: snapshot elapsed (~10s), freeze.
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 10)),
        reason: 'pause snapshots the elapsed position',
      );

      // Time passes while paused: the frozen position must NOT advance.
      h.advance(const Duration(seconds: 30));
      await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 1));
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 10)),
        reason: 'paused position is frozen - 30s of wall time does not move it',
      );

      // Resume: must re-anchor from the frozen ~10s, NOT snap to 0.
      // The SOAP read fires on resume; the fake reports 10s (matching the real
      // device which would report the actual playback position at this point).
      h.fake.nextPositionSecs = 10;
      await h.push(_play);
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 10)),
        reason: 'resume re-anchors from the frozen 10s, never 0',
      );

      // ...and continues upward from there.
      h.advance(const Duration(seconds: 2));
      await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 2));
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 12)),
        reason: 'after resume it advances: 10s frozen + 2s elapsed',
      );
    },
  );

  test(
    'a URI-only stream change re-anchors (uri participates in the key) - N6',
    () async {
      final h = await _harness();
      // Radio-stream tracks: no id, no title - only a distinct uri. These are
      // real content per Track.hasContent, so they must key the track.
      await h.push(
        const ChangeEventDto.track(
          groupId: 'G1',
          track: TrackDto(uri: 'x-rinconmp3radio://streamA'),
        ),
      );
      await h.push(_play);
      h.advance(const Duration(seconds: 9));
      await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 3));
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 9)),
        reason: 'sanity: advanced while the first stream played',
      );

      // A DIFFERENT uri-only stream is a new track -> restart at 0. Keying on
      // id/title alone (both null here) would miss this and keep advancing.
      await h.push(
        const ChangeEventDto.track(
          groupId: 'G1',
          track: TrackDto(uri: 'x-rinconmp3radio://streamB'),
        ),
      );
      expect(
        h.position('G1'),
        _approx(Duration.zero),
        reason: 'a distinct uri-only stream re-anchors at 0',
      );
    },
  );

  test(
    'an unrelated household change does NOT re-anchor (spurious guard)',
    () async {
      final h = await _harness();
      await h.push(_trackA);
      await h.push(_play);
      h.advance(const Duration(seconds: 8));
      await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 5));
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 8)),
        reason: 'sanity: advanced to ~8s while playing',
      );

      // A different room's volume event mutates the household (G1 build re-runs)
      // but touches neither G1's track nor its transport: position must hold.
      await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 6));
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 8)),
        reason: 'an unrelated change must NOT reset G1 to 0',
      );

      // ...and it keeps advancing normally afterwards.
      h.advance(const Duration(seconds: 2));
      await h.push(const ChangeEventDto.volume(speakerId: 'KT', volume: 7));
      expect(
        h.position('G1'),
        _approx(const Duration(seconds: 10)),
        reason: 'position continues advancing after the unrelated change',
      );
    },
  );

  // Bug 1 regression: a duration-less source (radio/line-in) must degrade to
  // null duration, never keep the previous track's total.
  test('track change to null-duration source clears duration (Bug 1)', () async {
    final h = await _harness();

    // First track has a real duration (240s from the default fake).
    h.fake.nextDurationSecs = 240;
    await h.push(_trackA);
    await h.push(_play);
    final durA = h.container.read(nowPlayingPositionProvider('G1')).duration;
    expect(
      durA,
      const Duration(seconds: 240),
      reason: 'sanity: first track has a 240s duration from the SOAP read',
    );

    // Second track returns null duration (radio/line-in).
    h.fake.nextDurationSecs = null;
    h.fake.nextPositionSecs = 0;
    await h.push(_trackB);
    final durB = h.container.read(nowPlayingPositionProvider('G1')).duration;
    expect(
      durB,
      isNull,
      reason:
          'a null-duration source must yield null, not carry the old 240s total',
    );
  });

  // Bug 2 regression: a stale _readAnchor completion (generation < current)
  // must be silently dropped; it must NOT overwrite the newer anchor/duration.
  //
  // Wiring: _CompleterPositionApi exposes Completers so we can control
  // completion order manually.
  //
  // Sequence:
  //   - open fires _readAnchor (generation 1). Track-A arrives first (this sets
  //     _seenTrack), then track-B arrives (_seenTrack true -> trackChanged ->
  //     generation 2 fires).
  //   - Complete gen-2 first with new-track values (pos=30, dur=180).
  //   - Complete gen-1 with stale values (pos=999, dur=999).
  //   - Assert the provider still reflects gen-2 values.
  test('stale async read is dropped by generation guard (Bug 2)', () async {
    final completers = <Completer<TrackPositionDto>>[];

    TrackPositionDto dto({required int? pos, required int? dur}) =>
        TrackPositionDto(
          positionSecs: pos == null ? null : BigInt.from(pos),
          durationSecs: dur == null ? null : BigInt.from(dur),
        );

    final events = StreamController<ChangeEventDto>.broadcast();
    var fakeNow = DateTime(2026, 1, 1);
    final container = ProviderContainer(
      overrides: [
        discoveryProvider.overrideWith(_FakeDiscovery.new),
        changeEventsProvider.overrideWith((ref) => events.stream),
        clockProvider.overrideWithValue(() => fakeNow),
        positionApiProvider.overrideWith(
          (ref) => _CompleterPositionApi(completers),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);

    container.read(householdProvider);
    await container.read(discoveryProvider.future);

    // Start listening: first build fires the open-read (generation 1).
    container.listen(nowPlayingPositionProvider('G1'), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(
      completers.length,
      1,
      reason: 'open-read fired exactly one _readAnchor call (gen 1)',
    );
    final gen1 = completers[0]; // do NOT complete yet

    // Push track-A: _seenTrack was false, so this is the initial population
    // (not a trackChanged), but it DOES set _seenTrack=true on this build run.
    // No new _readAnchor fires because opening=false, trackChanged=false,
    // resumedToPlaying=false here (track-only, no transport change to playing).
    events.add(_trackA);
    await Future<void>.delayed(Duration.zero);
    container.read(nowPlayingPositionProvider('G1'));
    await Future<void>.delayed(Duration.zero);
    // Still only 1 completer - no new read for the initial track-populate.
    expect(
      completers.length,
      1,
      reason: 'initial track populate does not fire an extra read',
    );

    // Push track-B: now _seenTrack=true and the key differs -> trackChanged=true
    // -> _readAnchor fires (generation 2).
    events.add(_trackB);
    await Future<void>.delayed(Duration.zero);
    container.read(nowPlayingPositionProvider('G1'));
    await Future<void>.delayed(Duration.zero);
    expect(
      completers.length,
      2,
      reason: 'track-change fired a second _readAnchor call (gen 2)',
    );
    final gen2 = completers[1];

    // Complete gen-2 FIRST with new-track values.
    gen2.complete(dto(pos: 30, dur: 180));
    await Future<void>.delayed(Duration.zero);
    container.read(nowPlayingPositionProvider('G1'));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(nowPlayingPositionProvider('G1')).duration,
      const Duration(seconds: 180),
      reason: 'gen-2 completion set duration to 180s',
    );

    // Now complete gen-1 with stale values - the generation guard must drop it.
    gen1.complete(dto(pos: 999, dur: 999));
    await Future<void>.delayed(Duration.zero);
    container.read(nowPlayingPositionProvider('G1'));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(nowPlayingPositionProvider('G1')).duration,
      const Duration(seconds: 180),
      reason: 'stale gen-1 completion is dropped; duration stays 180s not 999s',
    );
  });

  test('opening mid-track anchors from the read position, not 0', () async {
    // Set the fake to report a mid-track position BEFORE the harness builds
    // (the harness fires the open-read during the first listen, and the drain
    // in _harness() lets the .then land before we proceed here).
    final fake = _FakePositionApi()
      ..nextPositionSecs = 90
      ..nextDurationSecs = 240;
    final events = StreamController<ChangeEventDto>.broadcast();
    var fakeNow = DateTime(2026, 1, 1);
    final container = ProviderContainer(
      overrides: [
        discoveryProvider.overrideWith(_FakeDiscovery.new),
        changeEventsProvider.overrideWith((ref) => events.stream),
        clockProvider.overrideWithValue(() => fakeNow),
        positionApiProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);

    container.read(householdProvider);
    await container.read(discoveryProvider.future);

    // Start listening: this triggers the first build and the open-read.
    container.listen(nowPlayingPositionProvider('G1'), (_, _) {});
    // Drain microtasks so the _readAnchor .then reconciliation lands.
    await Future<void>.delayed(Duration.zero);

    // The open-read should have re-anchored at 90s (not 0).
    final pos = container.read(nowPlayingPositionProvider('G1')).position;
    expect(
      pos,
      _approx(const Duration(seconds: 90)),
      reason: 'opening mid-track anchors from the SOAP read position (90s)',
    );

    // Duration should also be set from the read.
    final dur = container.read(nowPlayingPositionProvider('G1')).duration;
    expect(
      dur,
      const Duration(seconds: 240),
      reason: 'duration is populated from the SOAP read',
    );
  });
}
