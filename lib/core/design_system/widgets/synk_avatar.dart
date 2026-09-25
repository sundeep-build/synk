import 'package:flutter/material.dart';

import '../synk_colors.dart';
import '../tokens.dart';
import 'cartoon_avatar.dart';

/// Generated avatar: a cartoon character (`c:<n>`, see [CartoonAvatar]) or an
/// emoji, on a solid identity colour. Zero uploads, zero storage cost,
/// identical on every device — ideal for the free tier.
class SynkAvatar extends StatelessWidget {
  const SynkAvatar({required this.emoji, required this.colorIndex, this.size = 40, this.ring = false, super.key});

  final String emoji;
  final int colorIndex;
  final double size;

  /// Highlights hosts / Pro members.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final cartoon = CartoonAvatar.indexOf(emoji);
    final Widget avatar = cartoon != null
        ? CartoonAvatar(index: cartoon, background: SynkPalette.identityColor(colorIndex), size: size)
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SynkPalette.identityColor(colorIndex)),
            child: Text(emoji, style: TextStyle(fontSize: size * 0.46, height: 1)),
          );
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: context.synk.brand),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.synk.background),
        child: avatar,
      ),
    );
  }
}

/// Overlapping avatars + "+N" overflow, e.g. room listeners.
class AvatarStack extends StatelessWidget {
  const AvatarStack({required this.avatars, this.total, this.size = 28, this.max = 4, super.key});

  final List<({String emoji, int colorIndex})> avatars;
  final int? total;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = avatars.take(max).toList();
    final overflow = (total ?? avatars.length) - shown.length;
    final step = size * 0.62;
    final count = shown.length + (overflow > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    final border = context.synk.background;

    Widget ringed(Widget child) => Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
      ),
      child: child,
    );

    return SizedBox(
      height: size + 4,
      width: step * (count - 1) + size + 4,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: ringed(SynkAvatar(emoji: shown[i].emoji, colorIndex: shown[i].colorIndex, size: size)),
            ),
          if (overflow > 0)
            Positioned(
              left: step * shown.length,
              child: ringed(
                Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: context.synk.surfaceOverlay),
                  child: Text(
                    '+${overflow > 99 ? 99 : overflow}',
                    style: context.text.labelSmall?.copyWith(fontSize: size * 0.34),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
