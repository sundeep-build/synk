import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/json.dart';

enum RoomVisibility { public, private }

enum RoomMode { music, radio }

@immutable
class NowPlayingSummary {
  const NowPlayingSummary({required this.title, required this.artist, this.artworkUrl});

  final String title;
  final String artist;
  final String? artworkUrl;

  Map<String, Object?> toJson() => {'title': title, 'artist': artist, if (artworkUrl != null) 'art': artworkUrl};

  static NowPlayingSummary? fromJson(Json? json) {
    if (json == null) return null;
    return NowPlayingSummary(title: json.str('title'), artist: json.str('artist'), artworkUrl: json.strOrNull('art'));
  }

  @override
  bool operator ==(Object other) =>
      other is NowPlayingSummary && other.title == title && other.artist == artist && other.artworkUrl == artworkUrl;

  @override
  int get hashCode => Object.hash(title, artist, artworkUrl);
}

/// Directory entry for a room, stored in Firestore at `rooms/{id}`.
/// Live state (playback, chat, presence) lives in Realtime Database.
@immutable
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.code,
    required this.hostId,
    required this.hostName,
    required this.hostEmoji,
    required this.hostColor,
    required this.visibility,
    required this.mode,
    required this.capacity,
    this.vibe,
    this.coverColor = 0,
    this.listenerCount = 0,
    this.isLive = true,
    this.closed = false,
    this.lastActiveAt,
    this.nowPlaying,
    this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String hostId;
  final String hostName;
  final String hostEmoji;
  final int hostColor;
  final RoomVisibility visibility;
  final RoomMode mode;
  final int capacity;
  final String? vibe;
  final int coverColor;
  final int listenerCount;
  final bool isLive;

  /// The host ended it for everyone. Unlike an idle room (everyone left),
  /// an ended room can't be reopened.
  final bool closed;
  final DateTime? lastActiveAt;
  final NowPlayingSummary? nowPlaying;
  final DateTime? createdAt;

  bool get isPublic => visibility == RoomVisibility.public;

  /// People are in it right now, as far as the directory knows.
  bool isActive([DateTime? now]) => isLive && !closed && listenerCount > 0 && !isStale(now);

  /// No heartbeat for a while → everyone left without a clean exit.
  bool isStale([DateTime? now]) {
    final last = lastActiveAt;
    if (last == null) return false;
    return (now ?? DateTime.now()).difference(last) > AppConfig.roomStaleAfter;
  }

  /// Opens the app straight into the room (`synk://app/join/ABC234`).
  String get inviteLink => '${AppConfig.inviteScheme}://app/join/$code';

  factory Room.fromJson(String id, Json json) => Room(
    id: id,
    name: json.str('name', 'Untitled room'),
    code: json.str('code'),
    hostId: json.str('hostId'),
    hostName: json.str('hostName'),
    hostEmoji: json.str('hostEmoji', '🎧'),
    hostColor: json.integer('hostColor'),
    visibility: RoomVisibility.values.asNameMap()[json.str('visibility')] ?? RoomVisibility.public,
    mode: RoomMode.values.asNameMap()[json.str('mode')] ?? RoomMode.music,
    capacity: json.integer('capacity', AppConfig.defaultRoomCapacity),
    vibe: json.strOrNull('vibe'),
    coverColor: json.integer('coverColor'),
    listenerCount: json.integer('listenerCount'),
    isLive: json.boolean('isLive', true),
    closed: json.boolean('closed'),
    lastActiveAt: json.time('lastActiveAt'),
    nowPlaying: NowPlayingSummary.fromJson(json.json('nowPlaying')),
    createdAt: json.time('createdAt'),
  );

  @override
  bool operator ==(Object other) =>
      other is Room &&
      other.id == id &&
      other.name == name &&
      other.listenerCount == listenerCount &&
      other.isLive == isLive &&
      other.closed == closed &&
      other.nowPlaying == nowPlaying &&
      other.lastActiveAt == lastActiveAt;

  @override
  int get hashCode => Object.hash(id, name, listenerCount, isLive, closed, nowPlaying, lastActiveAt);
}
