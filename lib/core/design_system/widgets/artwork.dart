import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Network artwork decoded at *display* size (not source size): a 1000px cover
/// shown at 56dp costs ~50KB of RAM instead of ~4MB.
class Artwork extends StatelessWidget {
  const Artwork({
    required this.url,
    required this.size,
    this.radius = Radii.mdAll,
    this.seed = 0,
    this.icon = Icons.music_note_rounded,
    super.key,
  });

  final String? url;
  final double size;
  final BorderRadius radius;

  /// Picks the placeholder colour so empty covers still look designed.
  final int seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(size: size, seed: seed, icon: icon);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox.square(
        dimension: size,
        child: url == null || url!.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url!,
                memCacheWidth: (size * dpr).round(),
                fit: BoxFit.cover,
                fadeInDuration: Motion.fast,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.seed, required this.icon});

  final double size;
  final int seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SynkPalette.identityColor(seed),
      child: Center(
        child: Icon(icon, size: size * 0.38, color: Colors.white.withValues(alpha: 0.9)),
      ),
    );
  }
}

/// Soft, blurred wash of the current artwork behind a screen.
///
/// Decodes the image at 48px and upscales with a blur, so the effect costs
/// ~9KB of texture memory regardless of screen size.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({required this.url, required this.child, super.key});

  final String? url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url!.isNotEmpty)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
              child: Opacity(
                opacity: 0.55,
                child: CachedNetworkImage(
                  imageUrl: url!,
                  memCacheWidth: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        // Flat veil (no fade) keeps text readable over any artwork.
        ColoredBox(color: bg.withValues(alpha: 0.8)),
        child,
      ],
    );
  }
}
