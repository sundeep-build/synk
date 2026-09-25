import '../domain/room_live_models.dart';

/// Pure decision helpers shared by the session controller and tests.
abstract final class RoomRules {
  /// The member that performs room chores (auto-advance, directory heartbeat):
  /// the host when present, otherwise whoever has been in the room longest.
  /// Deterministic on every client, so no extra writes are needed to elect.
  static String? leader(Iterable<RoomMember> members, String hostId) {
    RoomMember? oldest;
    for (final m in members) {
      if (m.uid == hostId) return hostId;
      if (oldest == null ||
          m.joinedAt < oldest.joinedAt ||
          (m.joinedAt == oldest.joinedAt && m.uid.compareTo(oldest.uid) < 0)) {
        oldest = m;
      }
    }
    return oldest?.uid;
  }

  /// Votes needed to skip: a simple majority of people in the room.
  static int skipThreshold(int listeners) => listeners <= 1 ? 1 : (listeners / 2).ceil();

  /// Counts votes cast for the *current* track only (stale votes are ignored).
  static int countSkipVotes(Map<String, int> votes, int currentSeq) =>
      votes.values.where((seq) => seq == currentSeq).length;

  /// Non-leaders wait before trying to auto-advance so the leader normally
  /// wins the transaction and nobody fetches a track for nothing.
  static Duration advanceDelay({required bool isLeader, required int jitterMs}) =>
      isLeader ? Duration.zero : Duration(milliseconds: 1500 + jitterMs);
}
