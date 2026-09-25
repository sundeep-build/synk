import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/design_system/design_system.dart';
import '../../application/huddle_controller.dart';
import '../../data/peer_link.dart';
import '../../domain/huddle_models.dart';

/// Runs a huddle action from a button and shows any failure as a snack.
Future<void> runHuddleAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) context.showError(e);
  }
}

/// Renders one video stream. The renderer (a GPU texture) exists only while
/// this widget is mounted, so it's shown only for cameras that are on.
class HuddleVideoSurface extends StatefulWidget {
  const HuddleVideoSurface({required this.stream, this.mirror = false, super.key});

  final MediaStream stream;
  final bool mirror;

  @override
  State<HuddleVideoSurface> createState() => _HuddleVideoSurfaceState();
}

class _HuddleVideoSurfaceState extends State<HuddleVideoSurface> {
  final _renderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) {
      if (!mounted) return;
      _renderer.srcObject = widget.stream;
      setState(() => _ready = true);
    });
  }

  @override
  void didUpdateWidget(HuddleVideoSurface old) {
    super.didUpdateWidget(old);
    if (_ready && old.stream.id != widget.stream.id) _renderer.srcObject = widget.stream;
  }

  @override
  void dispose() {
    if (_ready) _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: widget.mirror);
  }
}

/// One person in the huddle view: their camera, or their avatar, with a
/// ring while they talk.
class HuddleTile extends ConsumerWidget {
  const HuddleTile({required this.member, required this.isMe, super.key});

  final HuddleMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.synk;
    final uid = member.uid;
    final talking = ref.watch(huddleSpeakingProvider.select((s) => s.contains(uid)));
    final status = isMe ? PeerStatus.connected : ref.watch(huddleProvider.select((s) => s.peers[uid]));
    // Re-read streams when a connection is rebuilt.
    ref.watch(huddleProvider.select((s) => s.revision));
    final front = ref.watch(huddleProvider.select((s) => s.frontCamera));
    final controller = ref.read(huddleProvider.notifier);

    final stream = !member.cam
        ? null
        : isMe
        ? controller.localPreview
        : (status == PeerStatus.connected ? controller.remoteStream(uid) : null);

    return Semantics(
      label: [
        isMe ? 'You' : member.name,
        if (!member.mic) 'muted',
        if (talking) 'talking',
        if (status == PeerStatus.failed) "can't connect",
      ].join(', '),
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: Radii.lgAll,
          border: Border.all(color: talking ? c.online : c.glassBorder, width: talking ? 3 : 1),
        ),
        child: ClipRRect(
          borderRadius: Radii.lgAll,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (stream != null)
                HuddleVideoSurface(key: ValueKey(stream.id), stream: stream, mirror: isMe && front)
              else
                Center(
                  child: LayoutBuilder(
                    builder: (context, box) => SynkAvatar(
                      emoji: member.emoji,
                      colorIndex: member.color,
                      size: (box.biggest.shortestSide * 0.42).clamp(40.0, 96.0),
                    ),
                  ),
                ),
              if (status != PeerStatus.connected)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: Text(
                        status == PeerStatus.failed ? "Can't connect" : 'Connecting…',
                        style: context.text.labelLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: Space.sm,
                bottom: Space.sm,
                right: Space.sm,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: Radii.pillAll),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!member.mic) ...[
                          const Icon(Icons.mic_off_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            isMe ? 'You' : member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small avatar for the in-room strip: talking ring, muted and camera badges.
class HuddleBubble extends ConsumerWidget {
  const HuddleBubble({required this.member, this.size = 36, super.key});

  final HuddleMember member;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.synk;
    final talking = ref.watch(huddleSpeakingProvider.select((s) => s.contains(member.uid)));
    final badge = !member.mic
        ? Icons.mic_off_rounded
        : member.cam
        ? Icons.videocam_rounded
        : null;
    return SizedBox.square(
      dimension: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: talking ? c.online : Colors.transparent, width: 2),
            ),
            child: SynkAvatar(emoji: member.emoji, colorIndex: member.color, size: size),
          ),
          if (badge != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: c.surfaceOverlay, shape: BoxShape.circle),
                child: Icon(badge, size: 12, color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Round call control. [on] = the thing is active (mic live, camera on).
class HuddleControl extends StatelessWidget {
  const HuddleControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.on = true,
    this.danger = false,
    this.size = 56,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.synk;
    final (Color fill, Color fg) = danger
        ? (SynkPalette.danger, Colors.white)
        : on
        ? (c.surfaceOverlay, c.textPrimary)
        : (c.textPrimary, c.background);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        toggled: danger ? null : on,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  },
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: fg, size: size * 0.44),
            ),
          ),
        ),
      ),
    );
  }
}
