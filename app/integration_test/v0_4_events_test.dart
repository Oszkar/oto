/// v0.4 end-to-end acceptance tests. Drives MockWire via
/// `dev_discover_mock` and asserts the full Dart->Rust->Dart event
/// loop works for every variant of `ChangeEventDto`. Covers Mute,
/// grouped Playback, the dev-seam SubscriptionError regression, and
/// the discover-replacement race fix (generation token).
///
/// Run on a connected Windows desktop:
///
/// ```text
/// cd app && flutter test integration_test/v0_4_events_test.dart -d windows
/// ```
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oto/src/rust/api.dart' as api;
import 'package:oto/src/rust/frb_generated.dart';

/// MockWire seed set: subscribe_speakers emits Volume + Mute (per speaker)
/// + Playback + GroupVolume + GroupMute (per group). For the 3-speaker /
/// 2-group fixture that's 3 + 3 + 2 + 2 + 2 = 12 events. Pinning the exact
/// count makes the seed-drain Completer trip when the seed surface grows
/// again (deliberate brittleness - a silent change to the seed shape should
/// fail this test).
///
/// Keep this in lockstep with `MockWire::subscribe_speakers`. It is not just
/// an assertion: `seedComplete` fires when this many events have arrived, so
/// a stale (too-low) value completes early and lets post-seed mutations race
/// a still-draining seed phase - an intermittent failure, not a clean one.
const int _expectedSeedCount = 3 + 3 + 2 + 2 + 2;

/// Subscribe to the unified stream and capture a (subscription,
/// events, seedComplete) triple. `seedComplete` fires after
/// [_expectedSeedCount] events have arrived; callers await it before
/// any post-seed mutations to avoid racing on a still-draining seed
/// phase. Replaces the `Future.delayed(Duration(milliseconds: 200))`
/// patterns the earlier tests used.
({
  StreamSubscription<api.ChangeEventDto> sub,
  List<api.ChangeEventDto> events,
  Completer<void> seedComplete,
})
_subscribeAndCollect() {
  final events = <api.ChangeEventDto>[];
  final seedComplete = Completer<void>();
  final sub = api.subscribeChangeEvents().listen((event) {
    events.add(event);
    if (events.length == _expectedSeedCount && !seedComplete.isCompleted) {
      seedComplete.complete();
    }
  });
  return (sub: sub, events: events, seedComplete: seedComplete);
}

