import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oto/src/state/commands.dart';
import 'package:oto/src/state/discovery.dart';
import 'package:oto/src/state/household.dart';
import 'package:oto/src/state/model/group_state.dart';
import 'package:oto/src/state/model/household.dart';
import 'package:oto/src/state/model/room_state.dart';
import 'package:oto/src/state/model/track.dart';
import 'package:oto/src/state/now_playing.dart';
import 'package:oto/src/state/prefs.dart';
import 'package:oto/src/rust/api.dart' as api;
import 'package:oto/src/theme/accent.dart';
import 'package:oto/src/theme/oto_theme.dart';
import 'package:oto/src/ui/group/group_editor_screen.dart';
import 'package:oto/src/ui/home/home_screen.dart';
import 'package:oto/src/ui/home/room_card.dart';
import 'package:oto/src/ui/home/room_row.dart';
import 'package:oto/src/ui/now_playing/now_playing_screen.dart';
import 'package:oto/src/ui/room/room_detail_screen.dart';
import 'package:oto/src/ui/widgets/oto_slider.dart';
import 'package:oto/src/ui/shell/nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home/_fixtures.dart';

class _MutableHousehold extends HouseholdNotifier {
  _MutableHousehold(this.initial);
  final Household initial;
  @override
  Household build() => initial;
  void replace(Household household) => state = household;
}

class _Discovery extends Discovery {
  @override
  Future<api.Topology> build() async => const api.Topology(
    speakers: [
      api.DiscoveredSpeaker(id: 'A', roomName: 'A', ip: '10.0.0.1', model: ''),
    ],
    groups: [
      api.DiscoveredGroup(id: 'A', coordinator: 'A', members: ['A']),
    ],
  );
}

Household _soloRooms(
  List<String> ids, {
  String suffix = '',
  bool playing = false,
}) => Household(
  rooms: {
    for (final id in ids)
      id: RoomState(
        id: id,
        name: id,
        kind: RoomKind.speaker,
        volume: 40,
        groupId: '$id$suffix',
      ),
  },
  groups: {
    for (final id in ids)
      '$id$suffix': GroupState(
        id: '$id$suffix',
        coordinatorId: id,
        memberIds: [id],
        groupVolume: 40,
        transport: playing ? PlaybackState.playing : PlaybackState.stopped,
        track: playing ? Track(title: 'Track $id$suffix') : null,
      ),
  },
);

Future<({SpyPlayback playback, SpyGrouping grouping})> _pump(
  WidgetTester tester,
  _MutableHousehold household,
  Widget child, {
  HomeLayout layout = HomeLayout.stack,
  bool push = false,
}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  SharedPreferences.setMockInitialValues({'homeLayout': layout.name});
  final prefs = await SharedPreferences.getInstance();
  late SpyPlayback playback;
  late SpyGrouping grouping;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        householdProvider.overrideWith(() => household),
        discoveryProvider.overrideWith(_Discovery.new),
        prefsRepositoryProvider.overrideWithValue(PrefsRepository(prefs)),
        playbackControllerProvider.overrideWith(
          (ref) => playback = SpyPlayback(ref),
        ),
        groupingControllerProvider.overrideWith(
          (ref) => grouping = SpyGrouping(ref),
        ),
        positionApiProvider.overrideWithValue(const StubPositionApi()),
      ],
      child: MaterialApp(
        theme: otoTheme(Brightness.light, Accent.teal),
        home: Consumer(
          builder: (context, ref, _) {
            ref.read(playbackControllerProvider);
            ref.read(groupingControllerProvider);
            return push
                ? Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => child)),
                      child: const Text('Open'),
                    ),
                  )
                : child;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (push) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
  return (playback: playback, grouping: grouping);
}

