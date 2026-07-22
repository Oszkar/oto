import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/nav.dart';
import '../widgets/oto_icon.dart';

/// The room options kebab: "Group rooms" (opens the group editor, hosted by the
/// group's coordinator) and, for a room that is in a multi-room group,
/// "Ungroup" (removes THIS room from it).
///
/// Lives in its own file because two hosts render it. The phone's Room detail
/// header owns it, and on wide the Now Playing pane header does - v0.6.3 folded
/// Room detail away on wide, which took the kebab with it and left a solo room
/// with no join/leave affordance at all short of resizing the window (#129).
///
/// A room inside a multi-room group is ungrouped through the group card's own
/// "Group options" kebab, which opens the same editor as a dialog on wide.
class RoomOptionsButton extends ConsumerWidget {
  const RoomOptionsButton({
    super.key,
    required this.speakerId,
    required this.hostId,
    required this.memberCount,
  });

  final String speakerId;

  /// The group's coordinator - the editor host. For a solo room this equals
  /// speakerId; for a grouped member it is the real coordinator (not this room).
  final String hostId;

  final int memberCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: Key('room-kebab-$speakerId'),
      tooltip: 'Room options',
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
          openGroupEditor(context, hostId);
        },
        // Ungroup removes THIS room from its group, so it targets speakerId
        // (not the coordinator).
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
              title: Text(
                'Ungroup',
                style: TextStyles.body.copyWith(color: oto.danger),
              ),
              onTap: onUngroup,
            ),
          const SizedBox(height: Space.md8),
        ],
      ),
    );
  }
}
