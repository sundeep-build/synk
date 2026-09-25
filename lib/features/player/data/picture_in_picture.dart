import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';

/// Android picture-in-picture, over a small channel to `MainActivity`.
///
/// Only videos use it: radio already plays in the background. While a video
/// plays, [setAutoEnter] arms PiP so pressing Home / Recents shrinks the app
/// into the system's floating window instead of pausing the video.
///
/// Policy note: YouTube requires an embedded player of at least 200×200. The
/// system sizes (and lets users resize) the PiP window, often below that, so
/// PiP for YouTube is a compliance risk. [enabled] switches it off everywhere.
class PictureInPicture {
  PictureInPicture._() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_onCall);
  }

  static final PictureInPicture instance = PictureInPicture._();

  /// Kill switch for the whole feature.
  static const bool enabled = true;

  static const _channel = MethodChannel('club.buildd.synk/pip');

  final StreamController<bool> _modeCtrl = StreamController.broadcast();
  final StreamController<void> _dismissedCtrl = StreamController.broadcast();
  bool _inPip = false;
  bool? _armed;

  /// The app is currently shown in the PiP window.
  bool get inPip => _inPip;
  Stream<bool> get modeChanges => _modeCtrl.stream;

  /// The user closed the PiP window (✕ / swipe away), as opposed to
  /// expanding it back into the app. Playback should stop, not resume later.
  Stream<void> get dismissals => _dismissedCtrl.stream;

  /// Arms or disarms auto-enter (Android 12+) / enter-on-Home (Android 8–11).
  Future<void> setAutoEnter(bool armed) async {
    if (!enabled || !Platform.isAndroid || armed == _armed) return;
    _armed = armed;
    AppLogger.info('PiP', armed ? 'armed (video playing)' : 'disarmed');
    try {
      await _channel.invokeMethod<void>('setAutoEnter', armed);
    } on PlatformException catch (e, st) {
      AppLogger.error('PiP', e, st);
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'changed') return;
    final args = call.arguments is Map ? call.arguments as Map : const <Object?, Object?>{};
    final inPip = args['inPip'] == true;
    final dismissed = args['dismissed'] == true;
    if (inPip == _inPip) return;
    _inPip = inPip;
    AppLogger.info('PiP', inPip ? 'entered' : (dismissed ? 'closed' : 'expanded'));
    if (dismissed) _dismissedCtrl.add(null);
    _modeCtrl.add(inPip);
  }
}
