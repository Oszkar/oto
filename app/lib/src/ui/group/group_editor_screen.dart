import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/commands.dart';
import '../../state/group_editor.dart';
import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../state/model/room_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import '../shell/oto_scaffold.dart';
import '../widgets/oto_icon.dart';

/// Full-screen group editor. Will be opened from the Home group bar (the
/// navigation entry point is wired in a later change); lets the user pick which
/// rooms join the host group. Ported from the design-system `V3Group`. No
/// Stereo-pair button (backend-true: oto has no stereo-pair API).
///
/// Selection state lives in [groupEditorSelectionProvider]. Save computes a
/// [MembershipDiff] and fires [GroupingController.joinGroup] /
/// [GroupingController.leaveGroup] per the diff, then pops. Ungroup-all leaves
/// every non-host current member, then pops.
class GroupEditorScreen extends ConsumerWidget {
  const GroupEditorScreen({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final selection = ref.watch(groupEditorSelectionProvider(hostId));

    // Resolve the host group so we know current members and the selection count.
    final hostGroupId = household.rooms[hostId]?.groupId;
    final hostGroup =
        hostGroupId == null ? null : household.groups[hostGroupId];
    final currentMembers = hostGroup?.memberIds.toSet() ?? {hostId};

    final conflicts = roomsWithConflict(
      household,
      host: hostId,
      selected: selection,
    );

    // Sort for a stable list: rooms.values follows map insertion order, which
    // can reshuffle across state updates. Sort by name, id as tie-breaker
    // (mirrors the Home screen's deterministic ordering).
    final roomList = household.rooms.values.toList()
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });

    return OtoScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            hostId: hostId,
            selectedCount: selection.length,
            onSave: () => _onSave(context, ref, currentMembers),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: roomList.length,
              itemBuilder: (context, i) {
                final room = roomList[i];
                return _RoomRow(
                  room: room,
                  hostId: hostId,
                  hostGroup: hostGroup,
                  selected: selection.contains(room.id),
                  hasConflict: conflicts.contains(room.id),
                  onTap: () => ref
                      .read(groupEditorSelectionProvider(hostId).notifier)
                      .toggle(room.id),
                );
              },
            ),
          ),
          _Footer(
            onUngroupAll: () => _onUngroupAll(context, ref, currentMembers),
          ),
        ],
      ),
    );
  }

  void _onSave(
    BuildContext context,
    WidgetRef ref,
    Set<String> currentMembers,
  ) {
    final selection = ref.read(groupEditorSelectionProvider(hostId));
    final diff = diffMembership(
      host: hostId,
      currentMembers: currentMembers,
      selected: selection,
    );
    // Fire-and-forget, matching the app's command pattern: GroupingController
    // owns the async lifecycle (retry + topology reconcile), so the editor
    // dispatches every join/leave and pops immediately rather than blocking on
    // each SOAP round-trip. Reading the controller also initializes the test
    // spy even on a no-op save.
    final grouping = ref.read(groupingControllerProvider);
    for (final room in diff.toJoin) {
      grouping.joinGroup(room, hostId);
    }
    for (final room in diff.toLeave) {
      grouping.leaveGroup(room);
    }
    Navigator.of(context).maybePop();
  }

  void _onUngroupAll(
    BuildContext context,
    WidgetRef ref,
    Set<String> currentMembers,
  ) {
    final grouping = ref.read(groupingControllerProvider);
    for (final member in currentMembers) {
      if (member == hostId) continue;
      grouping.leaveGroup(member);
    }
    Navigator.of(context).maybePop();
  }
}

