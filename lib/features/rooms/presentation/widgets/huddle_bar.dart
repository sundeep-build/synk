import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../application/huddle_controller.dart';
import '../../application/huddle_state.dart';
import '../../domain/huddle_models.dart';
import '../huddle_view.dart';
import 'huddle_widgets.dart';

/// Room header button: starts (joins) the room's huddle, or opens it.
class HuddleHeaderButton extends ConsumerWidget {
  const HuddleHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(huddleProvider.select((s) => s.phase));
    final live = phase == HuddlePhase.live;
    return IconButton(
      tooltip: live ? 'Open huddle' : 'Start a huddle',
      isSelected: live,
      icon: const Icon(Icons.headset_mic_outlined),
      selectedIcon: Icon(Icons.headset_mic_rounded, color: context.colors.primary),
      onPressed: switch (phase) {
        HuddlePhase.joining => null,
        HuddlePhase.live => () => showHuddleView(context),
        HuddlePhase.idle => () => _join(context, ref),
      },
    );
  }
}

Future<void> _join(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  return runHuddleAction(context, ref.read(huddleProvider.notifier).join);
}

/// Strip under the room header, shown while anyone is in the huddle: who's
/// in it and a Join button, or your call controls once you've joined.
class HuddleBar extends ConsumerWidget {
  const HuddleBar({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(huddleProvider.select((s) => s.roomId == roomId ? s.phase : HuddlePhase.idle));
    final members = ref.watch(huddleMembersProvider(roomId).select((a) => a.value ?? const <HuddleMember>[]));
    if (phase == HuddlePhase.idle && members.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
      child: GlassPanel(
        radius: Radii.lgAll,
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
        // A floor, not a fixed height: large text sizes grow the strip
        // instead of overflowing it.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: phase == HuddlePhase.live
              ? _LiveRow(members: members)
              : _JoinRow(members: members, joining: phase == HuddlePhase.joining),
        ),
      ),
    );
  }
}

class _JoinRow extends ConsumerWidget {
  const _JoinRow({required this.members, required this.joining});

  final List<HuddleMember> members;
  final bool joining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = members.length;
    return Row(
      children: [
        Icon(Icons.headset_mic_rounded, color: context.colors.primary),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Huddle', style: context.text.titleSmall),
              Text(
                joining ? 'Connecting…' : (n == 1 ? '${members.first.name} is talking' : '$n people talking'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: context.synk.textSecondary),
              ),
            ],
          ),
        ),
        if (n > 0) ...[
          AvatarStack(avatars: [for (final m in members) (emoji: m.emoji, colorIndex: m.color)], size: 26),
          const SizedBox(width: Space.sm),
        ],
        FilledButton(
          onPressed: joining ? null : () => _join(context, ref),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          child: joining
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Join'),
        ),
      ],
    );
  }
}

class _LiveRow extends ConsumerWidget {
  const _LiveRow({required this.members});

  final List<HuddleMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (mic, cam) = ref.watch(huddleProvider.select((s) => (s.mic, s.cam)));
    final huddle = ref.read(huddleProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Open huddle, ${members.length} ${members.length == 1 ? 'person' : 'people'}',
            child: InkWell(
              borderRadius: Radii.mdAll,
              onTap: () => showHuddleView(context),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: members.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 2),
                        itemBuilder: (_, i) => Center(child: HuddleBubble(member: members[i])),
                      ),
                    ),
                  ),
                  Icon(Icons.open_in_full_rounded, size: 18, color: context.synk.textSecondary),
                  const SizedBox(width: Space.sm),
                ],
              ),
            ),
          ),
        ),
        HuddleControl(
          size: 40,
          icon: mic ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: mic ? 'Mute' : 'Unmute',
          on: mic,
          onPressed: () => runHuddleAction(context, huddle.toggleMic),
        ),
        const SizedBox(width: Space.xs),
        HuddleControl(
          size: 40,
          icon: cam ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          label: cam ? 'Turn camera off' : 'Turn camera on',
          on: cam,
          onPressed: () async {
            await runHuddleAction(context, huddle.toggleCamera);
            // Turning the camera on from the strip shows you the view.
            if (context.mounted && ref.read(huddleProvider).cam && !cam) await showHuddleView(context);
          },
        ),
        const SizedBox(width: Space.xs),
        HuddleControl(
          size: 40,
          icon: Icons.call_end_rounded,
          label: 'Leave huddle',
          danger: true,
          onPressed: () => runHuddleAction(context, huddle.leave),
        ),
      ],
    );
  }
}
