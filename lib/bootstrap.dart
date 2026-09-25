import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/design_system/design_system.dart';
import 'core/di/core_providers.dart';
import 'core/error/app_exception.dart';
import 'core/logging/app_logger.dart';
import 'core/storage/local_store.dart';
import 'features/player/application/player_providers.dart';
import 'features/player/data/synk_audio_handler.dart';
import 'firebase_options.dart';

/// App start-up: everything async that must exist before the first frame.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on UnsupportedError catch (e) {
    // `flutterfire configure` hasn't been run yet.
    runApp(_SetupRequired(message: e.message ?? '$e'));
    return;
  }

  _setUpCrashReporting();
  _setUpBudgets();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final (store, audio) = await (LocalStore.create(), _initAudio()).wait;

  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store), audioHandlerProvider.overrideWithValue(audio)],
      retry: _retryPolicy,
      child: const SynkApp(),
    ),
  );
}

void _setUpCrashReporting() {
  final crashlytics = FirebaseCrashlytics.instance;
  unawaited(crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode));
  FlutterError.onError = (details) {
    // Keep Flutter's full report (widget, file:line, render tree) in the
    // terminal; replacing onError outright hides it.
    FlutterError.presentError(details);
    unawaited(crashlytics.recordFlutterFatalError(details));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
  AppLogger.attachCrashlytics();
}

/// Memory & cache ceilings — the app should behave on a 2GB-RAM phone.
void _setUpBudgets() {
  // Firestore offline cache: fast cold starts, bounded disk.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 40 * 1024 * 1024);
  // Realtime Database persistence stays OFF on purpose: live room state
  // must come from the server, never from a stale local cache.

  // Decoded image cache (artwork is already downsampled at decode time).
  PaintingBinding.instance.imageCache
    ..maximumSize = 250
    ..maximumSizeBytes = 60 << 20;
}

Future<SynkAudioHandler> _initAudio() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  return AudioService.init(
    builder: SynkAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'club.buildd.synk.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Retry transient network failures a couple of times; never retry
/// permission/validation errors (they won't fix themselves).
Duration? _retryPolicy(int retryCount, Object error) {
  if (retryCount >= 2) return null;
  final e = AppException.from(error);
  if (e is! NetworkException) return null;
  return Duration(milliseconds: 600 * (1 << retryCount));
}

class _SetupRequired extends StatelessWidget {
  const _SetupRequired({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Firebase setup needed', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: Space.md),
              const Text('Run `flutterfire configure` in the project root, then restart the app.'),
              const SizedBox(height: Space.md),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    ),
  );
}
