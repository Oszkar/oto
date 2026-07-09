import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/breakpoints.dart';
import '../../state/selected_source.dart';
import '../group/group_editor_screen.dart';
import '../now_playing/now_playing_screen.dart';
import '../room/room_detail_screen.dart';
import '../settings/settings_screen.dart';

/// Open a group's Now Playing. Wide: select it into the detail pane. Phone:
/// push the full-screen route (today's behavior).
void openSource(BuildContext context, WidgetRef ref, String groupId) {
  ref.read(selectedSourceProvider.notifier).select(groupId);
  if (!context.isWide) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingScreen(groupId: groupId),
      ),
    );
  }
}

/// Open a solo room. Wide: select its group into the pane (Room-detail is folded
/// away on wide, that is Task 7). Phone: push RoomDetailScreen.
void openRoom(
  BuildContext context,
  WidgetRef ref, {
  required String speakerId,
  required String? groupId,
}) {
  if (groupId != null) {
    ref.read(selectedSourceProvider.notifier).select(groupId);
  }
  if (!context.isWide) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomDetailScreen(speakerId: speakerId),
      ),
    );
  }
}

/// Open Settings. Wide: a centered dialog. Phone: push the full-screen route.
Future<void> openSettings(BuildContext context) {
  if (context.isWide) {
    return _showPaneDialog(
      context,
      (dismiss) => SettingsBody(onDismiss: dismiss),
    );
  }
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
}

/// Open the Group editor hosted by [hostId]. Wide: a centered dialog. Phone:
/// push the full-screen route.
Future<void> openGroupEditor(BuildContext context, String hostId) {
  if (context.isWide) {
    return _showPaneDialog(
      context,
      (dismiss) => GroupEditorBody(hostId: hostId, onDismiss: dismiss),
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GroupEditorScreen(hostId: hostId)),
  );
}

/// A centered, size-constrained dialog hosting a chrome-free `*Body`. The body
/// is built with a `dismiss` callback that pops THIS dialog.
Future<void> _showPaneDialog(
  BuildContext context,
  Widget Function(VoidCallback dismiss) body,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
        child: body(() => Navigator.of(ctx).pop()),
      ),
    ),
  );
}
