import 'dart:async';

import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/logging/app_logger.dart';
import '../../catalog/domain/track.dart';
import 'media_engine.dart';

/// YouTube playback through the official IFrame player — compliant with the
/// YouTube API Developer Policies by construction:
///
/// * There is no player until a [YouTubeStage] is on screen and *attaches* a
///   controller; when that screen goes away the controller is closed, so a
///   video can never keep playing unseen (policy III.I.9, no background player).
///   Minimising the room / Now Playing hands the video to the app-wide
///   floating player ([wantsFloating]), which is still on screen at the
///   minimum 200×200 viewport.
/// * When the app goes to the background the video is paused.
/// * Audio is never separated from video; nothing is downloaded or cached.
///
/// While detached, the engine remembers the track, the desired play state and
/// the position, and resumes from there when a stage attaches again.
class YouTubeEngine implements MediaEngine {
  /// Mounted stages, newest last. Only the newest drives the video; when it
  /// goes away the one underneath takes over (e.g. PiP window → room screen).
  final List<YoutubePlayerController> _stages = [];
  YoutubePlayerController? get _controller => _stages.isEmpty ? null : _stages.last;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _stateSub;

  Track? _track;
  bool _wantPlay = false;
  bool _foreground = true;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.unknown;
  YoutubeError _lastError = YoutubeError.none;

  final StreamController<bool> _playingCtrl = StreamController.broadcast();
  final StreamController<Duration> _positionCtrl = StreamController.broadcast();
  final StreamController<void> _completedCtrl = StreamController.broadcast();
  final StreamController<YoutubeError> _errorCtrl = StreamController.broadcast();
  final StreamController<bool> _visibleCtrl = StreamController.broadcast();
  final StreamController<bool> _floatingCtrl = StreamController.broadcast();
  final StreamController<bool> _wantsPlayCtrl = StreamController.broadcast();
  final StreamController<bool> _floatEligibleCtrl = StreamController.broadcast();

  int _primaryStages = 0;
  bool _floating = false;
  bool _wantsPlay = false;
  bool _floatEligible = false;

  /// The PiP window's stage. While it's up, stages mounting in the (offstage)
  /// app park underneath it instead of taking the video away.
  YoutubePlayerController? _pinned;

  /// A player is on screen and the app is in the foreground.
  bool get visible => _controller != null && _foreground;

  /// Emits when [visible] changes (rooms re-sync when the video comes back).
  Stream<bool> get visibleStream => _visibleCtrl.stream;

  /// Player errors (e.g. a video that can't be embedded) — callers skip ahead.
  Stream<YoutubeError> get errorStream => _errorCtrl.stream;

  /// A video was minimised while playing (no full-size stage — room, Now
  /// Playing — is mounted), so the floating player shows it. It then stays up
  /// through pauses until the user closes it ([dismissFloating]) or the video
  /// goes away.
  bool get wantsFloating => _floating;

  /// The user means a video to be playing (regardless of buffering or which
  /// stage has it). PiP is armed on this, not on the reported player state.
  bool get wantsPlay => _wantsPlay;
  Stream<bool> get wantsPlayStream => _wantsPlayCtrl.stream;

  /// The floating card would show this video if no full-size player were on
  /// screen: it's playing, or already floating (a pause keeps the card up).
  /// Unlike [wantsFloating] this ignores full-size players, so the card can
  /// stand by while the room is open and take the player the moment the room
  /// closes, with no reload in between.
  bool get floatEligible => _floatEligible;
  Stream<bool> get floatEligibleStream => _floatEligibleCtrl.stream;

  /// ✕ on the floating card. A later play brings it back.
  void dismissFloating() {
    if (!_floating) return;
    _floating = false;
    if (!_floatingCtrl.isClosed) _floatingCtrl.add(false);
    _syncFloatEligible();
  }

  /// Emits when [wantsFloating] changes. Delivered asynchronously, so stages
  /// mounting/unmounting mid-frame never trigger a rebuild during build.
  Stream<bool> get floatingStream => _floatingCtrl.stream;

