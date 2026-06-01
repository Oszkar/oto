/// Tests for `topologyControllerProvider` (v0.5 S1, Option A): a burst of
/// `TopologyChanged` events from the unified change-event stream must be
/// debounced (250 ms) into exactly one `discoveryProvider` re-pull, a single
/// event triggers exactly one re-pull, and non-topology events trigger none.
///
/// FRB and a real LAN are bypassed: `changeEventsProvider` is overridden
/// with a controllable stream and `discoveryProvider` with a counting fake,
/// so the test observes the controller's debounce + invalidate behavior
/// without touching Rust.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart' as rust_api;
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/topology.dart';

const _fakeTopology = rust_api.Topology(
  speakers: [
    rust_api.DiscoveredSpeaker(
      id: 'RINCON_KITCHEN',
      roomName: 'Kitchen',
      ip: '10.0.0.10',
    ),
  ],
  groups: [
    rust_api.DiscoveredGroup(
      id: 'RINCON_KITCHEN:0',
      coordinator: 'RINCON_KITCHEN',
      members: ['RINCON_KITCHEN'],
    ),
  ],
);

/// A little longer than the controller's 250 ms debounce, so the timer has
/// fired by the time we flush + assert.
const _pastDebounce = Duration(milliseconds: 400);

/// Per-test ceiling so a regression that hangs fails fast (not the default
/// 30 s) — the controller's only timing is a 250 ms debounce.
const _testTimeout = Timeout(Duration(seconds: 8));

void main() {
  group('topologyController', () {
    late StreamController<rust_api.ChangeEventDto> events;
    late int discoveryBuilds;
    late ProviderContainer container;

    setUp(() {
      events = StreamController<rust_api.ChangeEventDto>.broadcast();
      discoveryBuilds = 0;
      container = ProviderContainer(
        overrides: [
          // Decouple from FRB: the controller listens to this stream.
          changeEventsProvider.overrideWith((ref) => events.stream),
          // Count (re)builds; an invalidate() by the controller forces one.
          discoveryProvider.overrideWith((ref) async {
            discoveryBuilds++;
            return _fakeTopology;
          }),
        ],
      );
      // A listener so discoveryProvider actually (re)builds on invalidate.
      container.listen(discoveryProvider, (_, _) {}, fireImmediately: true);
      // Activate + keep the controller mounted (a persistent listener, not a
      // one-shot read) so its ref.listen subscription stays live for the test.
      container.listen(topologyControllerProvider, (_, _) {}, fireImmediately: true);
    });

    tearDown(() {
      // Dispose the container FIRST so Riverpod cancels its stream
      // subscription + the controller's debounce timer (via onDispose);
      // then close the (now unlistened) controller without awaiting —
      // awaiting an actively-subscribed broadcast close can stall.
      container.dispose();
      unawaited(events.close());
    });

    /// Fire `events`, wait past the debounce window, and flush the
    /// microtask/timer queue so the invalidate-driven rebuild has run.
    Future<void> settle() async {
      await Future<void>.delayed(_pastDebounce);
      await pumpEventQueue();
    }

    test('a single TopologyChanged triggers one re-pull after the window',
        () async {
      await pumpEventQueue();
      expect(discoveryBuilds, 1, reason: 'initial build only');

      events.add(const rust_api.ChangeEventDto.topologyChanged());
      await settle();

      expect(discoveryBuilds, 2, reason: 'one re-pull after the debounce window');
    }, timeout: _testTimeout);

    test('a burst of TopologyChanged coalesces into exactly one re-pull',
        () async {
      await pumpEventQueue();
      expect(discoveryBuilds, 1);

      // Three events well within the 250 ms window.
      events.add(const rust_api.ChangeEventDto.topologyChanged());
      events.add(const rust_api.ChangeEventDto.topologyChanged());
      events.add(const rust_api.ChangeEventDto.topologyChanged());
      await settle();

      expect(
        discoveryBuilds,
        2,
        reason: 'the per-speaker NOTIFY burst must coalesce into one re-pull',
      );
    }, timeout: _testTimeout);

    test('non-topology events do not trigger a re-pull', () async {
      await pumpEventQueue();
      expect(discoveryBuilds, 1);

      events.add(
        const rust_api.ChangeEventDto.volume(speakerId: 'RINCON_KITCHEN', volume: 40),
      );
      events.add(const rust_api.ChangeEventDto.mute(speakerId: 'RINCON_KITCHEN', muted: true));
      await settle();

      expect(discoveryBuilds, 1, reason: 'only TopologyChanged re-pulls');
    }, timeout: _testTimeout);
  });
}
