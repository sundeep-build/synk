import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../catalog/domain/track.dart';
import '../domain/playlist.dart';

/// Likes: `users/{uid}/likes/{trackId}` (one doc per like → O(1) like/unlike).
/// Playlists: `users/{uid}/playlists/{id}` with embedded tracks.
class LibraryRepository {
  LibraryRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _likes(String uid) => _db.collection('users').doc(uid).collection('likes');
  CollectionReference<Map<String, dynamic>> _playlists(String uid) =>
      _db.collection('users').doc(uid).collection('playlists');

  Stream<List<Track>> likes(String uid) => _likes(uid)
      .orderBy('likedAt', descending: true)
      .limit(300)
      .snapshots()
      .map(
        (s) => [
          for (final d in s.docs)
            if (Track.tryParse(d.data()['track']) case final Track t) t,
        ],
      );

  Future<void> like(String uid, Track track) =>
      _likes(uid).doc(track.id).set({'track': track.toJson(), 'likedAt': FieldValue.serverTimestamp()});

  Future<void> unlike(String uid, String trackId) => _likes(uid).doc(trackId).delete();

  Stream<List<Playlist>> playlists(String uid) => _playlists(uid)
      .orderBy('updatedAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) Playlist.fromJson(d.id, d.data())]);

  Stream<Playlist?> playlist(String uid, String id) =>
      _playlists(uid).doc(id).snapshots().map((s) => s.exists ? Playlist.fromJson(s.id, s.data()!) : null);

  Future<String> createPlaylist(String uid, String name, {Track? firstTrack}) async {
    final ref = _playlists(uid).doc();
    await ref.set({
      'name': name.trim(),
      'tracks': [if (firstTrack != null) firstTrack.toJson()],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renamePlaylist(String uid, String id, String name) =>
      _playlists(uid).doc(id).update({'name': name.trim(), 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> deletePlaylist(String uid, String id) => _playlists(uid).doc(id).delete();

  /// Returns false when the track was already in the playlist.
  Future<bool> addToPlaylist(String uid, String playlistId, Track track) => _db.runTransaction((tx) async {
    final ref = _playlists(uid).doc(playlistId);
    final snap = await tx.get(ref);
    if (!snap.exists) throw const NotFoundException(message: 'Playlist not found.');
    final current = Playlist.fromJson(snap.id, snap.data()!);
    if (current.tracks.any((t) => t.id == track.id)) return false;
    if (current.tracks.length >= AppConfig.maxPlaylistTracks) {
      throw const ValidationException('Playlists can hold up to ${AppConfig.maxPlaylistTracks} songs.');
    }
    tx.update(ref, {
      'tracks': [...current.tracks.map((t) => t.toJson()), track.toJson()],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  });

  Future<void> removeFromPlaylist(String uid, String playlistId, String trackId) => _db.runTransaction((tx) async {
    final ref = _playlists(uid).doc(playlistId);
    final snap = await tx.get(ref);
    if (!snap.exists) return;
    final current = Playlist.fromJson(snap.id, snap.data()!);
    tx.update(ref, {
      'tracks': [
        for (final t in current.tracks)
          if (t.id != trackId) t.toJson(),
      ],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  });
}
