import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../state/model/household.dart';
import '../../state/model/room_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/nav.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';

/// One solo room rendered as a Stack-layout row. Ported from the design-system
/// `V3StackRow` (collapsed variant). Grouped rooms are rendered by the group
/// card (Task 9); this widget assumes a solo room.
///
/// Line 1: speaker icon + name + subtitle (track when playing, else "Idle" /
/// "Powered off") + a resume/pause transport (only when the group is active).
/// Line 2: a full-width per-room volume slider (hidden when powered off).
class RoomRow extends ConsumerWidget {
  const RoomRow({super.key, required this.speakerId});

  final String speakerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final room = ref.watch(householdProvider.select((h) => h.rooms[speakerId]));
    if (room == null) return const SizedBox.shrink();

    final group = ref.watch(householdProvider.select((h) => _groupOf(h, room)));

    final offline = !room.online;
    // Gate resume on online too: a room that drops offline mid-stream keeps a
    // stale active stream (SubscriptionError clears online, not transport/track),
    // which would otherwise render a live play button on a dimmed offline card.
    final canResume = (group?.hasActiveStream ?? false) && !offline;
    final playing = group?.transport == PlaybackState.playing;

    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: oto.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter12,
          11,
          Space.gutter12,
          Space.gutter12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _identityRow(context, ref, room, group, canResume, playing),
            if (!offline) ...[
              const SizedBox(height: Space.lg10),
              _volumeRow(context, ref, room),
            ],
          ],
        ),
      ),
    );

    return offline ? Opacity(opacity: 0.55, child: row) : row;
  }

  Widget _identityRow(
    BuildContext context,
    WidgetRef ref,
    RoomState room,
    GroupState? group,
    bool canResume,
    bool playing,
  ) {
    final oto = context.oto;
    final offline = !room.online;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: Key('room-open-$speakerId'),
            onTap: offline
                ? null
                : () => openRoom(
                    context,
                    ref,
                    speakerId: speakerId,
                    groupId: room.groupId,
                  ),
            borderRadius: BorderRadius.circular(Radius_.card16 - 1),
            child: Row(
              children: [
                OtoIcon(
                  room.kind == RoomKind.soundbar ? 'soundbar' : 'speaker',
                  size: 18,
                  color: oto.ink2,
                ),
                const SizedBox(width: Space.gutter12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.titleCard,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _subtitle(room, group, offline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.caption.copyWith(color: oto.inkMute),
                      ),
                    ],
                  ),
                ),
                if (!offline)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md8),
                    child: OtoIcon(
                      'chevronRight',
                      size: 12,
                      color: oto.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Resume-only transport: present ONLY when the group has an active stream.
        if (canResume)
          IconButton(
            key: Key('room-play-$speakerId'),
            tooltip: playing ? 'Pause ${room.name}' : 'Play ${room.name}',
            onPressed: () => ref
                .read(playbackControllerProvider)
                .togglePlay(group!.id, group.transport ?? PlaybackState.paused),
            icon: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: oto.fill,
                border: Border.all(color: oto.line),
                borderRadius: BorderRadius.circular(Radius_.pill999),
              ),
              alignment: Alignment.center,
              child: OtoIcon(
                playing ? 'pause' : 'play',
                size: 15,
                color: oto.ink,
              ),
            ),
          ),
      ],
    );
  }

  String _subtitle(RoomState room, GroupState? group, bool offline) {
    if (offline) return 'Powered off';
    final track = group?.track;
    if ((group?.hasActiveStream ?? false) && track?.title != null) {
      final artist = track?.artist;
      return artist != null ? '${track!.title} - $artist' : track!.title!;
    }
    final model = room.model;
    return model != null ? '$model · Idle' : 'Idle';
  }

  Widget _volumeRow(BuildContext context, WidgetRef ref, RoomState room) {
    final oto = context.oto;
    final hasVolume = room.volume != null;
    final value = (room.volume ?? 0) / 100;
    final ctrl = ref.read(playbackControllerProvider);
    return Padding(
      // Align the slider under the room name (icon width + gap), per the JSX.
      padding: const EdgeInsets.only(left: 30),
      child: Row(
        children: [
          OtoIcon('volume', size: 14, color: oto.inkMute),
          const SizedBox(width: Space.lg10),
          Expanded(
            child: OtoSlider(
              value: value,
              onChanged: hasVolume
                  ? (v) => ctrl.setVolume(speakerId, (v * 100).round())
                  : null,
              onChangeEnd: hasVolume
                  ? (v) => ctrl.setVolumeEnd(speakerId, (v * 100).round())
                  : null,
            ),
          ),
          const SizedBox(width: Space.lg10),
          SizedBox(
            width: 22,
            child: Text(
              hasVolume ? '${room.volume}' : '–',
              textAlign: TextAlign.right,
              style: TextStyles.caption.copyWith(
                fontFamily: Fonts.mono,
                color: oto.inkMute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolve a room's group from the household; null when ungrouped/unknown.
GroupState? _groupOf(Household h, RoomState room) {
  final gid = room.groupId;
  return gid == null ? null : h.groups[gid];
}
