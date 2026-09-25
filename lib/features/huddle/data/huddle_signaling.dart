import 'package:firebase_database/firebase_database.dart';

import '../../profile/domain/user_profile.dart';
import '../domain/huddle_models.dart';

/// A room's huddle in Realtime Database:
///
/// ```
/// huddles/{roomId}/members/{uid}          name, emoji, color, sid, mic, cam, joinedAt
/// huddles/{roomId}/signals/{uid}/{push}   that member's inbox of offers/answers/ICE
/// ```
///
/// Only signalling goes through Firebase (a few KB per connection). Voice and
/// video travel peer to peer, so they cost nothing on the free tier.
///
/// Each member reads only their own inbox, so signalling traffic per phone
/// grows with the group size, not with its square.
class HuddleSignaling {
  HuddleSignaling(this._db);

  final FirebaseDatabase _db;

  DatabaseReference _members(String roomId) => _db.ref('huddles/$roomId/members');
  DatabaseReference _inbox(String roomId, String uid) => _db.ref('huddles/$roomId/signals/$uid');

  /// Everyone in the huddle, earliest first (stable tile order).
  Stream<List<HuddleMember>> members(String roomId) => _members(roomId).onValue.map((e) {
    final list = [
      for (final c in e.snapshot.children)
        if (c.key != null) ?HuddleMember.fromJson(c.key!, c.value),
    ];
    return list..sort((a, b) => a.joinedAt != b.joinedAt ? a.joinedAt.compareTo(b.joinedAt) : a.uid.compareTo(b.uid));
  });

  /// New messages for [uid]. Each is delivered once; call [ack] when done.
  Stream<HuddleSignal> inbox(String roomId, String uid) => _inbox(roomId, uid).onChildAdded
      .map((e) => HuddleSignal.fromJson(e.snapshot.key ?? '', e.snapshot.value))
      .where((s) => s != null)
      .cast<HuddleSignal>();

  /// Registers server-side cleanup first, so a crash can never leave a ghost
  /// in the huddle, then clears leftovers from a previous session.
  Future<void> join(String roomId, UserProfile me, {required String sid, required bool mic}) async {
    final member = _members(roomId).child(me.uid);
    final inbox = _inbox(roomId, me.uid);
    await Future.wait([member.onDisconnect().remove(), inbox.onDisconnect().remove()]);
    await inbox.remove();
    await member.set({
      'name': me.username,
      'emoji': me.avatarEmoji,
      'color': me.avatarColor,
      'sid': sid,
      'mic': mic,
      'cam': false,
      'joinedAt': ServerValue.timestamp,
    });
  }

  Future<void> leave(String roomId, String uid) async {
    await Future.wait([
      _members(roomId).child(uid).onDisconnect().cancel(),
      _inbox(roomId, uid).onDisconnect().cancel(),
    ]);
    await _db.ref('huddles/$roomId').update({'members/$uid': null, 'signals/$uid': null});
  }

  Future<void> setMedia(String roomId, String uid, {bool? mic, bool? cam}) =>
      _members(roomId).child(uid).update({'mic': ?mic, 'cam': ?cam});

  Future<void> send(String roomId, {required String toUid, required HuddleSignal signal}) =>
      _inbox(roomId, toUid).push().set({...signal.toJson(), 'at': ServerValue.timestamp});

  /// Deletes handled messages in one write.
  Future<void> ack(String roomId, String uid, Iterable<String> ids) =>
      _inbox(roomId, uid).update({for (final id in ids) id: null});
}
