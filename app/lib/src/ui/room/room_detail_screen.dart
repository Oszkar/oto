import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../group/group_editor_screen.dart';
import '../shell/oto_scaffold.dart';
import '../widgets/album_art.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';

/// Room detail screen. Shows the room's header, a now-playing mini-card
/// (transport routed to the room's GROUP), a per-room volume slider, and a
/// kebab that opens the group editor seeded with this room.
///
/// Backend-true: no EQ / TV / System sections.
class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({super.key, required this.speakerId});

  final String speakerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(
      householdProvider.select((h) => h.rooms[speakerId]),
    );

    if (room == null) {
      return OtoScaffold(
        body: _buildHeader(context, ref, null, null),
      );
    }

    final gid = room.groupId;
    final group = ref.watch(
      householdProvider.select((h) => gid == null ? null : h.groups[gid]),
    );

    return OtoScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, ref, room.name, room.model),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.screen18,
                  Space.gutter12,
                  Space.screen18,
                  Space.section22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NowPlayingCard(speakerId: speakerId, group: group),
                    const SizedBox(height: Space.screen18),
                    _VolumeRow(speakerId: speakerId, volume: room.volume),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    String? name,
    String? model,
  ) {
    final oto = context.oto;
    final memberCount = ref.watch(
      householdProvider.select((h) {
        final room = h.rooms[speakerId];
        final gid = room?.groupId;
        return gid == null ? 1 : (h.groups[gid]?.memberIds.length ?? 1);
      }),
    );

    return Padding(
      // JSX header: `8px 18px 14px`, items centered, gap 12.
      padding: const EdgeInsets.fromLTRB(
        Space.xs4,
        Space.md8,
        Space.screen18,
        Space.card14,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: OtoIcon('chevronLeft', size: 18, color: oto.ink2),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Fonts.sans,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 19 * -0.015,
                  ),
                ),
                if (model != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.caption.copyWith(color: oto.inkMute),
                  ),
                ],
              ],
            ),
          ),
          _KebabButton(
            speakerId: speakerId,
            memberCount: memberCount,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Now-playing mini-card
// ---------------------------------------------------------------------------

class _NowPlayingCard extends ConsumerWidget {
  const _NowPlayingCard({required this.speakerId, required this.group});

  final String speakerId;
  final GroupState? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final track = group?.track;
    final playing = group?.transport == PlaybackState.playing;
    final ctrl = ref.read(playbackControllerProvider);
    // For a solo room the groupId is the room's own group; resolve it from the
    // group passed in (group?.id) or fall back to the room's groupId.
    final gid = group?.id ??
        ref.read(householdProvider.select((h) => h.rooms[speakerId]?.groupId));

    return Container(
      padding: const EdgeInsets.all(Space.lg10),
      decoration: BoxDecoration(
        color: oto.surface,
        border: Border.all(color: oto.line),
        borderRadius: BorderRadius.circular(Radius_.card16 - 2),
      ),
      child: Row(
        children: [
          AlbumArt(track?.artUri, size: 48),
          const SizedBox(width: Space.gutter12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Fonts.sans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (track?.artist != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    track!.artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.caption.copyWith(color: oto.inkMute),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: Key('room-detail-prev-$speakerId'),
            onPressed: gid == null ? null : () => ctrl.previous(gid),
            icon: OtoIcon('prev', size: 18, color: oto.ink),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            key: Key('room-detail-play-$speakerId'),
            onPressed: gid == null
                ? null
                : () => ctrl.togglePlay(
                      gid,
                      group?.transport ?? PlaybackState.paused,
                    ),
            icon: OtoIcon(
              playing ? 'pause' : 'play',
              size: 22,
              color: oto.ink,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            key: Key('room-detail-next-$speakerId'),
            onPressed: gid == null ? null : () => ctrl.next(gid),
            icon: OtoIcon('next', size: 18, color: oto.ink),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-room volume slider
// ---------------------------------------------------------------------------

class _VolumeRow extends ConsumerWidget {
  const _VolumeRow({required this.speakerId, required this.volume});

  final String speakerId;
  final int? volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final hasVolume = volume != null;
    final value = (volume ?? 0) / 100;
    final ctrl = ref.read(playbackControllerProvider);

    return Row(
      children: [
        OtoIcon('volume', size: 18, color: oto.ink2),
        const SizedBox(width: Space.card14),
        Expanded(
          child: OtoSlider(
            key: Key('room-volume-$speakerId'),
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
          width: 28,
          child: Text(
            hasVolume ? '$volume' : '-',
            textAlign: TextAlign.right,
            style: TextStyles.caption.copyWith(
              fontFamily: Fonts.mono,
              fontWeight: FontWeight.w600,
              color: oto.ink,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Kebab button + menu
// ---------------------------------------------------------------------------

class _KebabButton extends ConsumerWidget {
  const _KebabButton({required this.speakerId, required this.memberCount});

  final String speakerId;
  final int memberCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: Key('room-kebab-$speakerId'),
      onPressed: () => _showMenu(context, ref),
      icon: OtoIcon('more', size: 18, color: context.oto.ink2),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _KebabSheet(
        speakerId: speakerId,
        memberCount: memberCount,
        onGroupRooms: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupEditorScreen(hostId: speakerId),
            ),
          );
        },
        onUngroup: memberCount > 1
            ? () {
                Navigator.of(ctx).pop();
                ref.read(groupingControllerProvider).leaveGroup(speakerId);
              }
            : null,
      ),
    );
  }
}

class _KebabSheet extends StatelessWidget {
  const _KebabSheet({
    required this.speakerId,
    required this.memberCount,
    required this.onGroupRooms,
    required this.onUngroup,
  });

  final String speakerId;
  final int memberCount;
  final VoidCallback onGroupRooms;
  final VoidCallback? onUngroup;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: Key('room-kebab-group-$speakerId'),
            leading: OtoIcon('group', size: 20, color: oto.ink2),
            title: const Text('Group rooms'),
            onTap: onGroupRooms,
          ),
          if (onUngroup != null)
            ListTile(
              key: Key('room-kebab-ungroup-$speakerId'),
              leading: OtoIcon('x', size: 20, color: oto.danger),
              title: Text('Ungroup', style: TextStyle(color: oto.danger)),
              onTap: onUngroup,
            ),
          const SizedBox(height: Space.md8),
        ],
      ),
    );
  }
}