  /// Full-size stages register so the floating player steps aside.
  void addPrimaryStage() {
    _primaryStages++;
    _syncFloating();
  }

  void removePrimaryStage() {
    if (_primaryStages > 0) _primaryStages--;
    _syncFloating();
  }

  // ── Attachment (called by YouTubeStage) ──────────────────────────────────
  /// [pinned]: the PiP stage, which keeps the video until it goes away.
  void attach(YoutubePlayerController controller, {bool pinned = false}) {
    final pin = _pinned;
    if (!pinned && pin != null && !identical(pin, controller)) {
      // Mounted under the PiP window: park it, idle, right below; it takes
      // over (and gets cued) when PiP ends.
      _stages
        ..remove(controller)
        ..insert(_stages.indexOf(pin), controller);
      return;
    }
    if (pinned) _pinned = controller;
    final previous = _controller;
    // Hand over: only the newest stage plays, so audio never doubles up.
    if (previous != null && !identical(previous, controller)) unawaited(_guard(previous, previous.pauseVideo));
    _stages
      ..remove(controller)
      ..add(controller);
    _bind(controller);
  }

  void detach(YoutubePlayerController controller) {
    if (identical(_pinned, controller)) _pinned = null;
    final wasActive = identical(_controller, controller);
    _stages.remove(controller);
    if (!wasActive) return;
    final next = _controller;
    if (next != null) return _bind(next); // resumes from where the video is now
    _unsubscribe();
    _setState(PlayerState.paused);
    _visibleCtrl.add(false);
  }

  void _bind(YoutubePlayerController controller) {
    _unsubscribe();
    _valueSub = controller.listen(_onValue);
    _stateSub = controller.videoStateStream.listen((s) {
      _position = s.position;
      _positionCtrl.add(s.position);
    });
    _visibleCtrl.add(visible);
    unawaited(_cueCurrent());
  }

