/// Build-time configuration.
///
/// Values come from `--dart-define` so the same code ships to dev/staging/prod
/// without edits, e.g. `flutter run --dart-define=FLAVOR=dev`.
enum AppFlavor { dev, staging, prod }

abstract final class AppConfig {
  static const String appName = 'Synk';

  static final AppFlavor flavor = AppFlavor.values.firstWhere(
    (f) => f.name == const String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
    orElse: () => AppFlavor.dev,
  );

  static bool get isProd => flavor == AppFlavor.prod;

  // ── Media sources ──────────────────────────────────────────────────────
  /// YouTube Data API v3 key (search + charts). Supplied at build time, e.g.
  /// `flutter run --dart-define-from-file=env/dev.json`. Empty → YouTube is disabled
  /// and the app runs radio-only.
  static const String youtubeApiKey = String.fromEnvironment('YOUTUBE_API_KEY');
  static bool get youtubeEnabled => youtubeApiKey.isNotEmpty;

  /// Sent as X-Android-Package / X-Android-Cert so an API key restricted to this
  /// Android app accepts plain REST calls. Default = the local debug keystore;
  /// pass the release certificate's SHA-1 for store builds.
  static const String androidPackage = 'club.buildd.synk';
  static const String androidCertSha1 = String.fromEnvironment(
    'ANDROID_CERT_SHA1',
    defaultValue: '467BE7808EC66F70FA492984DBAC65B856883540',
  );

  /// Radio Browser community mirrors, tried in order on failure.
  static const List<String> radioBrowserHosts = [
    'https://de1.api.radio-browser.info',
    'https://fi1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
  ];

  // ── Product limits (keep well inside the Firebase free tier) ───────────────
  static const int defaultRoomCapacity = 25;
  static const int maxRoomCapacity = 50;
  static const int chatPageSize = 60;
  static const int chatMemoryCap = 200;
  static const int maxChatLength = 500;
  static const int maxPlaylistTracks = 200;
  static const int maxQueueLength = 100;
  static const Duration roomHeartbeat = Duration(seconds: 60);
  static const Duration roomStaleAfter = Duration(minutes: 3);

  // ── Huddles (voice + optional camera inside a room) ─────────────────────────
  /// Peer-to-peer mesh: everyone sends to everyone, so upload grows with the
  /// group. 8 voices and 4 cameras keep a phone under ~1.5 Mbps up on 4G.
  static const int maxHuddleSize = 8;
  static const int maxHuddleCameras = 4;

  /// STUN finds a direct path on most networks. Strict NATs (some mobile
  /// carriers) also need a TURN relay: pass TURN_URLS (comma-separated),
  /// TURN_USERNAME and TURN_CREDENTIAL at build time. Without them, calls
  /// still work for most people but can fail to connect on those networks.
  static const List<String> stunUrls = ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'];
  static const String _turnUrls = String.fromEnvironment('TURN_URLS');
  static const String turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const String turnCredential = String.fromEnvironment('TURN_CREDENTIAL');
  static List<String> get turnUrls => [
    for (final u in _turnUrls.split(','))
      if (u.trim().isNotEmpty) u.trim(),
  ];

  // ── Links ────────────────────────────────────────────────────────────────
  static const String inviteScheme = 'synk';
  static const String privacyUrl = 'https://example.com/privacy';
  static const String termsUrl = 'https://example.com/terms';
}
