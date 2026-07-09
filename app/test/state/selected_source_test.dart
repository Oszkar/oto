import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/selected_source.dart';

/// A household notifier whose value can be swapped at runtime, to drive the
/// selection's reconcile-on-source-change (regroup, a source starting/stopping).
class _MutableHousehold extends HouseholdNotifier {
  _MutableHousehold(this._fixture);
  Household _fixture;
  @override
  Household build() => _fixture;
  void set(Household h) {
    _fixture = h;
    state = h;
  }
}

/// Living Room active, Office idle - the original single-source fixture.
final _household = Household(
  rooms: {
    'LR': const RoomState(
      id: 'LR',
      name: 'Living Room',
      kind: RoomKind.speaker,
      groupId: 'G_ACTIVE',
    ),
    'OF': const RoomState(
      id: 'OF',
      name: 'Office',
      kind: RoomKind.speaker,
      groupId: 'G_IDLE',
    ),
  },
  groups: {
    'G_ACTIVE': const GroupState(
      id: 'G_ACTIVE',
      coordinatorId: 'LR',
      memberIds: ['LR'],
      transport: PlaybackState.playing,
    ),
    'G_IDLE': const GroupState(
      id: 'G_IDLE',
      coordinatorId: 'OF',
      memberIds: ['OF'],
      transport: PlaybackState.stopped,
    ),
  },
);

/// Two solo rooms - "Bedroom" (sorts first) and "Living Room" - each
/// active/idle per the flags, with Living Room's group id overridable to
/// simulate a regroup (the coordinator stays 'LR', only the group id churns).
Household _pair({
  required bool lrActive,
  required bool brActive,
  String lrGroupId = 'G_LR',
}) => Household(
  rooms: {
    'LR': RoomState(
      id: 'LR',
      name: 'Living Room',
      kind: RoomKind.speaker,
      groupId: lrGroupId,
    ),
    'BR': const RoomState(
      id: 'BR',
      name: 'Bedroom',
      kind: RoomKind.speaker,
      groupId: 'G_BR',
    ),
  },
  groups: {
    lrGroupId: GroupState(
      id: lrGroupId,
      coordinatorId: 'LR',
      memberIds: const ['LR'],
      transport: lrActive ? PlaybackState.playing : PlaybackState.stopped,
    ),
    'G_BR': GroupState(
      id: 'G_BR',
      coordinatorId: 'BR',
      memberIds: const ['BR'],
      transport: brActive ? PlaybackState.playing : PlaybackState.stopped,
    ),
  },
);

/// Only Bedroom exists (Living Room unplugged entirely).
final _brOnly = Household(
  rooms: {
    'BR': const RoomState(
      id: 'BR',
      name: 'Bedroom',
      kind: RoomKind.speaker,
      groupId: 'G_BR',
    ),
  },
  groups: {
    'G_BR': const GroupState(
      id: 'G_BR',
      coordinatorId: 'BR',
      memberIds: ['BR'],
      transport: PlaybackState.playing,
    ),
  },
);

/// A container whose household can be swapped via the returned notifier. The
/// `listen` keeps the selection chain alive so its reconcile listener fires on
/// a swap (a bare `read` would let the autoDispose providers drop first).
(ProviderContainer, _MutableHousehold) _live(Household initial) {
  final fx = _MutableHousehold(initial);
  final container = ProviderContainer(
    overrides: [householdProvider.overrideWith(() => fx)],
  );
  addTearDown(container.dispose);
  container.listen(resolvedSourceProvider, (_, _) {});
  return (container, fx);
}

