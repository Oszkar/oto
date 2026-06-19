import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/oto_colors.dart';

/// A single icon, resolved by [name] from one of two sources:
///
/// - Custom oto glyphs (`speaker`, `speakers`, `soundbar`, `group`) ship as
///   bundled SVGs under `assets/icons/` and render via [SvgPicture], tinted to
///   [color] with a `srcIn` blend.
/// - Standard glyphs map to the curated [_lucide] table of
///   `lucide_icons_flutter` members and render as a Material [Icon].
///
/// An unknown name trips an assert in debug and falls back to a loud
/// help-outline glyph so a missing mapping surfaces during screen work rather
/// than silently rendering nothing.
class OtoIcon extends StatelessWidget {
  const OtoIcon(this.name, {super.key, this.size, this.color});

  /// Icon name: a custom glyph name or a key into the [_lucide] map.
  final String name;

  /// Side length in logical px. Defaults to [_defaultSize].
  final double? size;

  /// Glyph color. Defaults to `context.oto.ink2`.
  final Color? color;

  /// Default glyph size — a sensible inline-icon size; no token fits exactly.
  static const double _defaultSize = 20;

  /// Custom oto glyphs that resolve to bundled SVGs under `assets/icons/`.
  static const Set<String> _custom = {
    'speaker',
    'speakers',
    'soundbar',
    'group',
  };

  /// Standard glyph names mapped to verified `lucide_icons_flutter` members.
  /// Curated to the v0.6.0 screen needs; over-mapping a few is fine.
  static const Map<String, IconData> _lucide = {
    'play': LucideIcons.play,
    'pause': LucideIcons.pause,
    'next': LucideIcons.skipForward,
    'prev': LucideIcons.skipBack,
    'volume': LucideIcons.volume2,
    'volumeMute': LucideIcons.volumeX,
    'settings': LucideIcons.settings,
    'chevronDown': LucideIcons.chevronDown,
    'chevronLeft': LucideIcons.chevronLeft,
    'chevronRight': LucideIcons.chevronRight,
    'link': LucideIcons.link,
    'check': LucideIcons.check,
    'more': LucideIcons.moreHorizontal,
    'search': LucideIcons.search,
    'plus': LucideIcons.plus,
    'moon': LucideIcons.moon,
    'layoutGrid': LucideIcons.layoutGrid,
    'list': LucideIcons.list,
    'music': LucideIcons.music,
    'x': LucideIcons.x,
  };

  @override
  Widget build(BuildContext context) {
    final s = size ?? _defaultSize;
    final c = color ?? context.oto.ink2;

    if (_custom.contains(name)) {
      return SvgPicture.asset(
        'assets/icons/$name.svg',
        width: s,
        height: s,
        colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      );
    }

    final glyph = _lucide[name];
    if (glyph != null) {
      return Icon(glyph, size: s, color: c);
    }

    assert(false, 'OtoIcon: unknown name "$name"');
    return Icon(Icons.help_outline, size: s, color: c);
  }
}
