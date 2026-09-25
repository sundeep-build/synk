import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../application/huddle_controller.dart';
import '../application/huddle_state.dart';
import '../domain/huddle_models.dart';
import 'widgets/huddle_widgets.dart';

/// Full huddle: everyone's camera or avatar, and the call controls. A sheet
/// over the room, so the room keeps playing underneath.
Future<void> showHuddleView(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const HuddleView(),
);

class HuddleView extends ConsumerWidget {
  const HuddleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The huddle ended (left, or left the room): close.
    ref.listen(huddleProvider.select((s) => s.phase), (_, phase) {
      if (phase == HuddlePhase.idle) Navigator.of(context).maybePop();
    });
    final members = ref.watch(huddleProvider.select((s) => s.members));
    final myUid = ref.watch(huddleProvider.select((s) => s.myUid));
    // You first, then everyone else in join order.
    final ordered = [...members.where((m) => m.uid == myUid), ...members.where((m) => m.uid != myUid)];

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.xs, Space.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Huddle', style: context.text.headlineSmall),
                      Text(
                        ordered.length <= 1 ? 'Waiting for others to join' : '${ordered.length} people',
                        style: context.text.bodySmall?.copyWith(color: context.synk.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Minimise',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _TileGrid(members: ordered, myUid: myUid),
          ),
          const SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
            child: _Controls(),
          ),
        ],
      ),
    );
  }
}

/// One column for up to two people, two after that. Tiles shrink to fit the
/// screen until they'd get too small, then the grid scrolls; it builds only
/// the tiles on screen, so off-screen cameras hold no renderer.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.members, required this.myUid});

  final List<HuddleMember> members;
  final String? myUid;

  static const double _gap = Space.sm;
  static const double _minTileHeight = 160;

  @override
  Widget build(BuildContext context) {
    final n = members.length;
    if (n == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final cols = n <= 2 ? 1 : 2;
        final rows = (n / cols).ceil();
        final tileWidth = (box.maxWidth - Space.gutter * 2 - _gap * (cols - 1)) / cols;
        final fit = (box.maxHeight - _gap * (rows - 1)) / rows;
        final tileHeight = math.max(fit, _minTileHeight);
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemCount: n,
          itemBuilder: (_, i) =>
              HuddleTile(key: ValueKey(members[i].uid), member: members[i], isMe: members[i].uid == myUid),
        );
      },
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (mic, cam, speaker) = ref.watch(huddleProvider.select((s) => (s.mic, s.cam, s.speaker)));
    final huddle = ref.read(huddleProvider.notifier);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        HuddleControl(
          icon: mic ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: mic ? 'Mute' : 'Unmute',
          on: mic,
          onPressed: () => runHuddleAction(context, huddle.toggleMic),
        ),
        HuddleControl(
          icon: cam ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          label: cam ? 'Turn camera off' : 'Turn camera on',
          on: cam,
          onPressed: () => runHuddleAction(context, huddle.toggleCamera),
        ),
        if (cam)
          HuddleControl(
            icon: Icons.cameraswitch_rounded,
            label: 'Switch camera',
            onPressed: () => runHuddleAction(context, huddle.flipCamera),
          ),
        HuddleControl(
          icon: speaker ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
          label: speaker ? 'Use earpiece' : 'Use loudspeaker',
          onPressed: () => runHuddleAction(context, huddle.toggleSpeaker),
        ),
        HuddleControl(
          icon: Icons.call_end_rounded,
          label: 'Leave huddle',
          danger: true,
          onPressed: () => runHuddleAction(context, huddle.leave),
        ),
      ],
    );
  }
}
