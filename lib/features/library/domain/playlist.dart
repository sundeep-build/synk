import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';
import '../../catalog/domain/track.dart';

/// Stored as ONE document with an embedded track list (capped), so opening a
/// playlist costs a single read instead of one read per song.
@immutable
class Playlist {
  const Playlist({required this.id, required this.name, required this.tracks, this.updatedAt});

  final String id;
  final String name;
  final List<Track> tracks;
  final DateTime? updatedAt;

  String? get coverUrl {
    for (final t in tracks) {
      if (t.artworkUrl != null) return t.artworkUrl;
    }
    return null;
  }

  Duration get totalDuration => tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  factory Playlist.fromJson(String id, Json json) => Playlist(
    id: id,
    name: json.str('name', 'Playlist'),
    tracks: [
      for (final raw in json.list('tracks'))
        if (Track.tryParse(raw) case final Track t) t,
    ],
    updatedAt: json.time('updatedAt'),
  );
}
