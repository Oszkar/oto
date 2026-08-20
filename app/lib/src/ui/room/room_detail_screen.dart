import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/oto_scaffold.dart';
import '../shell/responsive_pop.dart';
import '../widgets/album_art.dart';
import '../widgets/mute_button.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';
import 'room_options_menu.dart';

/// Room detail screen. Shows the room's header, a now-playing mini-card
/// (transport routed to the room's GROUP), a per-room volume slider, and a
/// kebab that opens the group editor seeded with this room.
///
/// Backend-true: no EQ / TV / System sections.
class RoomDetailScreen extends ConsumerStatefulWidget {
  const RoomDetailScreen({super.key, required this.speakerId});

  final String speakerId;

  @override
  ConsumerState<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends ConsumerState<RoomDetailScreen> {
  // Own controller so this scrollable never contends with another primary
  // scrollable (e.g. the wide NowPlayingPane) for the app-wide
  // PrimaryScrollController - see responsive_pop.dart's sibling fix.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.checkResponsivePop()) return const SizedBox.shrink();
    final speakerId = widget.speakerId;
    final room = ref.watch(householdProvider.select((h) => h.rooms[speakerId]));

    if (room == null) {
      // Unknown room (stale nav, or it left via a topology change): show the
      // header chrome only - no kebab, so its actions can't fire with an
      // invalid speakerId.
      return OtoScaffold(
        body: _buildHeader(
          context,
          name: null,
          model: null,
          memberCount: 1,
          showMenu: false,
          hostId: speakerId, // unused: no kebab when showMenu is false
        ),
      );
    }

    final gid = room.groupId;
    final group = ref.watch(
      householdProvider.select((h) => gid == null ? null : h.groups[gid]),
    );
    final memberCount = group?.memberIds.length ?? 1;
    // The group editor is always hosted by the group's COORDINATOR, never the
    // room you happened to open detail for. Passing speakerId would mis-host the
    // editor for a grouped non-coordinator member (wrong join/ungroup targets).
    // A solo room is its own coordinator, so this is identical there.
    final editorHost = group?.coordinatorId ?? speakerId;

    return OtoScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(
            context,
            name: room.name,
            model: room.model,
            memberCount: memberCount,
            showMenu: true,
            hostId: editorHost,
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
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
                      _NowPlayingCard(
                        speakerId: speakerId,
                        gid: gid,
                        group: group,
                        online: room.online,
                      ),
                      const SizedBox(height: Space.screen18),
                      _VolumeRow(
                        speakerId: speakerId,
                        name: room.name,
                        volume: room.volume,
                        muted: room.muted,
                        online: room.online,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String? name,
    required String? model,
    required int memberCount,
    required bool showMenu,
    required String hostId,
  }) {
    final oto = context.oto;

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
            tooltip: 'Back',
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
                  style: TextStyles.titleDetail,
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
          if (showMenu)
            RoomOptionsButton(
              speakerId: widget.speakerId,
              hostId: hostId,
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
  const _NowPlayingCard({
    required this.speakerId,
    required this.gid,
    required this.group,
    required this.online,
  });

  final String speakerId;

  /// The room's group id (command target). Null only when the room has no known
  /// group (unknown/offline), which disables the transport controls. Passed from
  /// the parent rather than re-derived so transport still targets the right group
  /// even if the group object is transiently absent from the household map.
  final String? gid;

  final GroupState? group;

  /// Whether the room is reachable. Offline -> transport is disabled (the
  /// speaker can't be commanded), mirroring RoomRow/RoomCard.
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final gid = this.gid; // local copy enables null-promotion in the handlers
    final track = group?.track;
    final playing = group?.transport == PlaybackState.playing;
    final ctrl = ref.read(playbackControllerProvider);

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
                  style: TextStyles.label,
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
            tooltip: 'Previous track',
            onPressed: (gid == null || !online)
                ? null
                : () => ctrl.previous(gid),
            icon: OtoIcon('prev', size: 18, color: oto.ink),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: Sizes.touchTarget44,
              minHeight: Sizes.touchTarget44,
            ),
          ),
          IconButton(
            key: Key('room-detail-play-$speakerId'),
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: (gid == null || !online)
                ? null
                : () => ctrl.togglePlay(
                    gid,
                    group?.transport ?? PlaybackState.paused,
                  ),
            icon: OtoIcon(playing ? 'pause' : 'play', size: 22, color: oto.ink),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: Sizes.touchTarget44,
              minHeight: Sizes.touchTarget44,
            ),
          ),
          IconButton(
            key: Key('room-detail-next-$speakerId'),
            tooltip: 'Next track',
            onPressed: (gid == null || !online) ? null : () => ctrl.next(gid),
            icon: OtoIcon('next', size: 18, color: oto.ink),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: Sizes.touchTarget44,
              minHeight: Sizes.touchTarget44,
            ),
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
  const _VolumeRow({
    required this.speakerId,
    required this.name,
    required this.volume,
    required this.muted,
    required this.online,
  });

  final String speakerId;

  /// Room name - names the mute action in its tooltip.
  final String name;

  final int? volume;

  /// Current mute state; null when no `Mute` event has been seen yet.
  final bool? muted;

  /// Offline -> disable the slider (the speaker is unreachable), mirroring
  /// RoomRow/RoomCard. A stale last-known volume can still render.
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final hasVolume = volume != null;
    final enabled = hasVolume && online;
    final value = (volume ?? 0) / 100;
    final ctrl = ref.read(playbackControllerProvider);

    return Row(
      children: [
        MuteButton(
          key: Key('room-detail-mute-$speakerId'),
          muted: muted,
          enabled: online,
          size: 18,
          color: oto.ink2,
          label: name,
          onToggle: () => ctrl.setMute(speakerId, !(muted ?? false)),
        ),
        const SizedBox(width: Space.md8),
        Expanded(
          child: Opacity(
            opacity: (muted ?? false) ? 0.45 : 1,
            child: OtoSlider(
              key: Key('room-volume-$speakerId'),
              value: value,
              onChanged: enabled
                  ? (v) => ctrl.setVolume(speakerId, (v * 100).round())
                  : null,
              onChangeEnd: enabled
                  ? (v) => ctrl.setVolumeEnd(speakerId, (v * 100).round())
                  : null,
            ),
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
              // GeistMono ships 400 + 500 only; w600 silently falls back.
              fontWeight: FontWeight.w500,
              color: oto.ink,
            ),
          ),
        ),
      ],
    );
  }
}
