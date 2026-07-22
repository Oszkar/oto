import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/state/command_failures.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';

/// One group `G1` (coord `LR`, members `[LR, KT]`) returned without any real
/// `discover()`. `buildCount` lets the NotFound test assert re-discovery.
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
    DiscoveredGroup(id: 'G1', coordinator: 'LR', members: ['LR', 'KT']),
  ],
);

class _FakeDiscovery extends Discovery {
  int buildCount = 0;
  @override
  Future<Topology> build() async {
    buildCount++;
    return _topo;
  }
}

/// Records every command call and, when armed, throws a chosen [CommandError].
///
/// When [deferVolume] is set, `setVolume` returns a pending future captured in
/// [volumeCompleters] so a test can complete in-flight sends out of order (the
/// N3 stale-send race).
class _SpyApi extends CommandApi {
  final calls = <String>[];
  CommandError? throwOn;
  bool deferVolume = false;
  final volumeCompleters = <Completer<void>>[];

  void _maybeThrow() {
    final t = throwOn;
    if (t != null) throw t;
  }

  @override
  Future<void> play(String groupId) async {
    calls.add('play($groupId)');
    _maybeThrow();
  }

  @override
  Future<void> pause(String groupId) async {
    calls.add('pause($groupId)');
    _maybeThrow();
  }

  @override
  Future<void> setVolume(String speakerId, int v) {
    calls.add('setVolume($speakerId,$v)');
    if (deferVolume) {
      final c = Completer<void>();
      volumeCompleters.add(c);
      return c.future;
    }
    final t = throwOn;
    return t != null ? Future<void>.error(t) : Future<void>.value();
  }

  @override
  Future<void> setMute(String speakerId, bool m) async {
    calls.add('setMute($speakerId,$m)');
    _maybeThrow();
  }

  @override
  Future<void> joinGroup(String speakerId, String coordinatorId) async {
    calls.add('joinGroup($speakerId,$coordinatorId)');
    _maybeThrow();
  }

  @override
  Future<void> leaveGroup(String speakerId) async {
    calls.add('leaveGroup($speakerId)');
    _maybeThrow();
  }

  @override
  Future<void> setGroupVolume(String groupId, int v) async {
    calls.add('setGroupVolume($groupId,$v)');
    _maybeThrow();
  }

  @override
  Future<void> setGroupMute(String groupId, bool m) async {
    calls.add('setGroupMute($groupId,$m)');
    _maybeThrow();
  }
}

