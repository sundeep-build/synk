import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/room_providers.dart';

/// Floating emoji reactions (IG-Live style). Bounded: at most [maxBursts]
/// animations exist at once, each disposed as soon as it finishes.
class ReactionLayer extends ConsumerStatefulWidget {
  const ReactionLayer({required this.roomId, required this.myUid, super.key});

  final String roomId;
  final String myUid;

  static const maxBursts = 14;

  @override
  ConsumerState<ReactionLayer> createState() => ReactionLayerState();
}

class ReactionLayerState extends ConsumerState<ReactionLayer> {
  final List<({int id, String emoji, double dx})> _bursts = [];
  final math.Random _random = math.Random();
  int _nextId = 0;

  void spawn(String emoji) {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    setState(() {
      if (_bursts.length >= ReactionLayer.maxBursts) _bursts.removeAt(0);
      _bursts.add((id: _nextId++, emoji: emoji, dx: _random.nextDouble() * 48));
    });
  }

  void _remove(int id) {
    if (mounted) setState(() => _bursts.removeWhere((b) => b.id == id));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roomReactionsProvider(widget.roomId), (_, next) {
      // Only fresh reactions: a re-opening stream still carries the last one.
      if (next is! AsyncData) return;
      final r = next.value;
      // Our own taps were already spawned locally.
      if (r != null && r.uid != widget.myUid) spawn(r.emoji);
    });

    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (_, constraints) => Stack(
            clipBehavior: Clip.none,
            children: [
              for (final b in _bursts)
                _FloatingEmoji(
                  key: ValueKey(b.id),
                  emoji: b.emoji,
                  dx: b.dx,
                  rise: constraints.maxHeight * 0.75,
                  onDone: () => _remove(b.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  const _FloatingEmoji({required this.emoji, required this.dx, required this.rise, required this.onDone, super.key});

  final String emoji;
  final double dx;
  final double rise;
  final VoidCallback onDone;

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder is a component widget, so Positioned still reaches the
    // Stack as its parent-data target.
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOut.transform(_c.value);
        final sway = math.sin(_c.value * math.pi * 3) * 14;
        final scale = _c.value < 0.15 ? 0.6 + _c.value / 0.15 * 0.6 : 1.2 - _c.value * 0.3;
        return Positioned(
          right: 16 + widget.dx + sway,
          bottom: t * widget.rise,
          child: Opacity(
            opacity: (1 - _c.value * _c.value).clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Text(widget.emoji, style: const TextStyle(fontSize: 34)),
    );
  }
}
