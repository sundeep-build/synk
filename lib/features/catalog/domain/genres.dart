import 'package:flutter/material.dart';

/// Curated "vibes" shown in onboarding and Explore. `searchQuery` feeds YouTube
/// search; `radioTag` is the Radio Browser tag used for the radio rows.
@immutable
class Vibe {
  const Vibe(this.label, this.searchQuery, this.radioTag, this.icon, this.colorIndex, {this.radioFirst = false});

  final String label;
  final String searchQuery;
  final String radioTag;
  final IconData icon;
  final int colorIndex;

  /// Regional vibes with strong live-radio coverage open on the Radio tab.
  final bool radioFirst;
}

abstract final class Vibes {
  static const List<Vibe> all = [
    Vibe('Pop', 'pop songs', 'pop', Icons.star_rounded, 0),
    Vibe('Hip-Hop', 'hip hop songs', 'hiphop', Icons.mic_external_on_rounded, 2),
    Vibe('Lo-Fi', 'lofi songs', 'lofi', Icons.nightlight_round, 5),
    Vibe('Electronic', 'electronic music', 'electronic', Icons.graphic_eq_rounded, 1),
    Vibe('House', 'house music', 'house', Icons.nightlife_rounded, 7),
    Vibe('R&B', 'r&b songs', 'rnb', Icons.favorite_rounded, 4),
    Vibe('Rock', 'rock songs', 'rock', Icons.electric_bolt_rounded, 2),
    Vibe('Chill', 'chill songs', 'chillout', Icons.spa_rounded, 3),
    Vibe('Jazz', 'jazz music', 'jazz', Icons.piano_rounded, 5),
    Vibe('Latin', 'latin songs', 'latin', Icons.celebration_rounded, 4),
    Vibe('Bollywood', 'bollywood songs', 'bollywood', Icons.movie_filter_rounded, 0, radioFirst: true),
    Vibe('Punjabi', 'punjabi songs', 'punjabi', Icons.music_note_rounded, 2, radioFirst: true),
    Vibe('Devotional', 'bhajan devotional songs', 'devotional', Icons.self_improvement_rounded, 6, radioFirst: true),
  ];

  static Vibe? byLabel(String? label) {
    for (final v in all) {
      if (v.label == label) return v;
    }
    return null;
  }
}
