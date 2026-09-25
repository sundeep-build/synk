import 'package:flutter/foundation.dart';

import '../../catalog/domain/track.dart';
import '../domain/room.dart';
import '../domain/room_live_models.dart';
import '../domain/room_playback.dart';
import '../sync/room_rules.dart';

/// Immutable snapshot of the room the user is currently in.
@immutable
class RoomSession {
  const RoomSession({
    required this.room,
    required this.myUid,
    this.playback = RoomPlayback.idle,
    this.queue = const [],
    this.members = const [],
    this.skipVotes = const {},
    this.playingItem,
    this.played = const [],
    this.locallyPaused = false,
    this.ended = false,
  });

  final Room room;
  final String myUid;
  final RoomPlayback playback;
  final List<QueueItem> queue;
  final List<RoomMember> members;
  final Map<String, int> skipVotes;

  /// Queue entry the current track came from. The live queue deletes an entry
  /// the moment it starts playing, so this keeps "added by" for the Now
  /// playing row. Null for autoplay picks, or if we joined mid-track.
  final QueueItem? playingItem;

  /// Tracks the room moved past while we were here, most recent first.
  final List<Track> played;

  static const maxPlayed = 30;

  /// A listener muted the room on their device only (room keeps playing).
  final bool locallyPaused;

  /// The host closed the room while we were in it.
  final bool ended;

  bool get isHost => room.hostId == myUid;
  bool get hostPresent => members.any((m) => m.uid == room.hostId);
  String? get leaderUid => RoomRules.leader(members, room.hostId);
  bool get isLeader => leaderUid == myUid;

  /// The host — or, while the host is away, the acting host (leader).
  /// Mirrors the "host absent" clause in `database.rules.json`.
  bool get canControl => isHost || (!hostPresent && isLeader);

  /// Queue minus the entry that's already playing.
  List<QueueItem> get upcoming =>
      playback.queueItemId == null ? queue : queue.where((q) => q.id != playback.queueItemId).toList();

  int get skipVotesForCurrent => RoomRules.countSkipVotes(skipVotes, playback.seq);
  int get skipThreshold => RoomRules.skipThreshold(members.length);
  bool get iVotedSkip => skipVotes[myUid] == playback.seq;

  /// Applies a new playback anchor. On a track change the finished track
  /// joins [played]; [known] holds every queue entry seen this session, so the
  /// new track's entry is found even if its delete arrived first.
  RoomSession withPlayback(RoomPlayback next, Map<String, QueueItem> known) {
    final finished = playback.track;
    final changed = next.seq != playback.seq;
    final qid = next.queueItemId;
    return copyWith(
      playback: next,
      playingItem: () => qid == null ? null : (known[qid] ?? (playingItem?.id == qid ? playingItem : null)),
      played: changed && finished != null
          ? [finished, ...played.where((t) => t.id != finished.id)].take(maxPlayed).toList()
          : null,
    );
  }

  RoomSession copyWith({
    Room? room,
    RoomPlayback? playback,
    List<QueueItem>? queue,
    List<RoomMember>? members,
    Map<String, int>? skipVotes,
    ValueGetter<QueueItem?>? playingItem,
    List<Track>? played,
    bool? locallyPaused,
    bool? ended,
  }) => RoomSession(
    room: room ?? this.room,
    myUid: myUid,
    playback: playback ?? this.playback,
    queue: queue ?? this.queue,
    members: members ?? this.members,
    skipVotes: skipVotes ?? this.skipVotes,
    playingItem: playingItem == null ? this.playingItem : playingItem(),
    played: played ?? this.played,
    locallyPaused: locallyPaused ?? this.locallyPaused,
    ended: ended ?? this.ended,
  );
}
