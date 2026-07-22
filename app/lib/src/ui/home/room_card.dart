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
import '../widgets/album_art.dart';
import '../widgets/mute_button.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';

/// One solo room rendered as a Cards-layout card. Ported from the design-system
/// `V3CardRoom`. Grouped rooms are rendered by the group card (Task 9); this
/// widget assumes a solo room (its group has a single member).
///
/// States:
/// - playing (group `hasActiveStream`): album art + track + a resume/pause button
/// - idle (group not active): an "Idle" affordance, no play button
/// - unreachable (`online == false`): dimmed, no controls
class RoomCard extends ConsumerWidget {
  const RoomCard({super.key, required this.speakerId});

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

    final card = Container(
      decoration: BoxDecoration(
        color: oto.surface,
        border: Border.all(color: oto.line),
        borderRadius: BorderRadius.circular(Radius_.card16),
      ),
      padding: const EdgeInsets.all(Space.gutter12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('room-open-$speakerId'),
            onTap: offline
                ? null
                : () => openRoom(
                    context,
                    ref,
                    speakerId: speakerId,
                    groupId: room.groupId,
                  ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radius_.card16 - 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _titleRow(context, room, offline),
                const SizedBox(height: Space.lg10),
                if (canResume)
                  _nowPlaying(context, ref, room, group!, playing)
                else
                  _idleRow(context, offline),
              ],
            ),
          ),
          if (!offline) ...[
            const SizedBox(height: Space.lg10),
            _volumeRow(context, ref, room),
          ],
        ],
      ),
    );

    // Unreachable rooms are dimmed (matching the JSX `opacity: 0.55`).
    return offline ? Opacity(opacity: 0.55, child: card) : card;
  }

  Widget _titleRow(BuildContext context, RoomState room, bool offline) {
    final oto = context.oto;
    return Row(
      children: [
        OtoIcon(
          room.kind == RoomKind.soundbar ? 'soundbar' : 'speaker',
          size: 14,
          color: oto.inkMute,
        ),
        const SizedBox(width: Space.md8),
        Expanded(
          child: Text(
            room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.titleCard,
          ),
        ),
      ],
    );
  }

  Widget _nowPlaying(
    BuildContext context,
    WidgetRef ref,
    RoomState room,
    GroupState group,
    bool playing,
  ) {
    final oto = context.oto;
    final track = group.track;
    return Row(
      children: [
        AlbumArt(track?.artUri, size: 44),
        const SizedBox(width: Space.lg10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track?.title ?? 'Playing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.label,
              ),
              if (track?.artist != null)
                Text(
                  track!.artist!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.micro.copyWith(
                    fontWeight: FontWeight.w400,
                    color: oto.inkMute,
                  ),
                ),
            ],
          ),
        ),
        // Resume-only transport: present ONLY when the group has an active stream.
        IconButton(
          key: Key('room-play-$speakerId'),
          tooltip: playing ? 'Pause ${room.name}' : 'Play ${room.name}',
          onPressed: () => ref
              .read(playbackControllerProvider)
              .togglePlay(group.id, group.transport ?? PlaybackState.paused),
          icon: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: oto.ink,
              borderRadius: BorderRadius.circular(Radius_.pill999),
            ),
            alignment: Alignment.center,
            child: OtoIcon(
              playing ? 'pause' : 'play',
              size: 15,
              color: oto.surface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _idleRow(BuildContext context, bool offline) {
    final oto = context.oto;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: oto.fill,
              borderRadius: BorderRadius.circular(Radius_.art10),
            ),
            alignment: Alignment.center,
            child: OtoIcon('play', size: 16, color: oto.inkFaint),
          ),
          const SizedBox(width: Space.lg10),
          Expanded(
            child: Text(
              offline ? 'Unreachable' : 'Idle',
              style: TextStyles.caption.copyWith(color: oto.inkMute),
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeRow(BuildContext context, WidgetRef ref, RoomState room) {
    final oto = context.oto;
    final hasVolume = room.volume != null;
    final muted = room.muted ?? false;
    final value = (room.volume ?? 0) / 100;
    final ctrl = ref.read(playbackControllerProvider);
    return Row(
      children: [
        MuteButton(
          key: Key('room-mute-$speakerId'),
          muted: room.muted,
          enabled: room.online,
          size: 12,
          // NOT inkFaint (what the static icon used): this is an interactive
          // control now, so its colour is load-bearing. inkMute is the
          // AA-passing step up, matching the room row's volume icon.
          color: oto.inkMute,
          label: room.name,
          onToggle: () => ctrl.setMute(speakerId, !muted),
        ),
        const SizedBox(width: Space.md8),
        Expanded(
          child: Opacity(
            opacity: muted ? 0.45 : 1,
            child: OtoSlider(
              value: value,
              // No known volume yet: render a disabled (non-interactive) track.
              onChanged: hasVolume
                  ? (v) => ctrl.setVolume(speakerId, (v * 100).round())
                  : null,
              onChangeEnd: hasVolume
                  ? (v) => ctrl.setVolumeEnd(speakerId, (v * 100).round())
                  : null,
            ),
          ),
        ),
        const SizedBox(width: Space.md8),
        SizedBox(
          width: 18,
          child: Text(
            hasVolume ? '${room.volume}' : '–',
            textAlign: TextAlign.right,
            style: TextStyles.micro.copyWith(
              fontFamily: Fonts.mono,
              color: oto.inkMute,
            ),
          ),
        ),
      ],
    );
  }
}

/// Resolve a room's group from the household. A solo room maps to a single-member
/// group; null when the room is ungrouped/unknown.
GroupState? _groupOf(Household h, RoomState room) {
  final gid = room.groupId;
  return gid == null ? null : h.groups[gid];
}
