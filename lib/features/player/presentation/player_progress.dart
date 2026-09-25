import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../catalog/domain/track.dart';
import '../application/player_providers.dart';

/// Progress bar isolated in its own widget: it's the only thing that rebuilds
/// at position-tick rate, so the rest of the screen stays still.
class PlayerProgress extends ConsumerStatefulWidget {
  const PlayerProgress({required this.track, this.onSeek, this.waveform = false, this.slim = false, super.key});

  final Track track;

  /// Null → read-only (e.g. listeners in a room).
  final ValueChanged<Duration>? onSeek;

  /// A waveform of bars instead of a slider (Now Playing). The bars are drawn
  /// from the track id, not decoded audio: a stable look that costs nothing.
  final bool waveform;

  /// One thin line with the times at either end (the room, where height is
  /// precious).
  final bool slim;

  @override
  ConsumerState<PlayerProgress> createState() => _PlayerProgressState();
}

class _PlayerProgressState extends ConsumerState<PlayerProgress> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    if (widget.track.isLive) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const LiveBadge(),
          const SizedBox(width: Space.sm),
          Text('Live broadcast', style: context.text.labelMedium?.copyWith(color: c.textSecondary)),
        ],
      );
    }

    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = widget.track.duration;
    final totalMs = total.inMilliseconds;
    final fraction = totalMs <= 0 ? 0.0 : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final value = _drag ?? fraction;
    final shown = _drag == null ? position : total * value;
    final labels = context.text.labelSmall?.copyWith(
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final Widget bar;
    if (widget.waveform) {
      bar = _Waveform(
        seed: widget.track.id.hashCode,
        value: value,
        played: context.colors.tertiary,
        idle: c.textMuted.withValues(alpha: 0.45),
        head: c.textPrimary,
        onDrag: widget.onSeek == null ? null : (v) => setState(() => _drag = v),
        onDragEnd: widget.onSeek == null
            ? null
            : (v) {
                widget.onSeek!(total * v);
                setState(() => _drag = null);
              },
      );
    } else {
      bar = SizedBox(
        height: 24,
        child: widget.onSeek == null
            ? Center(
                child: ClipRRect(
                  borderRadius: Radii.pillAll,
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: widget.slim ? 3 : 4,
                    backgroundColor: c.glassBorder,
                    color: context.colors.tertiary,
                  ),
                ),
              )
            : Slider(
                value: value,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  widget.onSeek!(total * v);
                  setState(() => _drag = null);
                },
              ),
      );
    }

    if (widget.slim) {
      return Semantics(
        slider: true,
        value: '${Formatters.duration(shown)} of ${Formatters.duration(total)}',
        child: Row(
          children: [
            Text(Formatters.duration(shown), style: labels),
            const SizedBox(width: Space.sm),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(
                  context,
                ).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
                child: bar,
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(Formatters.duration(total), style: labels),
          ],
        ),
      );
    }

    return Column(
      children: [
        Semantics(slider: true, value: '${Formatters.duration(shown)} of ${Formatters.duration(total)}', child: bar),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Text(Formatters.duration(shown), style: labels),
            const Spacer(),
            Text(Formatters.duration(total), style: labels),
          ],
        ),
      ],
    );
  }
}

/// Bars that light up as the song plays; drag or tap to seek.
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seed,
    required this.value,
    required this.played,
    required this.idle,
    required this.head,
    this.onDrag,
    this.onDragEnd,
  });

  final int seed;
  final double value;
  final Color played;
  final Color idle;
  final Color head;
  final ValueChanged<double>? onDrag;
  final ValueChanged<double>? onDragEnd;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        double at(Offset local) => (local.dx / box.maxWidth).clamp(0.0, 1.0);
        final seekable = onDrag != null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: seekable ? (d) => onDrag!(at(d.localPosition)) : null,
          onHorizontalDragEnd: seekable ? (_) => onDragEnd!(value) : null,
          onTapUp: seekable ? (d) => onDragEnd!(at(d.localPosition)) : null,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(box.maxWidth, height),
              painter: _WaveformPainter(seed: seed, value: value, played: played, idle: idle, head: head),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.seed,
    required this.value,
    required this.played,
    required this.idle,
    required this.head,
  });

  final int seed;
  final double value;
  final Color played;
  final Color idle;
  final Color head;

  static const double _bar = 3;
  static const double _gap = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (_bar + _gap)).floor();
    if (count <= 0) return;
    final random = math.Random(seed);
    final playedPaint = Paint()..color = played;
    final idlePaint = Paint()..color = idle;
    final split = value * size.width;
    final mid = size.height / 2;
    for (var i = 0; i < count; i++) {
      // Louder in the middle of a song, with random texture on top.
      final shape = 0.35 + 0.65 * math.sin(math.pi * (i + 0.5) / count);
      final h = (size.height * 0.85) * (0.18 + 0.82 * shape * (0.35 + 0.65 * random.nextDouble()));
      final x = i * (_bar + _gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h / 2, _bar, h), const Radius.circular(_bar / 2)),
        x + _bar <= split ? playedPaint : idlePaint,
      );
    }
    canvas.drawRect(Rect.fromLTWH(split - 1, 0, 2, size.height), Paint()..color = head);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.value != value || old.seed != seed || old.played != played || old.idle != idle || old.head != head;
}