/// Wait for `condition()` to become true, polling each microtask
/// (via `Future<void>.value()`). Bounded by `timeout`. Replaces the
/// `Future.delayed(Duration(milliseconds: 200))` "sleep and hope"
/// pattern: when the Rust side emits an event, the test resumes on
/// the very next microtask instead of waiting a fixed 200ms.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? message,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(message ?? 'condition never became true', timeout);
    }
    // Yield one microtask + one event-loop turn so the Rust→Dart
    // sink.add has a chance to push another event.
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  test(
    'v0.4 end-to-end: discover -> seed Volume -> mutation -> error',
    () async {
      // 1. Discover via MockWire. This auto-invokes subscribe_speakers.
      final topology = await api.devDiscoverMock();
      expect(topology.speakers.length, 3);

      // 2. Subscribe to the unified event stream.
      final h = _subscribeAndCollect();

      await h.seedComplete.future.timeout(const Duration(seconds: 5));

      // Seed shape: 3 Volume + 3 Mute + 2 Playback + 2 GroupVolume
      // + 2 GroupMute (see _expectedSeedCount).
      final volumeSeeds = h.events
          .whereType<api.ChangeEventDto_Volume>()
          .toList();
      final muteSeeds = h.events.whereType<api.ChangeEventDto_Mute>().toList();
      final playbackSeeds = h.events
          .whereType<api.ChangeEventDto_Playback>()
          .toList();
      expect(volumeSeeds, hasLength(3), reason: 'one Volume seed per speaker');
      expect(muteSeeds, hasLength(3), reason: 'one Mute seed per speaker');
      expect(
        playbackSeeds,
        hasLength(2),
        reason: 'one Playback seed per group',
      );
      for (final ev in muteSeeds) {
        expect(ev.muted, isFalse, reason: 'seed mute starts unmuted');
      }
      for (final ev in playbackSeeds) {
        expect(
          ev.state,
          api.PlaybackStateDto.stopped,
          reason: 'seed playback is Stopped',
        );
      }

      // 3. Mutation: set volume on Kitchen -> ChangeEventDto.Volume arrives.
      h.events.clear();
      await api.setVolume(speakerId: 'RINCON_KITCHEN', volume: 75);
      await _waitFor(
        () => h.events.isNotEmpty,
        message: 'no Volume event arrived after setVolume',
      );
      expect(h.events, hasLength(1));
      final volEv = h.events.first;
      expect(volEv, isA<api.ChangeEventDto_Volume>());
      volEv as api.ChangeEventDto_Volume;
      expect(volEv.speakerId, 'RINCON_KITCHEN');
      expect(volEv.volume, 75);

      // 4. Adversarial: a SubscriptionError pushed onto the held MockWire
      //    surfaces in Dart unchanged. Regression test for the cfg-gated
      //    dev_push_subscription_error_on_mock seam.
      h.events.clear();
      await api.devPushSubscriptionErrorOnMock(
        speakerId: 'RINCON_GHOST',
        message: 'synthesized for integration test',
      );
      await _waitFor(
        () => h.events.isNotEmpty,
        message: 'no SubscriptionError event arrived after devPush',
      );
      expect(h.events, hasLength(1));
      final errEv = h.events.first;
      expect(errEv, isA<api.ChangeEventDto_SubscriptionError>());
      errEv as api.ChangeEventDto_SubscriptionError;
      expect(errEv.speakerId, 'RINCON_GHOST');
      expect(errEv.message, 'synthesized for integration test');

      // Don't `await sub.cancel()`: it waits for the Rust loop's next
      // `sink.add(...)` to fail before returning, but the loop is now
      // blocked in `rx.recv()` waiting for the next event (we have no
      // more events to push). Fire-and-forget cancel; the Rust loop
      // will tear down naturally when the cdylib unloads at process
      // exit, or on the next `discover()` (Sender drop -> recv Err).
      unawaited(h.sub.cancel());
    },
  );

  test('v0.4: set_mute auto-emits ChangeEventDto.Mute', () async {
    // Office is the solo-group fixture speaker; muting it is the
    // simplest single-speaker case.
    await api.devDiscoverMock();
    final h = _subscribeAndCollect();
    await h.seedComplete.future.timeout(const Duration(seconds: 5));
    h.events.clear();

    await api.setMute(speakerId: 'RINCON_OFFICE', muted: true);
    await _waitFor(
      () => h.events.isNotEmpty,
      message: 'no Mute event arrived after setMute',
    );

    expect(h.events, hasLength(1));
    final ev = h.events.first;
    expect(ev, isA<api.ChangeEventDto_Mute>());
    ev as api.ChangeEventDto_Mute;
    expect(ev.speakerId, 'RINCON_OFFICE');
    expect(ev.muted, isTrue);

    unawaited(h.sub.cancel());
  });

  test(
    'v0.5: TopologyChanged is delivered end-to-end over the FRB stream',
    () async {
      // The FRB `subscribe_change_events` stream-loop has no Rust-level CI
      // test (it blocks on recv()); this integration test is the only
      // automated coverage that the loop forwards a variant to Dart. v0.5
      // adds the payload-less TopologyChanged variant - assert it crosses
      // the bridge unchanged, driven by the dev seam (debug-only).
      await api.devDiscoverMock();
      final h = _subscribeAndCollect();
      await h.seedComplete.future.timeout(const Duration(seconds: 5));
      h.events.clear();

      await api.devPushTopologyChangeOnMock();
      await _waitFor(
        () => h.events.isNotEmpty,
        message:
            'no TopologyChanged event arrived after devPushTopologyChangeOnMock',
      );

      expect(h.events, hasLength(1));
      expect(
        h.events.first,
        isA<api.ChangeEventDto_TopologyChanged>(),
        reason:
            'the payload-less TopologyChanged variant must cross the FRB stream',
      );

      unawaited(h.sub.cancel());
    },
  );

  test('v0.4: play(group) emits per-GROUP ChangeEventDto.Playback', () async {
    // Kitchen group is the multi-speaker fixture group (Kitchen +
    // Dining). The acceptance bar: the Playback event carries the
    // GROUP id (RINCON_KITCHEN:1), NOT a speaker id. A regression
    // that addressed Playback per-speaker would fail this assertion.
    await api.devDiscoverMock();
    final h = _subscribeAndCollect();
    await h.seedComplete.future.timeout(const Duration(seconds: 5));
    h.events.clear();

    const groupId = 'RINCON_KITCHEN:1';
    await api.play(groupId: groupId);
    await _waitFor(
      () => h.events.isNotEmpty,
      message: 'no Playback event arrived after play',
    );

    expect(h.events, hasLength(1));
    final ev = h.events.first;
    expect(ev, isA<api.ChangeEventDto_Playback>());
    ev as api.ChangeEventDto_Playback;
    expect(ev.groupId, groupId, reason: 'Playback addresses are per-GROUP');
    expect(ev.state, api.PlaybackStateDto.playing);

    unawaited(h.sub.cancel());
  });

  test(
    'v0.4: rediscovery - OLD stream completes cleanly and NEW stream emits fresh seed shape',
    () async {
      // This verifies the *stream lifecycle* across a discover_with-
      // induced wire swap. It does NOT directly verify the generation-
      // token's no-op behavior in `apply_event_at_generation` - that
      // invariant is exercised by the Rust unit test
      // `stale_consumer_loop_does_not_pollute_after_bump_and_clear` in
      // `state_manager.rs`. Here we check the surrounding Dart/FRB
      // plumbing the Rust fix relies on:
      //
      //   1. First discover  → subscribe → drain seeds.
      //   2. setVolume on Kitchen → assert event arrives on OLD stream.
      //   3. Second discover. The OLD wire's Sender is dropped by
      //      slot replacement; the OLD `subscribe_change_events` loop
      //      sees recv Err and returns; the Dart subscription on the
      //      OLD stream completes (onDone fires).
      //   4. NEW subscribe → drain NEW seeds. Seed shape must match
      //      the fresh deterministic fixture - Kitchen volume = 30
      //      (SEED_VOLUME), NOT the 88 we wrote on the OLD wire.
      //      The state-manager cache check happens in the Rust unit
      //      test above; this Dart test pins that the mock instance
      //      *itself* is freshly constructed on the second discover
      //      (a leaked Arc<MockWire> would surface here as a stale
      //      seed value).

      await api.devDiscoverMock();
      final h1 = _subscribeAndCollect();
      await h1.seedComplete.future.timeout(const Duration(seconds: 5));

      // Track whether the OLD stream completes. After the second
      // discover() replaces the wire, the OLD stream's underlying
      // mpsc Receiver sees its Sender drop, the Rust loop returns,
      // and Dart fires onDone on the OLD stream.
      var oldStreamDone = false;
      h1.sub.onDone(() => oldStreamDone = true);

      // A normal mutation on the OLD wire - proves the OLD stream is
      // alive right before re-discovery.
      h1.events.clear();
      await api.setVolume(speakerId: 'RINCON_KITCHEN', volume: 88);
      await _waitFor(
        () => h1.events.isNotEmpty,
        message: 'OLD stream missed setVolume before rediscover',
      );
      final preRediscoverEvent = h1.events.last as api.ChangeEventDto_Volume;
      expect(preRediscoverEvent.volume, 88);

      // ── Rediscover ─────────────────────────────────────────────────
      // This builds a FRESH MockWire, runs discover() on it, calls
      // subscribe_speakers (which seeds into the NEW channel), bumps
      // the generation in state_manager, clears the cache, then drops
      // the old wire (closing the OLD Sender). The OLD consumer loop
      // returns and the OLD Dart subscription's onDone fires.
      await api.devDiscoverMock();

      // The OLD subscription completes once the Rust loop returns.
      await _waitFor(
        () => oldStreamDone,
        timeout: const Duration(seconds: 5),
        message: 'OLD stream must complete after rediscover replaces the wire',
      );

      // ── NEW subscribe ──────────────────────────────────────────────
      // Captures events from the NEW wire. The seed phase should
      // produce exactly the same shape as the first discover - the
      // mock is deterministic.
      final h2 = _subscribeAndCollect();
      await h2.seedComplete.future.timeout(const Duration(seconds: 5));

      // Drain any straggler events the NEW pump might emit (none
      // expected; pin the count so a regression surfaces).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        h2.events,
        hasLength(_expectedSeedCount),
        reason:
            'NEW seed phase must match the deterministic mock seed shape - '
            'a stale event leaked from the OLD wire would inflate the count',
      );

      // The NEW Kitchen volume seed must be the fixture default
      // (SEED_VOLUME = 30), NOT the 88 we wrote on the OLD wire. If
      // the state-manager cache hadn't been bumped + cleared, a
      // stale apply_event from the OLD consumer's last drain might
      // still be sitting in the cache. The seed shape doesn't go
      // through the cache directly, but the fresh-fixture invariant
      // is what we're asserting here: every test run starts the new
      // wire with SEED_VOLUME, not the last-written value.
      final newKitchenSeed = h2.events
          .whereType<api.ChangeEventDto_Volume>()
          .firstWhere((e) => e.speakerId == 'RINCON_KITCHEN');
      expect(
        newKitchenSeed.volume,
        30,
        reason:
            'NEW wire must seed Kitchen at SEED_VOLUME (30) - the 88 we '
            'wrote on the OLD wire belongs to a torn-down wire and must '
            'not survive the generation bump',
      );

      unawaited(h1.sub.cancel());
      unawaited(h2.sub.cancel());
    },
  );
}
