import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';

enum RingAction { accept, decline }

/// Android side of an incoming huddle (`HuddleRinger.kt`, `MainActivity`):
/// the ringtone, the call notification, showing the app over the lock
/// screen, and the notification's Join / Decline buttons. On other platforms
/// it does nothing, and the in-app page shows without a ringtone.
class HuddleRinger {
  HuddleRinger() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('club.buildd.synk/huddle_ring');

  final StreamController<RingAction> _actions = StreamController.broadcast();

  /// Join / Decline tapped on the notification.
  Stream<RingAction> get actions => _actions.stream;

  /// The call notification, for when the app isn't on screen.
  Future<void> notify({required String caller, required String room}) =>
      _call('show', {'caller': caller, 'room': room});

  Future<void> cancel() => _call('cancel');

  /// The ringtone and vibration alone, while the app shows its own page.
  Future<void> ringtone(bool on) => _call('ringtone', on);

  /// Done ringing: stop showing over the lock screen. [unlock] (answered
  /// there) asks the user to unlock first.
  Future<void> release({required bool unlock}) => _call('release', {'unlock': unlock});

  /// Android 13+ notification permission, without which the call
  /// notification can't show.
  Future<void> requestPermission() => _call('requestPermission');

  Future<void> _call(String method, [Object? args]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e, st) {
      AppLogger.error('HuddleRinger', e, st);
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'action') return;
    final action = RingAction.values.asNameMap()[call.arguments];
    if (action != null) _actions.add(action);
  }
}