/// Build a container wired entirely off Rust: fake discovery, empty event
/// stream (bypasses the real `currentWireGeneration()`), spy command api.
({ProviderContainer container, _FakeDiscovery discovery}) _container(
  _SpyApi spy,
) {
  final discovery = _FakeDiscovery();
  final container = ProviderContainer(
    overrides: [
      discoveryProvider.overrideWith(() => discovery),
      changeEventsProvider.overrideWith(
        (ref) => const Stream<ChangeEventDto>.empty(),
      ),
      commandApiProvider.overrideWithValue(spy),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, discovery: discovery);
}

/// Instantiate the household + fold the fake topology in via the awaited
/// discovery future (the `fireImmediately` listener applies the data).
Future<void> _seedHousehold(ProviderContainer c) async {
  c.read(householdProvider); // instantiate the notifier (starts the listen).
  await c.read(discoveryProvider.future); // resolve → household folds topology.
}

void main() {
  test(
    'togglePlay flips transport optimistically and sends play once',
    () async {
      final spy = _SpyApi();
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      container
          .read(householdProvider.notifier)
          .setOptimisticTransport('G1', PlaybackState.paused);

      await container
          .read(playbackControllerProvider)
          .togglePlay('G1', PlaybackState.paused);

      expect(
        container.read(householdProvider).groups['G1']!.transport,
        PlaybackState.playing,
      );
      expect(spy.calls, ['play(G1)']);
    },
  );

  test('CommandError_NotFound invalidates discovery (re-discovers)', () async {
    final spy = _SpyApi()..throwOn = const CommandError.notFound('x');
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    final before = discovery.buildCount;

    await container
        .read(playbackControllerProvider)
        .togglePlay('G1', PlaybackState.paused);
    // Invalidation re-runs build() lazily; reading the future forces it.
    await container.read(discoveryProvider.future);

    expect(
      discovery.buildCount,
      greaterThan(before),
      reason: 'NotFound → ref.invalidate(discoveryProvider) re-ran build',
    );
  });

  test('Sonos reject rolls transport back', () async {
    final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    container
        .read(householdProvider.notifier)
        .setOptimisticTransport('G1', PlaybackState.paused);

    await container
        .read(playbackControllerProvider)
        .togglePlay('G1', PlaybackState.paused);

    expect(
      container.read(householdProvider).groups['G1']!.transport,
      PlaybackState.paused,
      reason: 'optimistic playing rolled back to paused on Sonos reject',
    );
  });

  test('Sonos reject on volume rolls the slider back', () async {
    final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    container.read(householdProvider.notifier).setOptimisticVolume('KT', 20);

    container.read(playbackControllerProvider).setVolumeEnd('KT', 55);
    await Future<void>.delayed(Duration.zero); // let the async send settle.
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(householdProvider).rooms['KT']!.volume,
      20,
      reason: 'optimistic 55 rolled back to the pre-gesture 20',
    );
  });

  test(
    'setVolumeEnd sends exactly once (pending trailing send canceled)',
    () async {
      final spy = _SpyApi();
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      container.read(householdProvider.notifier).setOptimisticVolume('KT', 30);

      final controller = container.read(playbackControllerProvider);
      controller.setVolume('KT', 50); // arms the 150ms trailing throttle
      controller.setVolumeEnd('KT', 50); // disposes throttle, sends once

      await Future<void>.delayed(Duration.zero);
      // Wait past the throttle window: a disposed timer must NOT fire a 2nd send.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        spy.calls,
        ['setVolume(KT,50)'],
        reason:
            'exactly one send - the trailing throttle was canceled, not flushed',
      );
      expect(container.read(householdProvider).rooms['KT']!.volume, 50);
    },
  );

  test('failed volume with a null anchor clears back to null', () async {
    final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    // KT has no volume yet (cold-start null) - the anchor will be null.
    expect(container.read(householdProvider).rooms['KT']!.volume, isNull);

    container.read(playbackControllerProvider).setVolumeEnd('KT', 40);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(householdProvider).rooms['KT']!.volume,
      isNull,
      reason:
          'a failed command clears the optimistic 40 back to null '
          '(no fabricated value left standing)',
    );
  });

  test('sends to one target are serialized, in order', () async {
    // Two gestures on the same room: the second must NOT dispatch until the
    // first settles. Concurrency here is what let an older failure land after a
    // newer success - and the Rust layer then emitted a SubscriptionError that
    // marked the room unreachable even though the user's last command worked.
    final spy = _SpyApi()..deferVolume = true;
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);

    final c = container.read(playbackControllerProvider);
    c.setVolumeEnd('KT', 20);
    expect(spy.volumeCompleters.length, 1, reason: 'first send dispatched');

    c.setVolumeEnd('KT', 30);
    await Future<void>.delayed(Duration.zero);
    expect(
      spy.volumeCompleters.length,
      1,
      reason: 'second send is queued behind the first, not dispatched',
    );

    spy.volumeCompleters[0].complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(spy.volumeCompleters.length, 2, reason: 'second send follows');
    expect(spy.calls, ['setVolume(KT,20)', 'setVolume(KT,30)']);
  });

  test('sends to DIFFERENT targets still run in parallel', () async {
    // Serialization is per target; unrelated rooms must not queue behind each
    // other, or one dead speaker would stall the whole household.
    final spy = _SpyApi()..deferVolume = true;
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);

    final c = container.read(playbackControllerProvider);
    c.setVolumeEnd('KT', 20);
    c.setVolumeEnd('LR', 40);
    await Future<void>.delayed(Duration.zero);

    expect(spy.volumeCompleters.length, 2);
  });

  test('a superseded gesture failing first neither rolls back nor reports', () async {
    final spy = _SpyApi()..deferVolume = true;
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    container.read(householdProvider.notifier).setOptimisticVolume('KT', 10);

    final c = container.read(playbackControllerProvider);
    c.setVolumeEnd('KT', 20); // gesture 1 - dispatched
    c.setVolumeEnd('KT', 30); // gesture 2 - supersedes it, queued

    // Gesture 1 now fails. The user has already moved to 30, so this must be
    // silent: no rollback to the anchor, no notice.
    spy.volumeCompleters[0].completeError(const CommandError.sonos('late'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(commandFailuresProvider), isNull);
    expect(
      container.read(householdProvider).rooms['KT']!.volume,
      30,
      reason: 'the superseded failure must not roll back over the newer value',
    );

    // And gesture 2 still gets its turn.
    expect(spy.volumeCompleters.length, 2);
    spy.volumeCompleters[1].complete();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(householdProvider).rooms['KT']!.volume, 30);
  });

  test(
    'NotFound rolls the optimistic transport back and re-discovers',
    () async {
      final spy = _SpyApi()..throwOn = const CommandError.notFound('x');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      final before = discovery.buildCount;

      await container
          .read(playbackControllerProvider)
          .togglePlay('G1', PlaybackState.paused);
      await container.read(discoveryProvider.future);

      expect(
        container.read(householdProvider).groups['G1']!.transport,
        PlaybackState.paused,
        reason:
            'NotFound rolls the optimistic playing back to paused, rather '
            'than carrying a wrong guess across re-discovery',
      );
      expect(
        discovery.buildCount,
        greaterThan(before),
        reason: 'NotFound also re-discovers to refresh the stale id',
      );
    },
  );

  test(
    'a stale failed mid-drag send does not roll back over a newer send (N3)',
    () async {
      final spy = _SpyApi()..deferVolume = true; // control completion order.
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      container.read(householdProvider.notifier).setOptimisticVolume('KT', 20);

      final c = container.read(playbackControllerProvider);
      c.setVolume('KT', 30); // arms the 150ms throttle (mid-drag).
      // Let the throttle fire the mid-drag send - it is now in flight.
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(spy.volumeCompleters.length, 1, reason: 'mid-drag send fired');

      c.setVolumeEnd('KT', 55); // final send supersedes the mid-drag one.

      // The stale mid-drag (30) fails. Sends are serialized, so it resolves
      // before the final one dispatches - and its rollback is suppressed
      // because a newer gesture already exists.
      spy.volumeCompleters[0].completeError(const CommandError.sonos('late'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(spy.volumeCompleters.length, 2, reason: 'final send follows');
      spy.volumeCompleters[1].complete();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(householdProvider).rooms['KT']!.volume,
        55,
        reason:
            'final 55 stands; a stale failed mid-drag must not roll back to 20',
      );
    },
  );

  group('GroupingController', () {
    test('joinGroup sends; a NotFound re-discovers', () async {
      final spy = _SpyApi()..throwOn = const CommandError.notFound('x');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      final before = discovery.buildCount;

      await container.read(groupingControllerProvider).joinGroup('KT', 'LR');
      await container.read(discoveryProvider.future);

      expect(spy.calls, ['joinGroup(KT,LR)']);
      expect(
        discovery.buildCount,
        greaterThan(before),
        reason: 'NotFound → ref.invalidate(discoveryProvider)',
      );
    });

    test('leaveGroup sends', () async {
      final spy = _SpyApi();
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);

      await container.read(groupingControllerProvider).leaveGroup('KT');

      expect(spy.calls, ['leaveGroup(KT)']);
    });

    test('Sonos reject on group volume rolls back', () async {
      final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      container
          .read(householdProvider.notifier)
          .setOptimisticGroupVolume('G1', 30);

      container.read(groupingControllerProvider).setGroupVolumeEnd('G1', 65);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(householdProvider).groups['G1']!.groupVolume,
        30,
        reason: 'optimistic 65 rolled back to the pre-gesture 30',
      );
    });

    test(
      'setGroupVolumeEnd sends exactly once (trailing throttle canceled)',
      () async {
        final spy = _SpyApi();
        final (:container, :discovery) = _container(spy);
        await _seedHousehold(container);

        final c = container.read(groupingControllerProvider);
        c.setGroupVolume('G1', 40); // arms throttle
        c.setGroupVolumeEnd('G1', 40); // disposes throttle, sends once
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(spy.calls, ['setGroupVolume(G1,40)']);
        expect(container.read(householdProvider).groups['G1']!.groupVolume, 40);
      },
    );

    test('Sonos reject on group mute rolls back', () async {
      final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      container
          .read(householdProvider.notifier)
          .setOptimisticGroupMuted('G1', false);

      await container.read(groupingControllerProvider).setGroupMute('G1', true);

      expect(
        container.read(householdProvider).groups['G1']!.groupMuted,
        false,
        reason: 'optimistic mute rolled back to the pre-gesture false',
      );
    });

    test('setGroupMute applies optimistically and sends', () async {
      final spy = _SpyApi();
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);

      await container.read(groupingControllerProvider).setGroupMute('G1', true);

      expect(spy.calls, ['setGroupMute(G1,true)']);
      expect(container.read(householdProvider).groups['G1']!.groupMuted, true);
    });

    test(
      'failed group volume with a null anchor clears back to null',
      () async {
        final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
        final (:container, :discovery) = _container(spy);
        await _seedHousehold(container);
        // Group volume is event-only - null until the first GroupVolume event.
        expect(
          container.read(householdProvider).groups['G1']!.groupVolume,
          isNull,
        );

        container.read(groupingControllerProvider).setGroupVolumeEnd('G1', 60);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(householdProvider).groups['G1']!.groupVolume,
          isNull,
          reason: 'a failed group-volume command clears the optimistic 60',
        );
      },
    );

    test('failed group mute with a null prior clears back to null', () async {
      final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      expect(
        container.read(householdProvider).groups['G1']!.groupMuted,
        isNull,
      );

      await container.read(groupingControllerProvider).setGroupMute('G1', true);

      expect(
        container.read(householdProvider).groups['G1']!.groupMuted,
        isNull,
        reason:
            'a failed mute clears the optimistic true back to null '
            '(no prior value to restore)',
      );
    });
  });

  group('per-room mute', () {
    test('applies optimistically and keeps the value on success', () async {
      final spy = _SpyApi();
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);

      await container.read(playbackControllerProvider).setMute('LR', true);

      expect(spy.calls, contains('setMute(LR,true)'));
      expect(container.read(householdProvider).rooms['LR']!.muted, isTrue);
    });

    test('failed mute with a null prior clears back to null', () async {
      final spy = _SpyApi()..throwOn = const CommandError.network('down');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      expect(container.read(householdProvider).rooms['LR']!.muted, isNull);

      await container.read(playbackControllerProvider).setMute('LR', true);

      expect(
        container.read(householdProvider).rooms['LR']!.muted,
        isNull,
        reason:
            'mute is event-fed and unobserved here, so a failed command must '
            'restore null rather than fabricate a false',
      );
    });
  });

  group('failure notices', () {
    test('a failed command reports a labelled notice', () async {
      final spy = _SpyApi()..throwOn = const CommandError.network('down');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);

      await container.read(playbackControllerProvider).setMute('LR', true);

      expect(
        container.read(commandFailuresProvider)?.message,
        'Could not reach Living Room',
      );
    });

    test('a group-addressed failure names the coordinator room', () async {
      final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);

      await container
          .read(playbackControllerProvider)
          .togglePlay('G1', PlaybackState.paused);

      expect(
        container.read(commandFailuresProvider)?.message,
        'Living Room rejected that command',
      );
    });

    test('a successful command reports nothing', () async {
      final spy = _SpyApi();
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);

      await container.read(playbackControllerProvider).setMute('LR', true);

      expect(container.read(commandFailuresProvider), isNull);
    });

    test('a superseded send that fails stays silent', () async {
      // Sends to one target are serialized, so the stale one resolves first;
      // the sequence gate keeps it quiet because a newer gesture supersedes it.
      final spy = _SpyApi()..deferVolume = true;
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      container.read(householdProvider.notifier).setOptimisticVolume('KT', 10);

      final c = container.read(playbackControllerProvider);
      c.setVolumeEnd('KT', 20);
      c.setVolumeEnd('KT', 30);

      spy.volumeCompleters[0].completeError(const CommandError.network('down'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(commandFailuresProvider),
        isNull,
        reason: 'a superseded send must not announce a failure',
      );
      expect(container.read(householdProvider).rooms['KT']!.volume, 30);
    });

    test('a stale-id failure still re-discovers even when superseded', () async {
      // The NotFound re-discover is deliberately OUTSIDE the supersede gate: a
      // stale identifier is stale regardless of which gesture observed it.
      final spy = _SpyApi()..deferVolume = true;
      final (:container, :discovery) = _container(spy);
      await _seedHousehold(container);
      final buildsBefore = discovery.buildCount;

      final c = container.read(playbackControllerProvider);
      c.setVolumeEnd('KT', 20);
      c.setVolumeEnd('KT', 30);

      spy.volumeCompleters[0].completeError(const CommandError.notFound('gone'));
      await Future<void>.delayed(Duration.zero);
      // Invalidation re-runs build() lazily; reading the future forces it.
      await container.read(discoveryProvider.future);

      expect(
        container.read(commandFailuresProvider),
        isNull,
        reason: 'the notice is gated, so a superseded failure stays quiet',
      );
      expect(
        discovery.buildCount,
        greaterThan(buildsBefore),
        reason:
            'but the re-discover is NOT gated - a stale id is stale whichever '
            'gesture observed it',
      );
    });
  });
}
