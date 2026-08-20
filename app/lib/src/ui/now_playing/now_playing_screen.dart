import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../state/now_playing.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../room/room_options_menu.dart';
import '../shell/oto_scaffold.dart';
import '../shell/responsive_pop.dart';
import '../widgets/album_art.dart';
import '../widgets/mute_button.dart';
import '../widgets/oto_icon.dart';
import '../widgets/oto_slider.dart';
import '../widgets/pane_dismiss.dart';

/// Embeddable Now Playing content for one group. Ported from the
/// design-system `V3NowPlaying`, deliberately OMITTING the queue icon,
/// shuffle, repeat, and the Spotify-origin pill (v0.6.0 spec §7) - oto is
/// backend-true and the backend exposes none of those.
///
/// Chrome-free (no `OtoScaffold`): [NowPlayingScreen] wraps this for the
/// phone route, and on wide layouts the same body renders inside the detail
/// pane. Pass `onDismiss: null` to hide the dismiss chevron for pane use.
///
/// A read-only progress bar sits between the track info and the transport
/// controls. It is fed by [nowPlayingPositionProvider], which reads
/// `track_position` (GetPositionInfo SOAP) for the real mid-track position and
/// duration, then ticks locally at ~500 ms. No seek - there is no seek backend.
class NowPlayingBody extends ConsumerStatefulWidget {
  const NowPlayingBody({super.key, required this.groupId, this.onDismiss});

  final String groupId;
  final VoidCallback? onDismiss;

  @override
  ConsumerState<NowPlayingBody> createState() => _NowPlayingBodyState();
}

class _NowPlayingBodyState extends ConsumerState<NowPlayingBody> {
  /// Upper bound on the album-art side, so it stays a comfortable square on
  /// wide panes and doesn't balloon on large windows.
  static const double _artMax = 320;

  // Own controller so this scrollable never contends with another primary
  // scrollable (e.g. the wide NowPlayingPane sitting alongside Home's own
  // list) for the app-wide PrimaryScrollController - see responsive_pop.dart's
  // sibling fix.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final group = ref.watch(householdProvider.select((h) => h.groups[groupId]));
    if (group == null) {
      return _Header(
        groupId: groupId,
        onDismiss: widget.onDismiss,
        child: const SizedBox.shrink(),
      );
    }

