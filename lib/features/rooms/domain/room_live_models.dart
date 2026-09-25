import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';
import '../../catalog/domain/track.dart';

enum ChatKind { text, dedication, system }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.emoji,
    required this.color,
    required this.text,
    required this.kind,
    required this.ts,
    this.toName,
    this.track,
  });

  final String id;
  final String uid;
  final String name;
  final String emoji;
  final int color;
  final String text;
  final ChatKind kind;
  final int ts;

  /// Dedication recipient ("for @maya").
  final String? toName;

  /// Dedicated song.
  final Track? track;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  static ChatMessage? fromJson(String id, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    return ChatMessage(
      id: id,
      uid: raw.str('uid'),
      name: raw.str('name', 'someone'),
      emoji: raw.str('emoji', '🎧'),
      color: raw.integer('color'),
      text: raw.str('text'),
      kind: ChatKind.values.asNameMap()[raw.str('kind')] ?? ChatKind.text,
      ts: raw.integer('ts'),
      toName: raw.strOrNull('to'),
      track: Track.tryParse(raw['track']),
    );
  }
}

@immutable
class QueueItem {
  const QueueItem({
    required this.id,
    required this.track,
    required this.addedBy,
    required this.addedByName,
    required this.addedAt,
  });

  /// RTDB push id — lexicographically ordered by creation time.
  final String id;
  final Track track;
  final String addedBy;
  final String addedByName;
  final int addedAt;

  static QueueItem? fromJson(String id, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final track = Track.tryParse(raw['track']);
    if (track == null) return null;
    return QueueItem(
      id: id,
      track: track,
      addedBy: raw.str('by'),
      addedByName: raw.str('byName'),
      addedAt: raw.integer('at'),
    );
  }

  @override
  bool operator ==(Object other) => other is QueueItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class RoomMember {
  const RoomMember({
    required this.uid,
    required this.name,
    required this.emoji,
    required this.color,
    required this.joinedAt,
  });

  final String uid;
  final String name;
  final String emoji;
  final int color;
  final int joinedAt;

  static RoomMember? fromJson(String uid, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    return RoomMember(
      uid: uid,
      name: raw.str('name', 'listener'),
      emoji: raw.str('emoji', '🎧'),
      color: raw.integer('color'),
      joinedAt: raw.integer('joinedAt'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomMember && other.uid == uid && other.name == name && other.emoji == emoji;

  @override
  int get hashCode => Object.hash(uid, name, emoji);
}

/// Someone who joined a room and hasn't left it on purpose, whether they're
/// in it right now or not (`roomsLive/{id}/roster`).
@immutable
class RosterEntry {
  const RosterEntry({
    required this.uid,
    required this.name,
    required this.emoji,
    required this.color,
    required this.lastSeen,
  });

  final String uid;
  final String name;
  final String emoji;
  final int color;

  /// Server time (ms) they last joined, or their connection last dropped.
  final int lastSeen;

  /// Null for anything without a name (never a whole entry).
  static RosterEntry? fromJson(String uid, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final name = raw.str('name');
    if (name.isEmpty) return null;
    return RosterEntry(
      uid: uid,
      name: name,
      emoji: raw.str('emoji', '🎧'),
      color: raw.integer('color'),
      lastSeen: raw.integer('lastSeen'),
    );
  }
}

@immutable
class Reaction {
  const Reaction({required this.id, required this.uid, required this.emoji});

  final String id;
  final String uid;
  final String emoji;

  static const allowed = ['🔥', '❤️', '😂', '👏', '🎶', '😭'];

  static Reaction? fromJson(String id, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final emoji = raw.str('e');
    if (!allowed.contains(emoji)) return null;
    return Reaction(id: id, uid: raw.str('uid'), emoji: emoji);
  }
}

/// Room-level flags mirrored into RTDB so security rules can check them.
@immutable
class RoomMeta {
  const RoomMeta({required this.hostId, required this.capacity, this.closed = false});

  final String hostId;
  final int capacity;
  final bool closed;

  static RoomMeta? fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    return RoomMeta(hostId: raw.str('hostId'), capacity: raw.integer('capacity'), closed: raw.boolean('closed'));
  }
}
