import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Where a playable item comes from. A new provider (e.g. a licensed catalog) is
/// added here + a data source; the rest of the app is source-agnostic.
///
/// * [youtube] — official YouTube player; plays only while its player is on screen.
/// * [radio]   — live stations; plays in the background with lock-screen controls.
enum TrackSource { youtube, radio }

/// A playable item: a YouTube song/video or a live radio station.
///
/// Serialised compactly (see [toJson]) because the same shape is stored in
/// room queues (RTDB), playlists/likes (Firestore) and local history.
@immutable
class Track {
  const Track({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    required this.streamUrl,
    this.artworkUrl,
    this.durationMs = 0,
    this.genre,
  });

  /// Source-scoped id, e.g. `yt:dQw4w9WgXcQ` or `radio:<uuid>`.
  /// Safe to use as a Firestore document id.
  final String id;
  final TrackSource source;
  final String title;
  final String artist;
  final String streamUrl;
  final String? artworkUrl;
  final int durationMs;
  final String? genre;

  bool get isLive => source == TrackSource.radio;
  bool get isYouTube => source == TrackSource.youtube;

  /// The 11-character YouTube video id, for YouTube tracks.
  String? get youtubeId => isYouTube ? id.substring(3) : null;

  /// Only radio may play while the app is in the background (YouTube's rules).
  bool get canPlayInBackground => source == TrackSource.radio;
  Duration get duration => Duration(milliseconds: durationMs);

  /// Stable small int used to pick placeholder gradients.
  int get seed => id.hashCode;

  Map<String, Object?> toJson() => {
    'id': id,
    'src': source.name,
    't': title,
    'a': artist,
    'u': streamUrl,
    if (artworkUrl != null) 'art': artworkUrl,
    if (durationMs > 0) 'd': durationMs,
    if (genre != null) 'g': genre,
  };

  static Track? tryParse(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final id = raw.str('id');
    final url = raw.str('u');
    // Unknown sources (e.g. Audius items saved by older builds) are dropped.
    final source = TrackSource.values.asNameMap()[raw.str('src')];
    if (id.isEmpty || url.isEmpty || source == null) return null;
    return Track(
      id: id,
      source: source,
      title: raw.str('t', 'Unknown track'),
      artist: raw.str('a', 'Unknown artist'),
      streamUrl: url,
      artworkUrl: raw.strOrNull('art'),
      durationMs: raw.integer('d'),
      genre: raw.strOrNull('g'),
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track($id, $title)';
}
