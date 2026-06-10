import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../state/model/source.dart';
import '../../state/model/track.dart';
import '../../state/sources.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/oto_icon.dart';

/// The adaptive now-playing strip at the bottom of Home. Ported from the
/// design-system `V3BottomStrip`. Driven entirely by [sourcesProvider]
/// (one [Source] per active group), it adapts to the number of sources:
///
/// - **0 sources** -> nothing ([SizedBox.shrink]).
/// - **1 source** -> a single floating mini-player.
/// - **2+ sources** -> a floating upward stack of rows, ONE per source,
///   uncapped (the JSX `+N more · manage all` cap is dropped per the v0.6
///   spec — every active source gets a row).
///
/// A row tap (the body, not the play button) routes through the injected
/// [onTapSource] callback. This widget never references the Now Playing
/// screen; Task 11b wires the real `Navigator.push` via [onTapSource], which
/// keeps the strip isolation-testable.
///
/// Backend-true omissions vs the JSX: no prev/next transport (no skip in
/// scope), and the multi-source collapse header (`N sources playing` +
/// chevron-down) is dropped — it is an inert affordance with no backend state
/// to drive.
class BottomStrip extends ConsumerWidget {
  const BottomStrip({super.key, required this.onTapSource});

  /// Invoked with a row's [Source] when its body (not the play button) is
  /// tapped. Task 11b injects the Now Playing navigation here.
  final void Function(Source) onTapSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    if (sources.isEmpty) return const SizedBox.shrink();

    final oto = context.oto;

    if (sources.length == 1) {
      final source = sources.first;
      // Single source: one floating pill (radius 14 per JSX), the stack
      // generalized down to a single row.
      return Padding(
        // JSX margin `0 12px 14px`.
        padding: const EdgeInsets.fromLTRB(
          Space.gutter12,
          0,
          Space.gutter12,
          Space.card14,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: oto.elevated,
            border: Border.all(color: oto.line),
            borderRadius: BorderRadius.circular(14),
            boxShadow: Elevation.float,
          ),
          clipBehavior: Clip.antiAlias,
          child: _SourceRow(source: source, onTap: () => onTapSource(source)),
        ),
      );
    }

    // 2+ sources: the floating bar grows UPWARD into a stack — one row per
    // active source, uncapped. Radius 16 per JSX.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter12,
        0,
        Space.gutter12,
        Space.card14,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: oto.elevated,
          border: Border.all(color: oto.line),
          borderRadius: BorderRadius.circular(Radius_.card16),
          boxShadow: Elevation.floatLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < sources.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: oto.line),
              _SourceRow(
                source: sources[i],
                onTap: () => onTapSource(sources[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One source row inside the strip: album art + label + track title, a row-body
/// tap target ([onTap]), and an independent play/pause button. Resolves the
/// group's transport from [householdProvider] so the glyph reflects live state
/// (a [Source] carries no transport).
class _SourceRow extends ConsumerWidget {
  const _SourceRow({required this.source, required this.onTap});

  final Source source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oto = context.oto;
    final transport = ref.watch(
      householdProvider.select((h) => h.groups[source.id]?.transport),
    );
    // A source is controllable only if its coordinator is reachable. If the
    // coordinator drops offline mid-stream the group still looks active (stale
    // track/transport survives a SubscriptionError), so dim + disable the row
    // rather than offer dead controls for an unreachable speaker.
    final coordinatorOnline = ref.watch(
      householdProvider.select((h) {
        final g = h.groups[source.id];
        return g == null ? true : (h.rooms[g.coordinatorId]?.online ?? true);
      }),
    );
    final playing = transport == PlaybackState.playing;
    final track = source.track;

    // The InkWell is the row-body tap target. The play IconButton sits inside
    // it but absorbs its own taps, so tapping play toggles playback WITHOUT
    // firing the row tap.
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: coordinatorOnline ? 1 : 0.55,
        child: Padding(
          // JSX row inset `8px 10px 8px 12px`.
          padding: const EdgeInsets.fromLTRB(
            Space.gutter12,
            Space.md8,
            Space.lg10,
            Space.md8,
          ),
          child: Row(
            children: [
              AlbumArt(track?.artUri, size: 40),
              const SizedBox(width: Space.gutter12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ?? 'Playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.label,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (source.memberCount > 1) ...[
                          OtoIcon('link', size: 10, color: oto.inkMute),
                          const SizedBox(width: Space.xs4),
                        ],
                        Flexible(
                          child: Text(
                            _subtitle(track, source.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.caption.copyWith(
                              color: oto.inkMute,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md8),
              IconButton(
                key: Key('strip-play-${source.id}'),
                onPressed: coordinatorOnline
                    ? () => ref
                          .read(playbackControllerProvider)
                          .togglePlay(
                            source.id,
                            transport ?? PlaybackState.paused,
                          )
                    : null,
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
              const SizedBox(width: Space.xs4),
              // Decorative affordance: the row body taps through to Now Playing.
              OtoIcon('chevronRight', size: 12, color: oto.inkFaint),
            ],
          ),
        ),
      ),
    );
  }

  /// "Artist · Label" when an artist is known, else just the source label.
  String _subtitle(Track? track, String label) {
    final artist = track?.artist;
    return artist != null ? '$artist · $label' : label;
  }
}