// ---------------------------------------------------------------------------
// Header: close button + centered title/subtitle + Save button
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.hostId,
    required this.selectedCount,
    required this.onSave,
  });

  final String hostId;
  final int selectedCount;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return Padding(
      // JSX: `4px 18px 14px` with items centered.
      padding: const EdgeInsets.fromLTRB(
        Space.xs4,
        Space.xs4,
        Space.screen18,
        Space.card14,
      ),
      child: Row(
        children: [
          IconButton(
            key: Key('group-close-$hostId'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: OtoIcon('x', size: 17, color: oto.ink2),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Group rooms',
                  style: TextStyles.titleCard.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 15 * -0.01,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$selectedCount selected',
                  style: TextStyles.caption.copyWith(
                    fontSize: 11,
                    color: oto.inkMute,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('group-save'),
            onPressed: onSave,
            style: TextButton.styleFrom(
              backgroundColor: oto.accent,
              foregroundColor: oto.onAccent,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.card14,
                vertical: Space.md8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radius_.button12 - 2),
              ),
              textStyle: TextStyles.label.copyWith(fontSize: 13),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One room row: checkbox + icon + name (+ HOST badge) + sub-line
// ---------------------------------------------------------------------------

class _RoomRow extends StatelessWidget {
  const _RoomRow({
    required this.room,
    required this.hostId,
    required this.hostGroup,
    required this.selected,
    required this.hasConflict,
    required this.onTap,
  });

  final RoomState room;
  final String hostId;

  /// The host's current group (null when the host has no group yet).
  final GroupState? hostGroup;

  final bool selected;
  final bool hasConflict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    final isHost = room.id == hostId;

    // Sub-line text and color.
    final String subText;
    final Color subColor;
    if (hasConflict) {
      subText = 'Will stop current playback';
      subColor = oto.danger;
    } else {
      // Room is currently a member of the host group when the group exists and
      // contains this room.
      final members = hostGroup?.memberIds ?? <String>[];
      final isCurrentMember = members.contains(room.id);
      if (isCurrentMember && !isHost) {
        subText = 'Currently grouped';
        subColor = oto.inkMute;
      } else if (isHost) {
        subText = 'Hosting';
        subColor = oto.inkMute;
      } else if (!room.online) {
        subText = 'Powered off';
        subColor = oto.inkMute;
      } else {
        subText = 'Idle';
        subColor = oto.inkMute;
      }
    }

    return GestureDetector(
      key: Key('group-row-${room.id}'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.screen18,
          Space.xs4,
          Space.screen18,
          Space.xs4,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.card14,
            vertical: Space.gutter12,
          ),
          decoration: BoxDecoration(
            color: selected ? oto.accentSoft : oto.surface,
            border: Border.all(
              color: selected ? oto.accent : oto.line,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(Radius_.card16 - 2),
          ),
          child: Row(
            children: [
              // Checkbox glyph: accent-filled when selected, outline when not.
              SizedBox(
                key: Key('group-check-${room.id}'),
                width: 20,
                height: 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? oto.accent : Colors.transparent,
                    border: Border.all(
                      color: selected ? oto.accent : oto.lineStrong,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(Radius_.xs4),
                  ),
                  child: selected
                      ? Center(
                          child: OtoIcon('check', size: 12, color: oto.onAccent),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: Space.gutter12),
              OtoIcon(
                room.kind == RoomKind.soundbar ? 'soundbar' : 'speaker',
                size: 18,
                color: oto.ink2,
              ),
              const SizedBox(width: Space.gutter12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.titleCard.copyWith(
                              fontWeight: isHost
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isHost) ...[
                          const SizedBox(width: Space.md8),
                          _HostBadge(oto: oto),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.caption.copyWith(
                        fontSize: 11.5,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostBadge extends StatelessWidget {
  const _HostBadge({required this.oto});

  final OtoColors oto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm6,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: oto.accent,
        borderRadius: BorderRadius.circular(Radius_.xs4),
      ),
      child: Text(
        'HOST',
        style: TextStyles.badge.copyWith(
          letterSpacing: 10.5 * 0.06,
          color: oto.onAccent,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer: Ungroup-all button (no Stereo-pair - backend-true)
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.onUngroupAll});

  final VoidCallback onUngroupAll;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: oto.surface,
        border: Border(top: BorderSide(color: oto.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.screen18,
          Space.gutter12,
          Space.screen18,
          Space.section22,
        ),
        child: OutlinedButton(
          key: const Key('group-ungroup-all'),
          onPressed: onUngroupAll,
          style: OutlinedButton.styleFrom(
            foregroundColor: oto.danger,
            side: BorderSide(color: oto.line),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter12,
              vertical: Space.lg10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radius_.button12 - 2),
            ),
            textStyle: TextStyles.label,
            minimumSize: const Size.fromHeight(0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Ungroup all'),
        ),
      ),
    );
  }
}
