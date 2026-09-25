import 'package:flutter/foundation.dart';

/// Rooms a user joined on this device, newest first, so Home can list them
/// after the app closes (no code needed to get back in), and the room they
/// were in when it closed, which the app reopens on the next launch.
///
/// Kept on the device, per user: nothing to read or write in Firestore.
@immutable
class RememberedRooms {
  const RememberedRooms({required this.uid, this.joined = const [], this.active});

  static const int max = 10;

  final String uid;
  final List<String> joined;

  /// The room the user was in when the app last closed. Null once they left
  /// it on purpose (Leave, Exit), so it isn't reopened.
  final String? active;

  RememberedRooms join(String roomId) => RememberedRooms(
    uid: uid,
    joined: [roomId, ...joined.where((id) => id != roomId)].take(max).toList(),
    active: roomId,
  );

  /// Left on purpose: still listed, not reopened.
  RememberedRooms leave() => RememberedRooms(uid: uid, joined: joined);

  /// Ended, gone, or removed from the list by the user.
  RememberedRooms forget(String roomId) => RememberedRooms(
    uid: uid,
    joined: [...joined.where((id) => id != roomId)],
    active: active == roomId ? null : active,
  );

  Map<String, Object?> toJson() => {'uid': uid, 'joined': joined, 'active': ?active};

  /// Another user's rooms (someone else signed in on this device) read as none.
  static RememberedRooms fromJson(Map<String, Object?>? json, String uid) {
    if (json == null || json['uid'] != uid) return RememberedRooms(uid: uid);
    final joined = json['joined'];
    final active = json['active'];
    return RememberedRooms(
      uid: uid,
      joined: joined is List ? [...joined.whereType<String>()] : const [],
      active: active is String ? active : null,
    );
  }
}
