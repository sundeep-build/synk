import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../auth/application/session.dart';
import '../../catalog/domain/track.dart';
import '../data/library_repository.dart';
import '../domain/playlist.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) => LibraryRepository(ref.watch(firestoreProvider)));

final _uidProvider = Provider<String?>((ref) => ref.watch(currentProfileProvider.select((p) => p?.uid)));

final likedTracksProvider = StreamProvider<List<Track>>((ref) {
  final uid = ref.watch(_uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(libraryRepositoryProvider).likes(uid);
});

/// O(1) "is this liked?" for every heart icon, derived from the one listener
/// above — no per-track reads.
final likedIdsProvider = Provider<Set<String>>(
  (ref) => {for (final t in ref.watch(likedTracksProvider).value ?? const <Track>[]) t.id},
);

final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  final uid = ref.watch(_uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(libraryRepositoryProvider).playlists(uid);
});

final playlistProvider = StreamProvider.autoDispose.family<Playlist?, String>((ref, id) {
  final uid = ref.watch(_uidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(libraryRepositoryProvider).playlist(uid, id);
});

final recentTracksProvider = Provider.autoDispose<List<Track>>(
  (ref) => [
    for (final json in ref.watch(localStoreProvider).recentTracks)
      if (Track.tryParse(json) case final Track t) t,
  ],
);

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);

class LibraryActions {
  LibraryActions(this._ref);

  final Ref _ref;

  String get _uid => _ref.read(_uidProvider)!;
  LibraryRepository get _repo => _ref.read(libraryRepositoryProvider);

  Future<void> toggleLike(Track track) {
    final liked = _ref.read(likedIdsProvider).contains(track.id);
    return liked ? _repo.unlike(_uid, track.id) : _repo.like(_uid, track);
  }

  Future<String> createPlaylist(String name, {Track? firstTrack}) =>
      _repo.createPlaylist(_uid, name, firstTrack: firstTrack);

  Future<bool> addToPlaylist(String playlistId, Track track) => _repo.addToPlaylist(_uid, playlistId, track);

  Future<void> removeFromPlaylist(String playlistId, String trackId) =>
      _repo.removeFromPlaylist(_uid, playlistId, trackId);

  Future<void> renamePlaylist(String playlistId, String name) => _repo.renamePlaylist(_uid, playlistId, name);

  Future<void> deletePlaylist(String playlistId) => _repo.deletePlaylist(_uid, playlistId);
}
