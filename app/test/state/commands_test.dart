import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/rust/api.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/events.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';

/// One group `G1` (coord `LR`, members `[LR, KT]`) returned without any real
/// `discover()`. `buildCount` lets the NotFound test assert re-discovery.
const _topo = Topology(
  speakers: [
    DiscoveredSpeaker(id: 'LR', roomName: 'Living Room', model: 'Beam', ip: '1'),
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
class _SpyApi extends CommandApi {
  final calls = <String>[];
  CommandError? throwOn;

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
  Future<void> setVolume(String speakerId, int v) async {
    calls.add('setVolume($speakerId,$v)');
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
      changeEventsProvider
          .overrideWith((ref) => const Stream<ChangeEventDto>.empty()),
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
  test('togglePlay flips transport optimistically and sends play once', () async {
    final spy = _SpyApi();
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    container.read(householdProvider.notifier)
        .setOptimisticTransport('G1', PlaybackState.paused);

    await container
        .read(playbackControllerProvider)
        .togglePlay('G1', PlaybackState.paused);

    expect(container.read(householdProvider).groups['G1']!.transport,
        PlaybackState.playing);
    expect(spy.calls, ['play(G1)']);
  });

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

    expect(discovery.buildCount, greaterThan(before),
        reason: 'NotFound → ref.invalidate(discoveryProvider) re-ran build');
  });

  test('Sonos reject rolls transport back', () async {
    final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    container.read(householdProvider.notifier)
        .setOptimisticTransport('G1', PlaybackState.paused);

    await container
        .read(playbackControllerProvider)
        .togglePlay('G1', PlaybackState.paused);

    expect(container.read(householdProvider).groups['G1']!.transport,
        PlaybackState.paused,
        reason: 'optimistic playing rolled back to paused on Sonos reject');
  });

  test('Sonos reject on volume rolls the slider back', () async {
    final spy = _SpyApi()..throwOn = const CommandError.sonos('x');
    final (:container, :discovery) = _container(spy);
    await _seedHousehold(container);
    container.read(householdProvider.notifier).setOptimisticVolume('KT', 20);

    container.read(playbackControllerProvider).setVolumeEnd('KT', 55);
    await Future<void>.delayed(Duration.zero); // let the async send settle.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(householdProvider).rooms['KT']!.volume, 20,
        reason: 'optimistic 55 rolled back to the pre-gesture 20');
  });

  test('setVolumeEnd sends exactly once (pending trailing send canceled)',
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

    expect(spy.calls, ['setVolume(KT,50)'],
        reason: 'exactly one send — the trailing throttle was canceled, not flushed');
    expect(container.read(householdProvider).rooms['KT']!.volume, 50);
  });
}
