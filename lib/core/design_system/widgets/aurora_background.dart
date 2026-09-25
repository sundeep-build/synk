import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Hero backdrop (welcome, room ended): a few large, flat, solid discs of the
/// brand colours drifting slowly — colour blocking, no gradients. One
/// CustomPainter + RepaintBoundary: no images, no blur filters.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: _AuroraPainter(_c, Theme.of(context).scaffoldBackgroundColor))),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.animation, this.background) : super(repaint: animation);

  final Animation<double> animation;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final t = animation.value * 2 * math.pi;
    final discs = [
      (SynkPalette.brand, 0.18, Offset(0.1 + 0.05 * math.sin(t), 0.12 + 0.03 * math.cos(t)), 0.55),
      (SynkPalette.cyan, 0.10, Offset(1.0 + 0.04 * math.cos(t * 1.3), 0.42 + 0.04 * math.sin(t)), 0.42),
      (SynkPalette.pink, 0.09, Offset(0.3 + 0.06 * math.sin(t * 0.7), 0.95 + 0.03 * math.cos(t * 1.1)), 0.5),
    ];
    for (final (color, alpha, center, radius) in discs) {
      canvas.drawCircle(
        Offset(center.dx * size.width, center.dy * size.height),
        radius * size.width,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.background != background;
}
