import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/selected_source.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import 'now_playing_screen.dart';
import '../widgets/oto_mark.dart';

/// The persistent wide detail pane. Renders the resolved source's Now Playing
/// body (no dismiss chevron), or a quiet placeholder when nothing is active.
class NowPlayingPane extends ConsumerWidget {
  const NowPlayingPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gid = ref.watch(resolvedSourceProvider);
    return ColoredBox(
      color: context.oto.surface,
      child: gid == null
          ? const _EmptyPane()
          : NowPlayingBody(groupId: gid), // onDismiss null -> no chevron
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane();

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Opacity(opacity: 0.4, child: OtoMark(40)),
          const SizedBox(height: Space.gutter12),
          Text(
            'Pick a room to control',
            style: TextStyles.body.copyWith(color: oto.inkMute),
          ),
        ],
      ),
    );
  }
}
