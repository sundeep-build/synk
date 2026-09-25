import 'dart:math' as math;

import 'huddle_models.dart';

/// Pure decisions for the huddle mesh, shared by the controller and tests.
abstract final class HuddleRules {
  /// Of each pair, the member whose uid sorts first sends the offer. Both
  /// sides work it out the same way, so two offers never cross ("glare").
  static bool isOfferer(String myUid, String otherUid) => myUid.compareTo(otherUid) < 0;

  static int camerasOn(Iterable<HuddleMember> members) => members.where((m) => m.cam).length;

  // ── Video budget ─────────────────────────────────────────────────────────
  // In a mesh every camera is encoded once per peer, so the per-peer cost
  // must fall as the group grows, or low-end phones overheat and 4G chokes.

  /// About 1.2 Mbps of video upload in total, split across peers, kept
  /// between 150 and 600 kbps per peer.
  static int videoBitrate(int peers) => (1200000 ~/ math.max(1, peers)).clamp(150000, 600000);

  /// Full 640×480 for one or two peers, then smaller: faces still read at
  /// tile size, and each extra encode gets cheaper.
  static double videoScaleDown(int peers) => peers <= 2
      ? 1.0
      : peers <= 4
      ? 1.5
      : 2.0;

  static int videoFps(int peers) => peers <= 2 ? 24 : 15;

  // ── Audio ────────────────────────────────────────────────────────────────
  /// Linear level (0–1, from WebRTC stats) above which someone is talking.
  static const double speakingLevel = 0.035;

  static const Map<String, String> _opus = {
    // Near-zero bitrate while silent (most of a group call).
    'usedtx': '1',
    // Rides out packet loss on mobile networks.
    'useinbandfec': '1',
    'stereo': '0',
    'maxaveragebitrate': '32000',
  };

  /// Rewrites the Opus `a=fmtp` line of an SDP with the settings above. Each
  /// side applies it to its own description, which asks the *other* side's
  /// encoder to use them.
  static String tuneOpus(String sdp) {
    final rtpmap = RegExp(r'^a=rtpmap:(\d+) opus/48000[^\r\n]*', multiLine: true, caseSensitive: false).firstMatch(sdp);
    if (rtpmap == null) return sdp;
    final pt = rtpmap.group(1)!;
    final fmtp = RegExp('^a=fmtp:$pt ([^\\r\\n]*)', multiLine: true).firstMatch(sdp);
    if (fmtp == null) {
      final eol = sdp.contains('\r\n') ? '\r\n' : '\n';
      return sdp.replaceRange(rtpmap.end, rtpmap.end, '${eol}a=fmtp:$pt ${_join(_opus)}');
    }
    final params = <String, String>{};
    for (final part in fmtp.group(1)!.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) params[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    params.addAll(_opus);
    return sdp.replaceRange(fmtp.start, fmtp.end, 'a=fmtp:$pt ${_join(params)}');
  }

  static String _join(Map<String, String> params) => [for (final e in params.entries) '${e.key}=${e.value}'].join(';');

  // ── Recovery ─────────────────────────────────────────────────────────────
  /// A dropped connection is rebuilt this many times before giving up on
  /// that peer (until either of you rejoins).
  static const int maxReconnects = 4;

  /// 2s, 4s, 8s, 16s.
  static Duration reconnectDelay(int attempt) => Duration(seconds: math.min(2 << attempt, 16));
}
