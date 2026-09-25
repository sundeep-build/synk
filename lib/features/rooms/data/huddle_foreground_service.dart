import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';

/// Android only: keeps the microphone working while Synk is in the
/// background, with an ongoing "In a huddle" notification. Android 11+ cuts
/// background mic access unless a microphone foreground service runs (see
/// `HuddleService.kt`). iOS needs nothing extra: the `audio` background mode
/// already covers an active voice session.
class HuddleForegroundService {
  const HuddleForegroundService();

  static const _channel = MethodChannel('club.buildd.synk/huddle');

  Future<void> start(String roomName) => _call('start', {'room': roomName});

  Future<void> stop() => _call('stop');

  Future<void> _call(String method, [Object? args]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e, st) {
      // The call still works in the foreground without it.
      AppLogger.error('HuddleService', e, st);
    }
  }
}
