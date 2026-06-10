import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/oto_scaffold.dart';
import '../widgets/album_art.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';

/// Full-screen Now Playing for one group. Ported from the design-system
/// `V3NowPlaying`, deliberately OMITTING the queue icon, shuffle, repeat, and
/// the Spotify-origin pill (v0.6.0 spec §7) - oto is backend-true and the
/// backend exposes none of those.
///
/// The progress/seek bar is intentionally ABSENT in v0.6.0. The SDK's reactive
/// `CurrentTrack` carries no duration and the backend does not event playback
/// position, so a bar would have no length and nothing to anchor to (it showed
/// `--:--` and reset to 0 on every open). v0.6.1 restores it by polling
/// `speakerState` (GetPositionInfo) for the real duration + position anchor,
/// then ticking locally. The tested `positionAt`/`NowPlayingPosition` logic in
/// `now_playing.dart` is kept dormant for that work. See ROADMAP v0.6.1.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key, required this.groupId});

  final String groupId;

  /// Album-art inset from the screen edge, matching the JSX `HF.W - 88`.
  static const double _artInset = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(householdProvider.select((h) => h.groups[groupId]));
    if (group == null) {
      return OtoScaffold(
        body: _Header(groupId: groupId, child: const SizedBox.shrink()),
      );
    }

    return OtoScaffold(
      body: _Header(
        groupId: groupId,
        child: Expanded(
          child: SingleChildScrollView(
            child: Padding(
              // JSX content inset `12px 24px 16px`.
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _art(context, group),
                  const SizedBox(height: Space.screen18),
                  _trackInfo(context, group),
                  const SizedBox(height: Space.screen18),
                  _transport(context, ref, group),
                  const SizedBox(height: Space.screen18),
                  _volumeSection(context, ref, group),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(BuildContext context, GroupState group) {
    final size = MediaQuery.sizeOf(context).width - _artInset;
    return Center(
      child: AlbumArt(group.track?.artUri, size: size.clamp(0, 320)),
    );
  }

  Widget _trackInfo(BuildContext context, GroupState group) {
    final oto = context.oto;
    final track = group.track;
    final subtitleParts = <String>[
      if (track?.artist != null) track!.artist!,
      if (track?.album != null) track!.album!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track?.title ?? 'Nothing playing',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyles.displayLg,
        ),
        if (subtitleParts.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            subtitleParts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.body.copyWith(color: oto.inkMute),
          ),
        ],
      ],
    );
  }

  /// prev / play-pause / next. No shuffle or repeat (backend-true: §7).
  Widget _transport(BuildContext context, WidgetRef ref, GroupState group) {
    final oto = context.oto;
    final playing = group.transport == PlaybackState.playing;
    final ctrl = ref.read(playbackControllerProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          key: Key('np-prev-$groupId'),
          onPressed: () => ctrl.previous(group.id),
          icon: OtoIcon('prev', size: 30, color: oto.ink),
        ),
        // Center play/pause: the filled ink disc from the JSX.
        IconButton(
          key: Key('np-play-$groupId'),
          onPressed: () =>
              ctrl.togglePlay(group.id, group.transport ?? PlaybackState.paused),
          icon: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: oto.ink,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: OtoIcon(
              playing ? 'pause' : 'play',
              size: 24,
              color: oto.surface,
            ),
          ),
        ),
        IconButton(
          key: Key('np-next-$groupId'),
          onPressed: () => ctrl.next(group.id),
          icon: OtoIcon('next', size: 30, color: oto.ink),
        ),
      ],
    );
  }

  /// Group-master volume slider plus per-room READ-OUTS (the JSX shows level
  /// labels "Living Room · 42", not per-room sliders, so these are read-only).
  Widget _volumeSection(BuildContext context, WidgetRef ref, GroupState group) {
    final oto = context.oto;
    final hasVolume = group.groupVolume != null;
    final value = (group.groupVolume ?? 0) / 100;
    final ctrl = ref.read(groupingControllerProvider);

    return Container(
      // JSX section block inset `12px 14px`.
      padding: const EdgeInsets.symmetric(
        horizontal: Space.card14,
        vertical: Space.gutter12,
      ),
      decoration: BoxDecoration(
        color: oto.surface,
        border: Border.all(color: oto.line),
        borderRadius: BorderRadius.circular(Radius_.card16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          OtoSlider(
            key: Key('np-group-volume-$groupId'),
            value: value,
            onChanged: hasVolume
                ? (v) => ctrl.setGroupVolume(groupId, (v * 100).round())
                : null,
            onChangeEnd: hasVolume
                ? (v) => ctrl.setGroupVolumeEnd(groupId, (v * 100).round())
                : null,
          ),
          const SizedBox(height: Space.sm6),
          _roomReadouts(context, ref, group),
        ],
      ),
    );
  }

  /// Per-room read-out labels (`Room · vol`), divider-separated from the group
  /// master per the JSX. Read-only: per-room control lives in the Room detail
  /// screen (v0.6.1), not here.
  Widget _roomReadouts(BuildContext context, WidgetRef ref, GroupState group) {
    final oto = context.oto;
    return Container(
      padding: const EdgeInsets.only(top: Space.sm6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: oto.line)),
      ),
      child: Wrap(
        spacing: Space.gutter12,
        runSpacing: Space.xs4,
        children: [
          for (final id in group.memberIds) _roomReadout(context, ref, id),
        ],
      ),
    );
  }

  Widget _roomReadout(BuildContext context, WidgetRef ref, String roomId) {
    final oto = context.oto;
    final room = ref.watch(householdProvider.select((h) => h.rooms[roomId]));
    if (room == null) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        style: TextStyles.caption.copyWith(color: oto.inkMute),
        children: [
          TextSpan(text: '${room.name} · '),
          TextSpan(
            text: room.volume?.toString() ?? '–',
            style: TextStyles.caption.copyWith(
              fontFamily: Fonts.mono,
              color: oto.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The dismiss header (a `chevronDown` back button) plus a "Playing on" host
/// caption, wrapping the screen body in a Column. Kept as a small private
/// widget so the unknown-group fallback reuses the same chrome.
class _Header extends ConsumerWidget {
  const _Header({required this.groupId, required this.child});

  final String groupId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final hostName = ref.watch(
      householdProvider.select((h) {
        final g = h.groups[groupId];
        return g == null ? null : h.rooms[g.coordinatorId]?.name;
      }),
    );
    final memberCount = ref.watch(
      householdProvider.select((h) => h.groups[groupId]?.memberIds.length ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // JSX header inset `4px 18px 6px`.
          padding: const EdgeInsets.fromLTRB(
            Space.screen18,
            Space.xs4,
            Space.screen18,
            Space.sm6,
          ),
          child: Row(
            children: [
              IconButton(
                key: Key('np-dismiss-$groupId'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: OtoIcon('chevronDown', size: 18, color: oto.ink2),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PLAYING ON',
                      style: TextStyles.overline.copyWith(
                        fontSize: 10.5,
                        color: oto.inkMute,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OtoIcon('link', size: 12, color: oto.accent),
                        const SizedBox(width: Space.xs4),
                        Flexible(
                          child: Text(
                            memberCount > 1
                                ? '${hostName ?? 'Group'} +${memberCount - 1}'
                                : (hostName ?? 'Group'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.label.copyWith(color: oto.accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Balances the leading dismiss button so the caption stays
              // centered. No queue icon (backend-true: §7).
              const SizedBox(width: 48),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
