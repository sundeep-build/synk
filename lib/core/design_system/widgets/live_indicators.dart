import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../synk_colors.dart';
import '../tokens.dart';

/// Pulsing LIVE pill with optional listener count.
class LiveBadge extends StatefulWidget {
  const LiveBadge({this.count, this.compact = false, super.key});

  final int? count;
  final bool compact;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final label = widget.count == null ? 'LIVE' : 'LIVE · ${widget.count}';
    return Semantics(
      label: widget.count == null ? 'Live' : 'Live, ${widget.count} listening',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 10, vertical: 5),
        decoration: BoxDecoration(color: c.live, borderRadius: Radii.pillAll),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: FadeTransition(
                opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: SizedBox.square(dimension: 6),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: context.text.labelSmall?.copyWith(color: Colors.white, letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}

/// Animated equalizer bars. Stops its ticker entirely when [active] is false,
/// so idle lists cost nothing.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({this.active = true, this.color, this.size = 16, this.bars = 4, super.key});

  final bool active;
  final Color? color;
  final double size;
  final int bars;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _EqPainter(
            animation: _c,
            color: widget.color ?? context.colors.primary,
            bars: widget.bars,
            active: widget.active,
          ),
        ),
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter({required this.animation, required this.color, required this.bars, required this.active})
    : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final int bars;
  final bool active;

  static const _phases = [0.0, 1.7, 3.1, 4.4, 5.3];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final gap = size.width * 0.12;
    final w = (size.width - gap * (bars - 1)) / bars;
    for (var i = 0; i < bars; i++) {
      final t = animation.value * 2 * math.pi;
      final h = active
          ? size.height * (0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * (1 + i * 0.35) + _phases[i % 5])))
          : size.height * 0.3;
      final x = i * (w + gap);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, w, h), Radius.circular(w / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) => old.color != color || old.active != active || old.bars != bars;
}
