import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'youtube_stage.dart';

/// Which on-screen slot holds the app's one YouTube player.
///
/// Slots claim the player with a priority (PiP window > room / Now Playing >
/// floating card). The highest, most recent claim owns it, and only the owner
/// builds the player. Every owner builds it under the same GlobalKey, so
/// changing owner *moves* the playing player instead of building a new one.
/// Leaving the room hands the video to the floating card mid-play, with no
/// 2–3 s reload.
class VideoStageRegistry extends ChangeNotifier {
  /// The shared player's identity.
  final GlobalKey stageKey = GlobalKey(debugLabel: 'youtube-stage');

  /// Builds the shared player for an owning slot. Tests swap in a stand-in
  /// (a real one needs a WebView).
  Widget Function(Key key, YouTubeStage config) playerBuilder = (key, c) =>
      YouTubeStage(key: key, height: c.height, radius: c.radius, floating: c.floating, fill: c.fill);

  final List<(Object slot, int priority)> _claims = [];
  Object? _owner;
  bool _resolveScheduled = false;

  bool owns(Object slot) => identical(_owner, slot);

  void claim(Object slot, int priority) {
    final i = _claims.indexWhere((c) => identical(c.$1, slot));
    if (i >= 0 && _claims[i].$2 == priority) return;
    if (i >= 0) _claims.removeAt(i);
    _claims.add((slot, priority));
    _resolve();
  }

  void release(Object slot) {
    final before = _claims.length;
    _claims.removeWhere((c) => identical(c.$1, slot));
    if (_claims.length != before) _resolve();
  }

  /// Picks the owner. Mid-build (a slot mounting and claiming), the switch
  /// waits for the frame to end: the old owner hasn't rebuilt yet, so both
  /// would hold the player for a frame. Otherwise it switches at once and
  /// every slot rebuilds together in the next frame, which is what lets the
  /// new owner take the player in the same frame the old one lets go.
  void _resolve() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_resolveScheduled) return;
      _resolveScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _resolveScheduled = false;
        _resolve();
      });
      return;
    }
    Object? next;
    var best = -1;
    for (final (slot, priority) in _claims) {
      // `>=`: among equals, the newest claim (e.g. a screen pushed on top) wins.
      if (priority >= best) {
        best = priority;
        next = slot;
      }
    }
    if (identical(next, _owner)) return;
    _owner = next;
    notifyListeners();
  }
}

final videoStageRegistryProvider = Provider<VideoStageRegistry>((ref) {
  final registry = VideoStageRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});

/// A place the shared YouTube player can appear.
///
/// While it [claim]s and wins (see [VideoStageRegistry]) it shows the player
/// configured like [stage]. Otherwise [builder] gets null, and by default a
/// black box of the same size keeps the layout still. A slot on a route lets
/// go the moment its route starts closing, so the next slot (usually the
/// floating card) takes the player while it's still playing.
///
/// [claim] is a listenable, not a flag: it must change from event handlers
/// (a stream event, a PiP callback), so the hand-over is announced outside a
/// build and every slot switches in the same frame.
class VideoSlot extends ConsumerStatefulWidget {
  const VideoSlot({required this.stage, this.priority = screen, this.claim, this.builder, super.key});

  static const int floating = 1;
  static const int screen = 2;
  static const int pip = 3;

  /// How the player looks here (its key is ignored).
  final YouTubeStage stage;
  final int priority;

  /// Whether this slot wants the player right now; null = always.
  final ValueListenable<bool>? claim;

  /// Wraps the player (null while another slot has it).
  final Widget Function(BuildContext context, Widget? player)? builder;

  @override
  ConsumerState<VideoSlot> createState() => _VideoSlotState();
}

class _VideoSlotState extends ConsumerState<VideoSlot> {
  late final VideoStageRegistry _registry = ref.read(videoStageRegistryProvider);
  Animation<double>? _route;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onOwnerChanged);
    widget.claim?.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (!identical(route, _route)) {
      _route?.removeStatusListener(_onRouteStatus);
      _route = route?..addStatusListener(_onRouteStatus);
      _closing = route?.status == AnimationStatus.reverse;
    }
    _sync();
  }

  @override
  void didUpdateWidget(VideoSlot old) {
    super.didUpdateWidget(old);
    if (!identical(old.claim, widget.claim)) {
      old.claim?.removeListener(_sync);
      widget.claim?.addListener(_sync);
    }
    _sync();
  }

  void _onRouteStatus(AnimationStatus status) {
    final closing = status == AnimationStatus.reverse || status == AnimationStatus.dismissed;
    if (closing == _closing) return;
    _closing = closing;
    _sync();
  }

  void _sync() =>
      (widget.claim?.value ?? true) && !_closing ? _registry.claim(this, widget.priority) : _registry.release(this);

  void _onOwnerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.claim?.removeListener(_sync);
    _route?.removeStatusListener(_onRouteStatus);
    _registry
      ..removeListener(_onOwnerChanged)
      ..release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _registry.owns(this) ? _registry.playerBuilder(_registry.stageKey, widget.stage) : null;
    final builder = widget.builder;
    if (builder != null) return builder(context, player);
    return player ??
        YouTubeStageFrame(height: widget.stage.height, radius: widget.stage.radius, fill: widget.stage.fill);
  }
}
