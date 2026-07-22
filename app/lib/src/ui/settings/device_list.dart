import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/household.dart';
import '../../state/model/group_state.dart';
import '../../state/model/room_state.dart';
import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import 'settings_section.dart';

class DeviceList extends ConsumerWidget {
  const DeviceList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);
    final rooms = household.rooms.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (rooms.isEmpty) {
      return const SettingsSection(
        title: 'Devices',
        child: SettingsRow(
          icon: 'speakers',
          label: 'No devices',
          subtitle: 'Scan the network from Home to discover speakers.',
          last: true,
        ),
      );
    }

    return SettingsSection(
      title: 'Devices',
      child: Column(
        children: [
          for (final (index, room) in rooms.indexed)
            DeviceRow(
              room: room,
              group: room.groupId == null
                  ? null
                  : household.groups[room.groupId],
              last: index == rooms.length - 1,
            ),
        ],
      ),
    );
  }
}

class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.room,
    required this.group,
    required this.last,
  });

  final RoomState room;
  final GroupState? group;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: room.kind == RoomKind.soundbar ? 'soundbar' : 'speaker',
      label: room.name,
      subtitle: room.model ?? 'Speaker',
      trailing: _StatusPill(label: _statusLabel, danger: !room.online),
      last: last,
    );
  }

  String get _statusLabel {
    if (!room.online) return 'Unreachable';

    final group = this.group;
    if (group == null || group.memberIds.length <= 1) return 'Standalone';

    return '${group.memberIds.length} rooms';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.danger = false});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final oto = context.oto;
    final color = danger ? oto.danger : oto.inkMute;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md8,
        vertical: Space.xs4,
      ),
      decoration: BoxDecoration(
        color: danger ? oto.danger.withValues(alpha: 0.10) : oto.fill,
        borderRadius: BorderRadius.circular(Radius_.pill999),
      ),
      child: Text(label, style: TextStyles.micro.copyWith(color: color)),
    );
  }
}
