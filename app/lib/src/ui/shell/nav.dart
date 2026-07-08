import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/breakpoints.dart';
import '../../state/selected_source.dart';
import '../now_playing/now_playing_screen.dart';
import '../room/room_detail_screen.dart';

/// Open a group's Now Playing. Wide: select it into the detail pane. Phone:
/// push the full-screen route (today's behavior).
void openSource(BuildContext context, WidgetRef ref, String groupId) {
  if (context.isWide) {
    ref.read(selectedSourceProvider.notifier).select(groupId);
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NowPlayingScreen(groupId: groupId)),
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
  if (context.isWide) {
    if (groupId != null) ref.read(selectedSourceProvider.notifier).select(groupId);
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RoomDetailScreen(speakerId: speakerId)),
    );
  }
}
