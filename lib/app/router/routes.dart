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
  static String join(String code) => '/join/$code';

  /// Screens that exist only before the user is fully signed in.
  static const gate = {splash, welcome, onboarding};
}