    return _Header(
      groupId: groupId,
      onDismiss: widget.onDismiss,
      child: Expanded(
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
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
                  _progress(context, ref, groupId),
                  const SizedBox(height: Space.screen18),
                  _transport(context, ref, group, groupId),
                  const SizedBox(height: Space.screen18),
                  _volumeSection(context, ref, group, groupId),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(BuildContext context, GroupState group) {
    // Size the square off the pane's OWN width, not the window's: in the wide
    // detail pane the window is far wider than the pane, so keying off screen
    // width stretched the art into a rectangle.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(0.0, _artMax);
        return Center(child: AlbumArt(group.track?.artUri, size: side));
      },
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

  Widget _progress(BuildContext context, WidgetRef ref, String groupId) {
    final oto = context.oto;
    final p = ref.watch(nowPlayingPositionProvider(groupId));
    final dur = p.duration;
    final value = (dur == null || dur.inMilliseconds == 0)
        ? 0.0
        : (p.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OtoSlider(
          key: Key('np-progress-$groupId'),
          value: value,
          onChanged: null, // read-only: no seek (no backend)
          // An indicator, not a disabled control - keep the accent tokens.
          readOnly: true,
        ),
        const SizedBox(height: Space.sm6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(p.position),
              style: TextStyles.caption.copyWith(
                fontFamily: Fonts.mono,
                color: oto.inkMute,
              ),
            ),
            Text(
              dur == null ? '--:--' : _fmt(dur),
              style: TextStyles.caption.copyWith(
                fontFamily: Fonts.mono,
                color: oto.inkMute,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// `m:ss` (or `h:mm:ss` past an hour). Mono, tabular.
  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final two = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$two' : '$mm:$two';
  }

  /// prev / play-pause / next. No shuffle or repeat (backend-true: §7).
  Widget _transport(
    BuildContext context,
    WidgetRef ref,
    GroupState group,
    String groupId,
  ) {
    final oto = context.oto;
    final playing = group.transport == PlaybackState.playing;
    final ctrl = ref.read(playbackControllerProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          key: Key('np-prev-$groupId'),
          tooltip: 'Previous track',
          onPressed: () => ctrl.previous(group.id),
          icon: OtoIcon('prev', size: 30, color: oto.ink),
        ),
        // Center play/pause: the filled ink disc from the JSX.
        IconButton(
          key: Key('np-play-$groupId'),
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: () => ctrl.togglePlay(
            group.id,
            group.transport ?? PlaybackState.paused,
          ),
          icon: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: oto.ink, shape: BoxShape.circle),
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
          tooltip: 'Next track',
          onPressed: () => ctrl.next(group.id),
          icon: OtoIcon('next', size: 30, color: oto.ink),
        ),
      ],
    );
  }

  /// Group-master volume slider plus per-room READ-OUTS (the JSX shows level
  /// labels "Living Room · 42", not per-room sliders, so these are read-only).
  Widget _volumeSection(
    BuildContext context,
    WidgetRef ref,
    GroupState group,
    String groupId,
  ) {
    final oto = context.oto;
    // See GroupCard._groupMaster: a group command goes to the coordinator, so
    // an unreachable coordinator means it cannot land.
    final coordinatorOnline = ref.watch(
      householdProvider.select(
        (h) => h.rooms[group.coordinatorId]?.online ?? true,
      ),
    );
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
              MuteButton(
                key: Key('np-group-mute-$groupId'),
                muted: group.groupMuted,
                enabled: coordinatorOnline,
                size: 14,
                color: oto.ink2,
                label: 'group',
                onToggle: () =>
                    ctrl.setGroupMute(groupId, !(group.groupMuted ?? false)),
              ),
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
                    // GeistMono ships 400 + 500 only; w600 silently falls back.
                    fontWeight: FontWeight.w500,
                    color: oto.ink2,
                  ),
                ),
              ),
            ],
          ),
          Opacity(
            opacity: (group.groupMuted ?? false) ? 0.45 : 1,
            child: OtoSlider(
              key: Key('np-group-volume-$groupId'),
              value: value,
              onChanged: hasVolume
                  ? (v) => ctrl.setGroupVolume(groupId, (v * 100).round())
                  : null,
              onChangeEnd: hasVolume
                  ? (v) => ctrl.setGroupVolumeEnd(groupId, (v * 100).round())
                  : null,
            ),
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

/// The dismiss header (a `chevronDown` back button, omitted when [onDismiss]
/// is null) plus a "Playing on" host caption, wrapping the body in a Column.
/// Kept as a small private widget so the unknown-group fallback reuses the
/// same chrome.
class _Header extends ConsumerWidget {
  const _Header({
    required this.groupId,
    required this.onDismiss,
    required this.child,
  });

  final String groupId;
  final VoidCallback? onDismiss;
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
    // Room-level options belong to a SOLO room only: a multi-room group has no
    // single room to act on, and its own options live on the group card. On
    // wide, Room detail is folded away, so without this the pane offered no
    // join/leave path at all (#129).
    final soloMemberId = ref.watch(
      householdProvider.select((h) {
        final g = h.groups[groupId];
        if (g == null || g.memberIds.length != 1) return null;
        final memberId = g.memberIds.single;
        // Cross-check the room's own view of its group. `householdFromTopology`
        // builds both sides from one topology so they agree, but this control
        // dispatches commands against `memberId` - it should not act on a room
        // that is missing or has already moved to another group.
        return h.rooms[memberId]?.groupId == groupId ? memberId : null;
      }),
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
              PaneDismiss(
                onDismiss: onDismiss,
                icon: 'chevronDown',
                tooltip: 'Dismiss Now Playing',
                buttonKey: Key('np-dismiss-$groupId'),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PLAYING ON',
                      style: TextStyles.overline.copyWith(color: oto.inkMute),
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
              // A solo room gets its options kebab here; otherwise a spacer of
              // the same width keeps the caption centered against the leading
              // dismiss button. No queue icon (backend-true: §7).
              if (soloMemberId == null)
                const SizedBox(width: 48)
              else
                RoomOptionsButton(
                  speakerId: soloMemberId,
                  // A solo room is its own coordinator, so it hosts its own
                  // group editor, and there is nothing to ungroup from.
                  hostId: soloMemberId,
                  memberCount: 1,
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

/// Full-screen Now Playing route (phone). On wide layouts the same content is
/// rendered by `NowPlayingBody` inside the detail pane instead.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    if (context.checkResponsivePop()) return const SizedBox.shrink();
    return OtoScaffold(
      body: NowPlayingBody(
        groupId: groupId,
        onDismiss: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
