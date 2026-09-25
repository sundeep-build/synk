import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';
import '../../catalog/domain/track.dart';

enum PlaybackStatus { idle, playing, paused }

/// The single source of truth for what a room is hearing, stored at
/// `roomsLive/{roomId}/playback` in Realtime Database.
///
/// Instead of streaming positions, we store an *anchor*: "at server time
/// [updatedAt] the track was at [positionMs]". Every client derives the
/// current position locally from the server clock, so a room of 50 costs the
/// same bandwidth as a room of 2 and nobody needs to broadcast ticks.
@immutable
class RoomPlayback {
  const RoomPlayback({
    required this.status,
    required this.positionMs,
    required this.updatedAt,
    required this.seq,
    this.track,
    this.by,
    this.queueItemId,
  });

  static const idle = RoomPlayback(status: PlaybackStatus.idle, positionMs: 0, updatedAt: 0, seq: 0);

  final Track? track;
  final PlaybackStatus status;

  /// Track position at [updatedAt].
  final int positionMs;

  /// Server epoch millis when this anchor was written.
  final int updatedAt;

  /// Monotonic track counter. Advancing to the next track requires
  /// `seq == current + 1`, which makes "who skips first" race-free.
  final int seq;

  /// uid that wrote this state.
  final String? by;

  /// Queue entry this track was taken from. Clients treat that entry as
  /// consumed even if the writer crashed before deleting it, so a track is
  /// never played twice.
  final String? queueItemId;

  bool get isPlaying => status == PlaybackStatus.playing && track != null;

  /// Where playback should be *now*, given the server clock.
  int expectedPositionMs(int serverNowMs) {
    if (!isPlaying) return positionMs;
    final elapsed = serverNowMs - updatedAt;
    final pos = positionMs + (elapsed < 0 ? 0 : elapsed);
    final duration = track!.durationMs;
    if (track!.isLive || duration <= 0) return pos;
    return pos > duration ? duration : pos;
  }

  /// True once the (on-demand) track has run to its end.
  bool hasEnded(int serverNowMs, {int graceMs = 400}) {
    final t = track;
    if (!isPlaying || t == null || t.isLive || t.durationMs <= 0) return false;
    return expectedPositionMs(serverNowMs) >= t.durationMs - graceMs;
  }

  static RoomPlayback fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) return idle;
    final track = Track.tryParse(raw['track']);
    return RoomPlayback(
      track: track,
      status: track == null
          ? PlaybackStatus.idle
          : PlaybackStatus.values.asNameMap()[raw.str('status')] ?? PlaybackStatus.paused,
      positionMs: raw.integer('positionMs'),
      updatedAt: raw.integer('updatedAt'),
      seq: raw.integer('seq'),
      by: raw.strOrNull('by'),
      queueItemId: raw.strOrNull('qid'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomPlayback &&
      other.track == track &&
      other.status == status &&
      other.positionMs == positionMs &&
      other.updatedAt == updatedAt &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(track, status, positionMs, updatedAt, seq);
}
