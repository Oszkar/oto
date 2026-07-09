import 'package:flutter/material.dart';

import '../../theme/oto_colors.dart';
import '../../theme/tokens.dart';
import 'oto_icon.dart';

/// Square album artwork loaded from [uri], rounded to [Radius_.art10].
///
/// When [uri] is null, fails to load, or is still loading, a token-styled
/// placeholder fills the frame: an [OtoColors.fill] background with a muted
/// music glyph. The placeholder carries the `album-art-placeholder` key so it
/// is findable in tests.
class AlbumArt extends StatelessWidget {
  const AlbumArt(this.uri, {super.key, this.size});

  /// Image URL, or null to show the placeholder.
  final String? uri;

  /// Side length in logical px. Defaults to [_defaultSize].
  final double? size;

  /// Default artwork size - a comfortable thumbnail; no token fits exactly.
  static const double _defaultSize = 56;

  @override
  Widget build(BuildContext context) {
    final s = size ?? _defaultSize;
    final radius = BorderRadius.circular(Radius_.art10);

    final Widget child;
    if (uri == null) {
      child = _placeholder(context, s);
    } else {
      child = Image.network(
        uri!,
        width: s,
        height: s,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context, s),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _placeholder(context, s);
        },
      );
    }

    return ClipRRect(borderRadius: radius, child: child);
  }

  Widget _placeholder(BuildContext context, double s) {
    return Container(
      key: const Key('album-art-placeholder'),
      width: s,
      height: s,
      color: context.oto.fill,
      alignment: Alignment.center,
      child: OtoIcon('music', size: s * 0.4, color: context.oto.inkFaint),
    );
  }
}
