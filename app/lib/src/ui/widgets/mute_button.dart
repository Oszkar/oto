import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'oto_icon.dart';

/// The mute toggle: the volume glyph that already led every volume row, made
/// interactive. Tapping flips mute for whatever the row controls - a room
/// (`PlaybackController.setMute`) or a group master
/// (`GroupingController.setGroupMute`).
///
/// [size] is the glyph size, so each row keeps its own visual weight; the tap
/// target is always at least [Sizes.touchTarget44] via transparent hit-slop.
/// A null [muted] means no mute value has been observed yet (the field is
/// event-fed) and renders as unmuted.
class MuteButton extends StatelessWidget {
  const MuteButton({
    super.key,
    required this.muted,
    required this.enabled,
    required this.size,
    required this.color,
    required this.label,
    required this.onToggle,
  });

  /// Current mute state; null when never observed.
  final bool? muted;

  /// Whether the target can be commanded (false for an unreachable room).
  final bool enabled;

  /// Glyph size in logical px - matches the static icon this replaced.
  final double size;

  /// Glyph colour - matches the static icon this replaced.
  final Color color;

  /// What is being muted, for the tooltip and the semantic label.
  final String label;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isMuted = muted ?? false;
    final action = isMuted ? 'Unmute $label' : 'Mute $label';
    // The tooltip alone gives the node a `tooltip` property but no accessible
    // NAME, so a screen reader has nothing to announce the control by. Label it
    // explicitly, matching how the Home header's gear button pairs a Tooltip
    // with a Semantics label.
    return Semantics(
      label: action,
      button: true,
      child: IconButton(
        tooltip: action,
        onPressed: enabled ? onToggle : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: Sizes.touchTarget44,
          minHeight: Sizes.touchTarget44,
        ),
        icon: OtoIcon(
          isMuted ? 'volumeMute' : 'volume',
          size: size,
          color: color,
        ),
      ),
    );
  }
}
