import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/design_system.dart';
import '../../features/auth/application/session.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/home/presentation/genre_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/library/presentation/playlist_screen.dart';
import '../../features/player/presentation/now_playing_screen.dart';
import '../../features/profile/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/rooms/presentation/join_screen.dart';
import '../../features/rooms/presentation/live_rooms_screen.dart';
import '../../features/rooms/presentation/room_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../shell/exit_guard.dart';
import '../shell/home_shell.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod → go_router: re-run redirects whenever the session moves.
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(sessionProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (_, state) => redirectFor(ref.read(sessionProvider), state.matchedLocation, state.uri),
    errorBuilder: (_, _) => const _NotFound(),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const ExitGuard(child: WelcomeScreen()),
      ),
      GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'genre/:label',
                    builder: (_, s) => GenreScreen(label: s.pathParameters['label']!),
                  ),
                  GoRoute(path: 'live', builder: (_, _) => const LiveRoomsScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.search, builder: (_, _) => const SearchScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.library,
                builder: (_, _) => const LibraryScreen(),
                routes: [
                  GoRoute(
                    path: 'playlist/:id',
                    builder: (_, s) => PlaylistScreen(id: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/room/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, RoomScreen(roomId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.player,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _slideUp(s, const NowPlayingScreen()),
      ),
      GoRoute(
        path: '/join/:code',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => JoinScreen(code: s.pathParameters['code']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Pure redirect policy (unit-tested). Deep links that arrive before sign-in
/// (e.g. an invite to `/join/ABC234`) are carried through as `?from=` and
/// resumed once the user is ready.
@visibleForTesting
String? redirectFor(SessionState session, String location, Uri uri) {
  final atGate = Routes.gate.contains(location);
  final from = uri.queryParameters['from'] ?? (atGate ? null : uri.toString());

  String? gate(String path) =>
      location == path ? null : Uri(path: path, queryParameters: from == null ? null : {'from': from}).toString();

  return switch (session) {
    SessionLoading() || SessionError() => gate(Routes.splash),
    SignedOut() => gate(Routes.welcome),
    NeedsProfile() => gate(Routes.onboarding),
    SessionReady() => atGate ? (from ?? Routes.home) : null,
  };
}

CustomTransitionPage<void> _slideUp(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: Motion.slow,
  reverseTransitionDuration: Motion.medium,
  transitionsBuilder: (_, animation, _, child) => SlideTransition(
    position: animation.drive(
      Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Motion.emphasized)),
    ),
    child: child,
  ),
);

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: EmptyState(
        icon: Icons.explore_off_rounded,
        title: 'Page not found',
        action: FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Go home')),
      ),
    ),
  );
}