  /// App lifecycle: pause when backgrounded, resume (if wanted) when back.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    final c = _controller;
    if (c != null) {
      unawaited(_guard(c, () => foreground && _wantPlay ? c.playVideo() : c.pauseVideo()));
    }
    _visibleCtrl.add(visible);
  }

  // ── MediaEngine ──────────────────────────────────────────────────────────
  @override
  Future<void> load(Track track, {Duration position = Duration.zero, bool play = true}) {
    _track = track;
    _wantPlay = play;
    _position = position;
    _lastError = YoutubeError.none;
    _positionCtrl.add(position);
    _syncFloating();
    return _cueCurrent();
  }

  @override
  Future<void> play() async {
    _wantPlay = true;
    _syncFloating();
    final c = _controller;
    if (c != null && _foreground) await _guard(c, c.playVideo);
  }

  @override
  Future<void> pause() async {
    _wantPlay = false;
    _syncFloating();
    final c = _controller;
    if (c != null) await _guard(c, c.pauseVideo);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionCtrl.add(position);
    final c = _controller;
    if (c != null) await _guard(c, () => c.seekTo(seconds: position.inMilliseconds / 1000, allowSeekAhead: true));
  }

  /// YouTube only supports coarse rates (0.25x steps), so no speed nudging.
  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> clear() async {
    _track = null;
    _wantPlay = false;
    _position = Duration.zero;
    _syncFloating();
    final c = _controller;
    // Not awaited: a stage that never finished loading would hold callers
    // (e.g. leaving a room) for the package's 30 s ready timeout.
    if (c != null) unawaited(_guard(c, c.stopVideo));
    _setState(PlayerState.unStarted);
  }

  @override
  bool get playing => _state == PlayerState.playing;

  @override
  bool get isBuffering => _state == PlayerState.buffering || (_wantPlay && visible && _state != PlayerState.playing);

  @override
  double get speed => 1;

  @override
  Duration get position => _position;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<void> get completedStream => _completedCtrl.stream;

  // ── Internals ────────────────────────────────────────────────────────────
  /// Loads the current track into the active stage. If YouTube hasn't come
  /// up within the package's 30 s (slow network) the command is lost, so try
  /// once more — reading the position again, since time has moved on.
  Future<void> _cueCurrent({bool retry = true}) async {
    final c = _controller;
    final id = _track?.youtubeId;
    if (c == null || id == null) return;
    // YouTube rejects a start at or past the end ("invalid parameter"): start
    // over instead of showing a black player.
    final durationS = (_track?.durationMs ?? 0) / 1000;
    var start = _position.inMilliseconds / 1000;
    if (start < 0 || (durationS > 0 && start >= durationS - 1)) start = 0;
    final timedOut = await _guard(
      c,
      () => _wantPlay && _foreground
          ? c.loadVideoById(videoId: id, startSeconds: start)
          : c.cueVideoById(videoId: id, startSeconds: start),
    );
    if (timedOut && retry && identical(_controller, c) && _track?.youtubeId == id) {
      await _cueCurrent(retry: false);
    }
  }

  void _onValue(YoutubePlayerValue value) {
    _setState(value.playerState);
    if (value.error != YoutubeError.none && value.error != _lastError) {
      _lastError = value.error;
      AppLogger.info('YouTube', 'player error ${value.error} for ${_track?.id}');
      _errorCtrl.add(value.error);
    }
  }

  void _setState(PlayerState next) {
    if (next == _state) return;
    final wasPlaying = playing;
    _state = next;
    if (wasPlaying != playing) _playingCtrl.add(playing);
    if (next == PlayerState.ended) _completedCtrl.add(null);
    _syncWantsPlay();
  }

  void _syncFloating() {
    // Shown only for a playing video; once shown, a pause keeps it up.
    final next = _track != null && _primaryStages == 0 && (_wantPlay || _floating);
    if (next != _floating) {
      _floating = next;
      if (!_floatingCtrl.isClosed) _floatingCtrl.add(next);
    }
    _syncFloatEligible();
    _syncWantsPlay();
  }

  void _syncFloatEligible() {
    final next = _track != null && (_wantPlay || _floating);
    if (next == _floatEligible) return;
    _floatEligible = next;
    if (!_floatEligibleCtrl.isClosed) _floatEligibleCtrl.add(next);
  }

  void _syncWantsPlay() {
    final next = _track != null && _wantPlay && _state != PlayerState.ended;
    if (next == _wantsPlay) return;
    _wantsPlay = next;
    if (!_wantsPlayCtrl.isClosed) _wantsPlayCtrl.add(next);
  }

  void _unsubscribe() {
    unawaited(_valueSub?.cancel());
    unawaited(_stateSub?.cancel());
    _valueSub = null;
    _stateSub = null;
  }

  /// Runs a player call on [target]; never throws. Returns true if it timed
  /// out while [target] was still the stage on screen.
  ///
  /// Every call waits for the player's "ready", with a 30 s timeout inside the
  /// package. A stage that is removed before YouTube loads (e.g. the floating
  /// player, when the user reopens the room right away) never gets ready, so
  /// its pending calls time out. That's expected and isn't reported. Only
  /// failures on the live stage are, and a timeout there is logged as info (a
  /// slow network, not a bug).
  Future<bool> _guard(YoutubePlayerController target, Future<void> Function() call) async {
    try {
      await call();
      return false;
    } catch (e, st) {
      if (!_stages.contains(target)) return false; // stage already gone
      if (e is TimeoutException) {
        AppLogger.info('YouTube', 'player not ready after 30s for ${_track?.id}');
        return identical(_controller, target);
      }
      AppLogger.error('YouTube', e, st);
      return false;
    }
  }

  Future<void> dispose() async {
    _unsubscribe();
    await Future.wait([
      _playingCtrl.close(),
      _positionCtrl.close(),
      _floatEligibleCtrl.close(),
      _completedCtrl.close(),
      _errorCtrl.close(),
      _visibleCtrl.close(),
      _floatingCtrl.close(),
      _wantsPlayCtrl.close(),
    ]);
  }
}
