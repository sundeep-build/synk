import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/utils/formatters.dart';
import '../../catalog/domain/track.dart';
import '../application/player_providers.dart';

/// Progress bar isolated in its own widget: it's the only thing that rebuilds
/// at position-tick rate, so the rest of the screen stays still.
class PlayerProgress extends ConsumerStatefulWidget {
  const PlayerProgress({required this.track, this.onSeek, super.key});

  final Track track;

  /// Null → read-only (e.g. listeners in a room).
  final ValueChanged<Duration>? onSeek;

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

    return Column(
      children: [
        SizedBox(
          height: 24,
          child: widget.onSeek == null
              ? Center(
                  child: ClipRRect(
                    borderRadius: Radii.pillAll,
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      backgroundColor: c.glassBorder,
                      color: c.textPrimary,
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
        ),
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
