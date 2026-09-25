import 'package:firebase_database/firebase_database.dart';

import '../../../core/config/app_config.dart';
import '../../catalog/domain/track.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/room_live_models.dart';
import '../domain/room_playback.dart';

/// Everything real-time about a room, in Realtime Database:
///
/// ```
/// roomsLive/{roomId}/meta          hostId, capacity, closed
/// roomsLive/{roomId}/playback      the sync anchor (see RoomPlayback)
/// roomsLive/{roomId}/queue/{push}  upcoming tracks
/// roomsLive/{roomId}/presence/{uid}
/// roomsLive/{roomId}/skipVotes/{uid} = seq
/// roomChats/{roomId}/{push}        chat (separate tree: not downloaded
///                                  by anyone who only needs playback)
/// roomReactions/{roomId}/{push}    ephemeral emoji bursts
/// throttle/{uid}/{chat|react}      last write time, used by rules to
///                                  rate-limit spam without a server
/// ```
///
/// RTDB bills bandwidth, not operations — ideal for chatty, small payloads.
class RoomLiveDataSource {
  RoomLiveDataSource(this._db);

  final FirebaseDatabase _db;

  DatabaseReference _live(String roomId) => _db.ref('roomsLive/$roomId');

  // ── Streams ────────────────────────────────────────────────────────────
  Stream<RoomMeta?> meta(String roomId) =>
      _live(roomId).child('meta').onValue.map((e) => RoomMeta.fromJson(e.snapshot.value));

  Stream<RoomPlayback> playback(String roomId) =>
      _live(roomId).child('playback').onValue.map((e) => RoomPlayback.fromJson(e.snapshot.value));

  Stream<List<QueueItem>> queue(String roomId) => _live(roomId)
      .child('queue')
      .orderByKey()
      .limitToFirst(AppConfig.maxQueueLength)
      .onValue
      .map((e) => _children(e.snapshot, QueueItem.fromJson));

  Stream<List<RoomMember>> members(String roomId) => _live(roomId)
      .child('presence')
      .onValue
      .map((e) => _children(e.snapshot, RoomMember.fromJson)..sort((a, b) => a.joinedAt.compareTo(b.joinedAt)));

  Stream<Map<String, int>> skipVotes(String roomId) => _live(roomId).child('skipVotes').onValue.map((e) {
    final votes = <String, int>{};
    for (final c in e.snapshot.children) {
      if (c.key case final String uid when c.value is int) votes[uid] = c.value! as int;
    }
    return votes;
  });

  /// Last [AppConfig.chatPageSize] messages, then each new one as it arrives.
  Stream<ChatMessage> chat(String roomId) => _db
      .ref('roomChats/$roomId')
      .limitToLast(AppConfig.chatPageSize)
      .onChildAdded
      .map((e) => ChatMessage.fromJson(e.snapshot.key ?? '', e.snapshot.value))
      .where((m) => m != null)
      .cast<ChatMessage>();

  /// Only reactions sent after [sinceServerMs] — never replays history.
  Stream<Reaction> reactions(String roomId, {required int sinceServerMs}) => _db
      .ref('roomReactions/$roomId')
      .orderByChild('ts')
      .startAt(sinceServerMs)
      .onChildAdded
      .map((e) => Reaction.fromJson(e.snapshot.key ?? '', e.snapshot.value))
      .where((r) => r != null)
      .cast<Reaction>();

  /// The first [limit] people to join, for avatar previews outside the room.
  /// Indexed on `joinedAt` (database.rules.json), so only they are downloaded.
  Future<List<RoomMember>> presencePreview(String roomId, {int limit = 4}) async {
    final snap = await _live(roomId).child('presence').orderByChild('joinedAt').limitToFirst(limit).get();
    return _children(snap, RoomMember.fromJson)..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
  }

  Future<int> memberCount(String roomId) async {
    final snap = await _live(roomId).child('presence').get();
    return snap.children.length;
  }

  Future<bool> isMember(String roomId, String uid) async => (await _live(roomId).child('presence/$uid').get()).exists;

