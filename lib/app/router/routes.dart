/// Route paths in one place — never hard-code a path in a widget.
abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const onboarding = '/onboarding';

  static const home = '/home';
  static const search = '/search';
  static const library = '/library';
  static const profile = '/profile';

  static const player = '/player';
  static String room(String id) => '/room/$id';
  // Nested under their tab so the dock (mini player + nav) stays visible.
  static String playlist(String id) => '$library/playlist/$id';
  static String genre(String label) => '$home/genre/${Uri.encodeComponent(label)}';
  static const liveRooms = '$home/live';
  static const trending = '$home/trending';
  static String join(String code) => '/join/$code';

  /// Full-screen "someone started a huddle" page (Join / Decline).
  static const incomingHuddle = '/huddle/incoming';

  /// The room a [room] path shows, or null for any other path.
  static String? roomIn(String path) => path.startsWith('/room/') ? path.substring('/room/'.length) : null;

  /// Screens that exist only before the user is fully signed in.
  static const gate = {splash, welcome, onboarding};
}
