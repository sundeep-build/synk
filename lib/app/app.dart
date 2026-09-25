import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/design_system/design_system.dart';
import '../core/di/core_providers.dart';
import '../features/player/presentation/floating_video.dart';
import '../features/player/presentation/pip_host.dart';
import '../features/rooms/presentation/incoming_huddle.dart';
import 'router/app_router.dart';

class SynkApp extends ConsumerWidget {
  const SynkApp({super.key});

  // Built once: ThemeData construction (and font lookups) isn't free.
  static final _light = AppTheme.light();
  static final _dark = AppTheme.dark();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      // Respect large text settings, but cap extreme scales that would break
      // fixed-size artwork layouts. The floating video sits above every route
      // so a minimised video keeps playing while the user browses; PipHost
      // swaps in the video alone when Android shows the app in PiP. The
      // incoming-huddle host rings from any screen.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.35)),
        child: PipHost(
          child: Stack(
            children: [
              child!,
              const Positioned.fill(child: FloatingVideo()),
              const IncomingHuddleHost(),
            ],
          ),
        ),
      ),
    );
  }
}
