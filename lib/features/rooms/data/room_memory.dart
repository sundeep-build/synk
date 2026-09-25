import '../../../core/storage/local_store.dart';
import '../domain/remembered_rooms.dart';

/// [RememberedRooms] on this device, per signed-in user.
class RoomMemory {
  RoomMemory(this._store);

  final LocalStore _store;

  RememberedRooms of(String uid) => RememberedRooms.fromJson(_store.rooms, uid);

  Future<void> joined(String uid, String roomId) => _update(uid, (r) => r.join(roomId));

  Future<void> left(String uid) => _update(uid, (r) => r.leave());

  Future<void> forget(String uid, String roomId) => _update(uid, (r) => r.forget(roomId));

  Future<void> _update(String uid, RememberedRooms Function(RememberedRooms r) change) =>
      _store.setRooms(change(of(uid)).toJson());
}