void main() {
  for (final layout in HomeLayout.values) {
    testWidgets(
      '$layout: topology removal cannot redirect a solo volume drag',
      (tester) async {
        final household = _MutableHousehold(_soloRooms(['A', 'B', 'C', 'D']));
        final spies = await _pump(
          tester,
          household,
          const HomeScreen(),
          layout: layout,
        );
        final room = find.byWidgetPredicate(
          (widget) =>
              widget is RoomCard && widget.speakerId == 'B' ||
              widget is RoomRow && widget.speakerId == 'B',
        );
        final slider = find.descendant(
          of: room,
          matching: find.byType(OtoSlider),
        );
        final gesture = await tester.startGesture(tester.getCenter(slider));
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        expect(
          spies.playback.calls.any((c) => c.startsWith('setVolume(B,')),
          isTrue,
        );
        spies.playback.calls.clear();
        household.replace(_soloRooms(['B', 'C', 'D']));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 0));
        await gesture.up();
        await tester.pump();
        expect(
          spies.playback.calls.where((c) => c.startsWith('setVolume')),
          everyElement(matches(r'^setVolume(?:End)?\(B,')),
        );
      },
    );
  }

  testWidgets(
    'phone Now Playing follows coordinator through new and reused group IDs',
    (tester) async {
      final household = _MutableHousehold(_soloRooms(['A'], playing: true));
      final spies = await _pump(
        tester,
        household,
        const NowPlayingScreen(groupId: 'A'),
        push: true,
      );
      final next = _soloRooms(['A', 'B'], suffix: '-new', playing: true);
      household.replace(
        Household(
          rooms: next.rooms,
          groups: {
            'A-new': next.groups['A-new']!,
            'A': next.groups['B-new']!.copyWith(id: 'A'),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Track A-new'), findsOneWidget);
      expect(find.text('Track B-new'), findsNothing);
      await tester.tap(find.byKey(const Key('np-play-A-new')));
      expect(spies.playback.calls, contains('togglePlay(A-new,playing)'));
      household.replace(_soloRooms(['B'], playing: true));
      await tester.pumpAndSettle();
      expect(find.text('This source is no longer available.'), findsOneWidget);
      expect(find.byKey(const Key('np-play-B')), findsNothing);
    },
  );

  testWidgets('room options stays actionable when the window widens', (
    tester,
  ) async {
    final household = _MutableHousehold(_soloRooms(['A']));
    await _pump(
      tester,
      household,
      const RoomDetailScreen(speakerId: 'A'),
      push: true,
    );
    await tester.tap(find.byKey(const Key('room-kebab-A')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-kebab-group-A')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(GroupEditorBody), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('room options survives removal of its originating room widget', (
    tester,
  ) async {
    final household = _MutableHousehold(groupEditHousehold());
    final spies = await _pump(
      tester,
      household,
      const RoomDetailScreen(speakerId: 'KT'),
      push: true,
    );
    await tester.tap(find.byKey(const Key('room-kebab-KT')));
    await tester.pumpAndSettle();
    household.replace(_soloRooms(['LR']));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room-kebab-ungroup-KT')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(spies.grouping.calls, contains('leaveGroup(KT)'));
  });

  testWidgets('wide group confirmation stays actionable after narrowing', (
    tester,
  ) async {
    final household = _MutableHousehold(groupEditHousehold());
    final spies = await _pump(
      tester,
      household,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openGroupEditor(context, 'LR'),
            child: const Text('Edit group'),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit group'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-ungroup-all')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-confirm-ungroup-all')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(spies.grouping.calls, contains('leaveGroup(KT)'));
    expect(find.byType(GroupEditorBody), findsNothing);
  });

  testWidgets('Ungroup all cancels if topology changes during confirmation', (
    tester,
  ) async {
    final household = _MutableHousehold(groupEditHousehold());
    final spies = await _pump(
      tester,
      household,
      const GroupEditorScreen(hostId: 'LR'),
      push: true,
    );
    await tester.tap(find.byKey(const Key('group-ungroup-all')));
    await tester.pumpAndSettle();
    household.replace(_soloRooms(['LR', 'KT', 'BR']));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-confirm-ungroup-all')));
    await tester.pumpAndSettle();
    expect(spies.grouping.calls, isEmpty);
    expect(
      find.text('Rooms changed. Review the group and try again.'),
      findsOneWidget,
    );
    expect(find.byType(GroupEditorBody), findsOneWidget);
  });
}
