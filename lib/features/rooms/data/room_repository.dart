import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/utils/room_code.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/room.dart';

/// Room directory in Firestore (`rooms/{id}`, `roomCodes/{code}`).
///
/// Reads are budgeted: discovery is a one-shot query (cached ~60s by the
/// provider), not a live listener — a live listener would bill every viewer
/// for every heartbeat of every room.
class RoomRepository {
  RoomRepository(this._db, this._rtdb);

  final FirebaseFirestore _db;
  final FirebaseDatabase _rtdb;

  CollectionReference<Map<String, dynamic>> get _rooms => _db.collection('rooms');
  CollectionReference<Map<String, dynamic>> get _codes => _db.collection('roomCodes');

  Future<Room> create({
    required UserProfile host,
    required String name,
    required RoomVisibility visibility,
    required RoomMode mode,
    required int capacity,
    String? vibe,
  }) async {
    final roomRef = _rooms.doc();
    final coverColor = roomRef.id.hashCode.abs() % 8;

    for (var attempt = 0; attempt < 5; attempt++) {
      final code = RoomCode.generate();
      final data = {
        'name': name.trim(),
        'code': code,
        'hostId': host.uid,
        'hostName': host.username,
        'hostEmoji': host.avatarEmoji,
        'hostColor': host.avatarColor,
        'visibility': visibility.name,
        'mode': mode.name,
        'capacity': capacity,
        'vibe': vibe,
        'coverColor': coverColor,
        'listenerCount': 0,
        'isLive': true,
        'nowPlaying': null,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      };
      try {
        await _db.runTransaction((tx) async {
          final codeRef = _codes.doc(code);
          if ((await tx.get(codeRef)).exists) throw const _CodeCollision();
          tx
            ..set(codeRef, {'roomId': roomRef.id, 'createdBy': host.uid})
            ..set(roomRef, data);
        });
      } on _CodeCollision {
        continue;
      }

      // Mirror what the RTDB security rules need to authorise live writes.
      await _rtdb.ref('roomsLive/${roomRef.id}/meta').set({
        'hostId': host.uid,
        'capacity': capacity,
        'closed': false,
        'createdAt': ServerValue.timestamp,
      });

      return Room(
        id: roomRef.id,
        name: name.trim(),
        code: code,
        hostId: host.uid,
        hostName: host.username,
        hostEmoji: host.avatarEmoji,
        hostColor: host.avatarColor,
        visibility: visibility,
        mode: mode,
        capacity: capacity,
        vibe: vibe,
        coverColor: coverColor,
        lastActiveAt: DateTime.now(),
      );
    }
    throw const UnknownException(cause: 'Could not allocate a unique room code');
  }

  Future<String> resolveCode(String rawCode) async {
    final code = RoomCode.normalize(rawCode);
    if (!RoomCode.isValid(code)) {
      throw const ValidationException('Room codes are 6 letters/numbers.');
    }
    final doc = await _codes.doc(code).get();
    final roomId = doc.data()?['roomId'];
    if (roomId is! String) throw const NotFoundException(message: 'No room with that code.');
    return roomId;
  }

  Future<Room> get(String roomId) async {
    final doc = await _rooms.doc(roomId).get();
    if (!doc.exists) throw const NotFoundException(message: 'This room no longer exists.');
    return Room.fromJson(doc.id, doc.data()!);
  }

  Stream<Room?> watch(String roomId) =>
      _rooms.doc(roomId).snapshots().map((s) => s.exists ? Room.fromJson(s.id, s.data()!) : null);

  Future<List<Room>> liveRooms({int limit = 20}) async => (await liveRoomsPage(limit: limit)).rooms;

  /// One page of the public live-room directory, busiest first. Pass the
  /// previous page's [RoomPage.cursor] as [after] to continue.
  Future<RoomPage> liveRoomsPage({Object? after, int limit = 20}) async {
    var query = _rooms
        .where('visibility', isEqualTo: RoomVisibility.public.name)
        .where('isLive', isEqualTo: true)
        .orderBy('listenerCount', descending: true)
        .limit(limit);
    if (after is DocumentSnapshot<Map<String, dynamic>>) query = query.startAfterDocument(after);
    final snap = await query.get();
    final now = DateTime.now();
    final docs = snap.docs;
    return RoomPage(
      rooms: [
        for (final d in docs)
          if (Room.fromJson(d.id, d.data()) case final r when !r.isStale(now) && r.listenerCount > 0) r,
      ],
      cursor: docs.isEmpty ? after : docs.last,
      // Sorted busiest first: once a page reaches empty rooms, the rest are too.
      hasMore: docs.length == limit && (docs.last.data()['listenerCount'] as num? ?? 0) > 0,
    );
  }

  /// Rooms [uid] hosts that haven't been ended, newest first. A room drops
  /// out of Live now once everyone has left (or the app was closed), so this
  /// is how its host finds it again.
  Future<List<Room>> hostedBy(String uid, {int limit = 10}) async {
    final snap = await _rooms
        .where('hostId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return [
      for (final d in snap.docs)
        if (Room.fromJson(d.id, d.data()) case final r when !r.closed) r,
    ];
  }

  /// Directory refresh written by the room leader (see RoomRules.leader).
  Future<void> heartbeat(String roomId, {required int listenerCount, required NowPlayingSummary? nowPlaying}) =>
      _rooms.doc(roomId).update({
        'listenerCount': listenerCount,
        'isLive': true,
        'nowPlaying': nowPlaying?.toJson(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

  /// Last person out turns the lights off.
  Future<void> markIdle(String roomId) =>
      _rooms.doc(roomId).update({'listenerCount': 0, 'isLive': false, 'lastActiveAt': FieldValue.serverTimestamp()});

  /// Host ends the room for everyone, for good.
  Future<void> close(String roomId) async {
    await _rtdb.ref('roomsLive/$roomId/meta/closed').set(true);
    await _rooms.doc(roomId).update({
      'closed': true,
      'listenerCount': 0,
      'isLive': false,
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }
}

/// A page of live rooms plus where to continue from.
@immutable
class RoomPage {
  const RoomPage({required this.rooms, required this.cursor, required this.hasMore});

  /// Rooms worth showing (stale and empty ones are filtered out, so a page can
  /// hold fewer than were asked for even when [hasMore] is true).
  final List<Room> rooms;

  /// Opaque continuation token for the next call.
  final Object? cursor;
  final bool hasMore;
}

class _CodeCollision implements Exception {
  const _CodeCollision();
}
