import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';

/// A multi-room synchrony group rendered as ONE merged card. Ported from the
/// design-system `V3GroupCard` (+ `V3RoomLevel`). A group is one source: the
/// header shows the coordinator's name, a member-count badge, the shared
/// now-playing, and ONE resume/pause transport. Volume is the per-room
/// exception, so the body nests a group-master slider plus each member's level.
///
/// The per-room levels cap at [_maxLevels] visible rows; past that, a
/// "+N more · Room detail" button stubs the (v0.6.1) Room-detail entry while
/// the group-master stays reachable.
class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.groupId});

  final String groupId;

  /// Visible per-room level rows before the overflow button kicks in. From the
  /// JSX `MAXR = 4`.
  static const int _maxLevels = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final group = ref.watch(householdProvider.select((h) => h.groups[groupId]));
    if (group == null) return const SizedBox.shrink();

    final canResume = group.hasActiveStream;
    final playing = group.transport == PlaybackState.playing;

    return Container(
      decoration: BoxDecoration(
        color: oto.surface,
        border: Border.all(color: oto.line),
        borderRadius: BorderRadius.circular(Radius_.card16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, ref, group, canResume, playing),
          _volumeSection(context, ref, group),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    WidgetRef ref,
    GroupState group,
    bool canResume,
    bool playing,
  ) {
    final oto = context.oto;
    // Coordinator's room name titles the card; the count badge + levels list
    // convey membership, so the title never truncates by group size.
    final hostName = ref.watch(
      householdProvider.select((h) => h.rooms[group.coordinatorId]?.name),
    );
    final track = group.track;
    return Padding(
      padding: const EdgeInsets.all(Space.gutter12),
      child: Row(
        children: [
          AlbumArt(track?.artUri, size: 46),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hostName ?? 'Group',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.titleCard,
                      ),
                    ),
                    const SizedBox(width: Space.sm6),
                    _countBadge(context, group.memberIds.length),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _nowPlayingLine(group),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.caption.copyWith(color: oto.inkMute),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md8),
          // Resume-only transport: present ONLY when the group has an active
          // stream, matching the room widgets.
          if (canResume)
            IconButton(
              key: Key('group-play-$groupId'),
              onPressed: () => ref
                  .read(playbackControllerProvider)
                  .togglePlay(
                    group.id,
                    group.transport ?? PlaybackState.paused,
                  ),
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
      ),
    );
  }

  /// The `link` icon + member count pill (JSX accent-soft badge).
  Widget _countBadge(BuildContext context, int count) {
    final oto = context.oto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm6, vertical: 1),
      decoration: BoxDecoration(
        color: oto.accentSoft,
        borderRadius: BorderRadius.circular(Radius_.xs4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OtoIcon('link', size: 9, color: oto.accent),
          const SizedBox(width: 3),
          Text('$count', style: TextStyles.badge.copyWith(color: oto.accent)),
        ],
      ),
    );
  }

  String _nowPlayingLine(GroupState group) {
    final track = group.track;
    if (group.hasActiveStream && track?.title != null) {
      final artist = track?.artist;
      return artist != null ? '${track!.title} - $artist' : track!.title!;
    }
    return 'Idle';
  }

  Widget _volumeSection(BuildContext context, WidgetRef ref, GroupState group) {
    final oto = context.oto;
    final visible = group.memberIds.take(_maxLevels).toList();
    final overflow = group.memberIds.length - visible.length;
    return Container(
      // Literal 14/14 horizontal+bottom padding from the JSX section block; no
      // single token matches the asymmetric 12/14/14 inset.
      padding: const EdgeInsets.fromLTRB(
        Space.card14,
        Space.gutter12,
        Space.card14,
        Space.card14,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: oto.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _groupMaster(context, ref, group),
          const SizedBox(height: Space.gutter12),
          Text(
            'ROOM LEVELS',
            style: TextStyles.overline.copyWith(
              fontSize: 9.5,
              letterSpacing: 9.5 * 0.07,
              color: oto.inkFaint,
            ),
          ),
          for (final id in visible) ...[
            const SizedBox(height: 9),
            _roomLevel(context, ref, id),
          ],
          if (overflow > 0) ...[
            const SizedBox(height: 9),
            _overflowButton(context, overflow),
          ],
        ],
      ),
    );
  }

  Widget _groupMaster(BuildContext context, WidgetRef ref, GroupState group) {
    final oto = context.oto;
    final hasVolume = group.groupVolume != null;
    final value = (group.groupVolume ?? 0) / 100;
    final ctrl = ref.read(groupingControllerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OtoIcon('volume', size: 14, color: oto.ink2),
            const SizedBox(width: Space.md8),
            Text(
              'GROUP VOLUME',
              style: TextStyles.overline.copyWith(color: oto.ink2),
            ),
            const Spacer(),
            SizedBox(
              width: 22,
              child: Text(
                hasVolume ? '${group.groupVolume}' : '–',
                textAlign: TextAlign.right,
                style: TextStyles.caption.copyWith(
                  fontFamily: Fonts.mono,
                  fontWeight: FontWeight.w600,
                  color: oto.ink2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        OtoSlider(
          key: Key('group-volume-$groupId'),
          value: value,
          // Group-master routes through the GroupingController, never per-room.
          onChanged: hasVolume
              ? (v) => ctrl.setGroupVolume(groupId, (v * 100).round())
              : null,
          onChangeEnd: hasVolume
              ? (v) => ctrl.setGroupVolumeEnd(groupId, (v * 100).round())
              : null,
        ),
      ],
    );
  }

  /// One per-room level row (JSX `V3RoomLevel`): name + that room's own slider.
  /// The slider routes through the per-room [PlaybackController], NOT the group
  /// master. A member id missing from `rooms` renders nothing.
  Widget _roomLevel(BuildContext context, WidgetRef ref, String roomId) {
    final oto = context.oto;
    final room = ref.watch(householdProvider.select((h) => h.rooms[roomId]));
    if (room == null) return const SizedBox.shrink();

    final hasVolume = room.volume != null;
    final value = (room.volume ?? 0) / 100;
    final ctrl = ref.read(playbackControllerProvider);
    return Row(
      children: [
        SizedBox(
          // JSX fixes the name column at 92px so sliders align.
          width: 92,
          child: Text(
            room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.caption.copyWith(fontSize: 12, color: oto.ink2),
          ),
        ),
        const SizedBox(width: Space.lg10),
        Expanded(
          child: OtoSlider(
            value: value,
            onChanged: hasVolume
                ? (v) => ctrl.setVolume(roomId, (v * 100).round())
                : null,
            onChangeEnd: hasVolume
                ? (v) => ctrl.setVolumeEnd(roomId, (v * 100).round())
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
              fontSize: 11,
              color: oto.inkMute,
            ),
          ),
        ),
      ],
    );
  }

  /// "+N more · Room detail" overflow entry. Room detail is v0.6.1, so this is
  /// a deliberate no-op stub for now.
  Widget _overflowButton(BuildContext context, int overflow) {
    final oto = context.oto;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        key: Key('group-more-$groupId'),
        // TODO(v0.6.1): push the Room detail screen for this group.
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+$overflow more ${overflow == 1 ? 'room' : 'rooms'}',
                style: TextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: oto.accent,
                ),
              ),
              Text(
                ' · Room detail',
                style: TextStyles.caption.copyWith(color: oto.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
