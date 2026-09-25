import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/error/app_exception.dart';
import '../domain/user_profile.dart';

/// `users/{uid}` profiles + `usernames/{name}` reservations.
///
/// Username uniqueness is enforced by a transaction here AND by security
/// rules (a reservation doc can only be created once, by its owner), so two
/// people racing for the same name can never both win.
class UserRepository {
  UserRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _names => _db.collection('usernames');

  Stream<UserProfile?> watch(String uid) =>
      _users.doc(uid).snapshots().map((s) => s.exists ? UserProfile.fromJson(uid, s.data()!) : null);

  Future<bool> isUsernameAvailable(String username) async {
    final doc = await _names.doc(username.trim().toLowerCase()).get();
    return !doc.exists;
  }

  Future<void> createProfile({
    required String uid,
    required String username,
    required String avatarEmoji,
    required int avatarColor,
    required List<String> vibes,
  }) async {
    final name = username.trim().toLowerCase();
    try {
      await _db.runTransaction((tx) async {
        final nameRef = _names.doc(name);
        if ((await tx.get(nameRef)).exists) {
          throw const ValidationException('That username was just taken — try another.');
        }
        tx.set(nameRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.set(_users.doc(uid), {
          'username': name,
          'displayName': name,
          'avatarEmoji': avatarEmoji,
          'avatarColor': avatarColor,
          'vibes': vibes,
          'isPro': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException.from(e);
    }
  }

  Future<void> updateProfile(UserProfile profile) => _users.doc(profile.uid).update({
    'displayName': profile.displayName,
    'avatarEmoji': profile.avatarEmoji,
    'avatarColor': profile.avatarColor,
    'vibes': profile.vibes,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Removes profile data. Subcollections (likes, playlists) are deleted in
  /// small batches to stay within the free tier's per-request limits.
  Future<void> deleteProfile(UserProfile profile) async {
    for (final sub in ['likes', 'playlists']) {
      while (true) {
        final page = await _users.doc(profile.uid).collection(sub).limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
    final batch = _db.batch()
      ..delete(_users.doc(profile.uid))
      ..delete(_names.doc(profile.username));
    await batch.commit();
  }
}