/// Let Riverpod flush its scheduler so `ref.listen` reconcile callbacks run.
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('defaults to the first active source when nothing is selected', () {
    final (container, _) = _live(_household);
    expect(container.read(resolvedSourceProvider), 'G_ACTIVE');
  });

  test('honors an explicit selection of an existing (even idle) group', () {
    final (container, _) = _live(_household);
    container.read(selectedSourceProvider.notifier).select('G_IDLE');
    expect(container.read(resolvedSourceProvider), 'G_IDLE');
  });

  test('selecting an unknown group id is a no-op (keeps the current pick)', () {
    final (container, _) = _live(_household);
    container.read(selectedSourceProvider.notifier).select('G_MISSING');
    expect(container.read(resolvedSourceProvider), 'G_ACTIVE');
  });

  test('resolves to null when there is no selection and no sources', () {
    final (container, _) = _live(const Household());
    expect(container.read(resolvedSourceProvider), isNull);
  });

  test('an explicit pick survives a regroup (group id churns, coord stable)',
      () async {
    final (container, fx) = _live(_pair(lrActive: true, brActive: false));
    container.read(selectedSourceProvider.notifier).select('G_LR');
    expect(container.read(resolvedSourceProvider), 'G_LR');

    // Same coordinator, brand-new group id (as a real regroup produces).
    fx.set(_pair(lrActive: true, brActive: false, lrGroupId: 'G_LR2'));
    await _tick();

    expect(container.read(selectedSourceProvider).coord, 'LR');
    expect(container.read(resolvedSourceProvider), 'G_LR2');
  });

  test('auto default is sticky: a later first-sorting source does not steal it',
      () async {
    final (container, fx) = _live(_pair(lrActive: true, brActive: false));
    // Living Room is the only active source; the pane latches onto it.
    expect(container.read(resolvedSourceProvider), 'G_LR');

    // Bedroom (sorts before "Living Room") starts playing.
    fx.set(_pair(lrActive: true, brActive: true));
    await _tick();

    // The pane stays on Living Room instead of jumping to the now-first Bedroom.
    expect(container.read(resolvedSourceProvider), 'G_LR');
  });

  test('auto default moves to the next active source when the current stops',
      () async {
    final (container, fx) = _live(_pair(lrActive: true, brActive: true));
    // Both active; "Bedroom" sorts first, so the auto latch lands there.
    expect(container.read(resolvedSourceProvider), 'G_BR');

    fx.set(_pair(lrActive: false, brActive: true)); // Bedroom keeps playing
    await _tick();
    // Still on Bedroom (its own source is active) - nothing to move to.
    expect(container.read(resolvedSourceProvider), 'G_BR');

    fx.set(_pair(lrActive: true, brActive: false)); // Bedroom stops, LR plays
    await _tick();
    expect(container.read(resolvedSourceProvider), 'G_LR');
  });

  test('an explicit pin stays put when its source goes idle (unlike auto)',
      () async {
    final (container, fx) = _live(_pair(lrActive: true, brActive: true));
    container.read(selectedSourceProvider.notifier).select('G_LR');
    expect(container.read(resolvedSourceProvider), 'G_LR');

    // Living Room stops; Bedroom still plays. A pin holds; auto would move off.
    fx.set(_pair(lrActive: false, brActive: true));
    await _tick();

    expect(container.read(selectedSourceProvider).pinned, isTrue);
    expect(container.read(resolvedSourceProvider), 'G_LR');
  });

  test('an explicit pin falls back to default when its coordinator vanishes',
      () async {
    final (container, fx) = _live(_pair(lrActive: true, brActive: true));
    container.read(selectedSourceProvider.notifier).select('G_LR');
    expect(container.read(resolvedSourceProvider), 'G_LR');

    // Living Room disappears entirely; only Bedroom remains.
    fx.set(_brOnly);
    await _tick();

    expect(container.read(selectedSourceProvider).pinned, isFalse);
    expect(container.read(resolvedSourceProvider), 'G_BR');
  });

  test('a pinned idle coordinator clears when it vanishes (active list stable)',
      () async {
    // Bedroom playing, Office idle. Pin the idle Office, then remove Office.
    // Bedroom (the only active source) is untouched, so `sources` stays
    // value-equal - the reconcile must be driven by the coordinator-set change.
    final withOffice = Household(
      rooms: {
        'BR': const RoomState(
          id: 'BR',
          name: 'Bedroom',
          kind: RoomKind.speaker,
          groupId: 'G_BR',
        ),
        'OF': const RoomState(
          id: 'OF',
          name: 'Office',
          kind: RoomKind.speaker,
          groupId: 'G_OF',
        ),
      },
      groups: {
        'G_BR': const GroupState(
          id: 'G_BR',
          coordinatorId: 'BR',
          memberIds: ['BR'],
          transport: PlaybackState.playing,
        ),
        'G_OF': const GroupState(
          id: 'G_OF',
          coordinatorId: 'OF',
          memberIds: ['OF'],
          transport: PlaybackState.stopped,
        ),
      },
    );
    final (container, fx) = _live(withOffice);
    container.read(selectedSourceProvider.notifier).select('G_OF');
    expect(container.read(resolvedSourceProvider), 'G_OF');
    expect(container.read(selectedSourceProvider).pinned, isTrue);

    fx.set(_brOnly); // Office gone; Bedroom's active source unchanged.
    await _tick();

    expect(container.read(selectedSourceProvider).pinned, isFalse);
    expect(container.read(resolvedSourceProvider), 'G_BR');
  });

  test('clear() returns an explicit pin to auto-follow', () async {
    final (container, fx) = _live(_pair(lrActive: true, brActive: true));
    container.read(selectedSourceProvider.notifier).select('G_LR');
    expect(container.read(selectedSourceProvider).pinned, isTrue);

    container.read(selectedSourceProvider.notifier).clear();
    // Re-latches onto the first active source ("Bedroom"), no longer pinned.
    expect(container.read(selectedSourceProvider).pinned, isFalse);
    expect(container.read(resolvedSourceProvider), 'G_BR');
    // And now it follows: Bedroom stops -> moves to Living Room.
    fx.set(_pair(lrActive: true, brActive: false));
    await _tick();
    expect(container.read(resolvedSourceProvider), 'G_LR');
  });
}