  // ── Presence ───────────────────────────────────────────────────────────
  /// Registers the server-side cleanup *before* announcing ourselves, so a
  /// crash between the two can never leave a ghost listener behind.
  Future<void> join(String roomId, UserProfile me) async {
    final ref = _live(roomId).child('presence/${me.uid}');
    await ref.onDisconnect().remove();
    await ref.set({
      'name': me.username,
      'emoji': me.avatarEmoji,
      'color': me.avatarColor,
      'joinedAt': ServerValue.timestamp,
    });
  }

  Future<void> leave(String roomId, String uid) async {
    final ref = _live(roomId).child('presence/$uid');
    await ref.onDisconnect().cancel();
    await ref.remove();
  }

  // ── Chat & reactions ───────────────────────────────────────────────────
  Future<void> sendMessage(
    String roomId,
    UserProfile me, {
    required String text,
    ChatKind kind = ChatKind.text,
    String? toName,
    Track? track,
  }) {
    final key = _db.ref('roomChats/$roomId').push().key!;
    // Multi-path write: message + throttle stamp succeed or fail together,
    // which is what lets the rules enforce "max 1 message per second".
    return _db.ref().update({
      'roomChats/$roomId/$key': {
        'uid': me.uid,
        'name': me.username,
        'emoji': me.avatarEmoji,
        'color': me.avatarColor,
        'text': text,
        'kind': kind.name,
        'ts': ServerValue.timestamp,
        'to': ?toName,
        if (track != null) 'track': track.toJson(),
      },
      'throttle/${me.uid}/chat': ServerValue.timestamp,
    });
  }

  Future<void> react(String roomId, String uid, String emoji) {
    final key = _db.ref('roomReactions/$roomId').push().key!;
    return _db.ref().update({
      'roomReactions/$roomId/$key': {'uid': uid, 'e': emoji, 'ts': ServerValue.timestamp},
      'throttle/$uid/react': ServerValue.timestamp,
    });
  }

  // ── Queue & votes ──────────────────────────────────────────────────────
  Future<void> addToQueue(String roomId, UserProfile me, Track track) => _live(roomId).child('queue').push().set({
    'track': track.toJson(),
    'by': me.uid,
    'byName': me.username,
    'at': ServerValue.timestamp,
  });

  Future<void> removeFromQueue(String roomId, String itemId) => _live(roomId).child('queue/$itemId').remove();

  Future<void> voteSkip(String roomId, String uid, int seq) => _live(roomId).child('skipVotes/$uid').set(seq);

  // ── Playback ───────────────────────────────────────────────────────────
  /// Host transport: play/pause/seek on the current track (same seq).
  Future<void> setTransport(
    String roomId, {
    required PlaybackStatus status,
    required int positionMs,
    required String by,
  }) => _live(roomId).child('playback').update({
    'status': status.name,
    'positionMs': positionMs,
    'updatedAt': ServerValue.timestamp,
    'by': by,
  });

  /// Atomically moves the room to [next] — only if nobody else already moved
  /// past [fromSeq]. Returns whether *this* client won.
  Future<bool> advance(
    String roomId, {
    required int fromSeq,
    required Track next,
    required String by,
    String? queueItemId,
  }) async {
    final result = await _live(roomId).child('playback').runTransaction((current) {
      if (RoomPlayback.fromJson(current).seq != fromSeq) return Transaction.abort();
      return Transaction.success({
        'track': next.toJson(),
        'status': PlaybackStatus.playing.name,
        'positionMs': 0,
        'updatedAt': ServerValue.timestamp,
        'seq': fromSeq + 1,
        'by': by,
        'qid': ?queueItemId,
      });
    }, applyLocally: false);
    return result.committed;
  }

  static List<T> _children<T>(DataSnapshot snap, T? Function(String key, Object? value) parse) => [
    for (final c in snap.children)
      if (c.key != null)
        if (parse(c.key!, c.value) case final T item) item,
  ];
}
