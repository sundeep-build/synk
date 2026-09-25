import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../synk_colors.dart';
import 'synk_avatar.dart';

/// A profile avatar (cartoon character or emoji) that dances to the music:
/// sways, bounces and squashes on every beat, with notes floating up. When
/// not [dancing] it idles with a small, slow sway. Honours "reduce motion".
///
/// Only a transform changes per frame; the avatar itself is painted once
/// (RepaintBoundary), so this stays cheap.
class DancingAvatar extends StatefulWidget {
  const DancingAvatar({
    required this.emoji,
    required this.colorIndex,
    this.size = 48,
    this.dancing = true,
    this.notes = true,
    this.ring = false,
    super.key,
  });

  final String emoji;
  final int colorIndex;
  final double size;
  final bool dancing;

  /// Notes rising beside it while it dances.
  final bool notes;
  final bool ring;

  @override
  State<DancingAvatar> createState() => _DancingAvatarState();
}

class _DancingAvatarState extends State<DancingAvatar> with SingleTickerProviderStateMixin {
  /// One loop = one beat while dancing (about 110 bpm), a slow breath idle.
  static const _beat = Duration(milliseconds: 545);
  static const _idle = Duration(milliseconds: 1800);

  late final AnimationController _c = AnimationController(vsync: this, duration: widget.dancing ? _beat : _idle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DancingAvatar old) {
    super.didUpdateWidget(old);
    if (old.dancing != widget.dancing) {
      _c.duration = widget.dancing ? _beat : _idle;
      if (_c.isAnimating) _c.repeat();
    }
    _sync();
  }

  void _sync() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final avatar = RepaintBoundary(
      child: SynkAvatar(emoji: widget.emoji, colorIndex: widget.colorIndex, size: size, ring: widget.ring),
    );
    final noteColor = context.colors.tertiary;
    return SizedBox.square(
      dimension: size,
      child: AnimatedBuilder(
        animation: _c,
        child: avatar,
        builder: (context, child) {
          final t = _c.value;
          final Matrix4 m;
          if (widget.dancing) {
            final hop = math.sin(math.pi * t).abs(); // 0 on the beat, 1 mid-air
            final squash = 1 - hop; // flattest as it lands
            m = Matrix4.identity()
              ..translateByDouble(0, -hop * size * 0.12, 0, 1)
              ..rotateZ(math.sin(2 * math.pi * t) * 0.16)
              ..scaleByDouble(1 + squash * 0.05, 1 - squash * 0.07, 1, 1);
          } else {
            m = Matrix4.identity()
              ..translateByDouble(0, math.sin(2 * math.pi * t) * size * 0.02, 0, 1)
              ..rotateZ(math.sin(2 * math.pi * t) * 0.05);
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Transform(transform: m, alignment: Alignment.bottomCenter, child: child),
              if (widget.dancing && widget.notes)
                for (final (phase, side) in [(0.0, 1.0), (0.5, -1.0)])
                  _Note(progress: (t + phase) % 1, side: side, size: size, color: noteColor),
            ],
          );
        },
      ),
    );
  }
}

/// A note drifting up and out, fading as it goes.
class _Note extends StatelessWidget {
  const _Note({required this.progress, required this.side, required this.size, required this.color});

  final double progress;
  final double side;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final noteSize = size * 0.34;
    return Positioned(
      left: size / 2 - noteSize / 2 + side * (size * 0.42 + math.sin(progress * math.pi * 2) * 3),
      top: size * 0.25 - progress * size * 0.7,
      child: Opacity(
        opacity: (1 - progress).clamp(0.0, 1.0),
        child: Icon(side > 0 ? Icons.music_note_rounded : Icons.audiotrack_rounded, size: noteSize, color: color),
      ),
    );
  }
}
