import 'dart:ui';

import 'package:flutter/material.dart';

import '../synk_colors.dart';
import '../tokens.dart';

/// Frosted surface. Real blur ([blur] = true) costs a save-layer per frame, so
/// it's reserved for a few floating chrome elements (nav bar, mini player).
/// Everything else gets the translucent fill + hairline border look for free.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.blur = false,
    this.radius = Radii.lgAll,
    this.padding,
    this.color,
    super.key,
  });

  final Widget child;
  final bool blur;
  final BorderRadius radius;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.glassFill,
        borderRadius: radius,
        border: Border.all(color: c.glassBorder, width: 0.8),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (!blur) return panel;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: panel),
    );
  }
}
