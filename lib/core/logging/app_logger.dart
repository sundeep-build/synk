import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Thin logger: console in debug, Crashlytics breadcrumbs + non-fatals in
/// release. Keeps logging calls cheap (no string building unless enabled).
abstract final class AppLogger {
  static bool _crashlyticsReady = false;

  static void attachCrashlytics() => _crashlyticsReady = true;

  static void debug(String tag, String Function() message) {
    if (kDebugMode) debugPrint('[$tag] ${message()}');
  }

  static void info(String tag, String message) {
    if (kDebugMode) debugPrint('[$tag] $message');
    if (_crashlyticsReady) FirebaseCrashlytics.instance.log('[$tag] $message');
  }

  static void error(String tag, Object error, [StackTrace? stack, bool fatal = false]) {
    if (kDebugMode) {
      debugPrint('[$tag] ERROR $error');
      if (stack != null) debugPrintStack(stackTrace: stack, maxFrames: 8);
    }
    if (_crashlyticsReady) {
      FirebaseCrashlytics.instance.recordError(error, stack, reason: tag, fatal: fatal);
    }
  }
}
