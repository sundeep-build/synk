import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/catalog/domain/track.dart';
import 'package:synk/features/rooms/application/room_session.dart';
import 'package:synk/features/rooms/domain/room.dart';
import 'package:synk/features/rooms/domain/room_live_models.dart';
import 'package:synk/features/rooms/domain/room_playback.dart';
import 'package:synk/features/rooms/sync/room_rules.dart';

Track _t(String id) => Track(
  id: 'yt:$id',
  source: TrackSource.youtube,
  title: id,
  artist: 'Artist',
  streamUrl: 'https://example.com/$id',
  durationMs: 180000,
);

QueueItem _q(String id, Track track) =>
    QueueItem(id: id, track: track, addedBy: 'u2', addedByName: 'priya', addedAt: 0);

RoomPlayback _playing(Track t, int seq, {String? qid}) =>
    RoomPlayback(track: t, status: PlaybackStatus.playing, positionMs: 0, updatedAt: 0, seq: seq, queueItemId: qid);

const _room = Room(
  id: 'r1',
  name: 'Room',
  code: 'ABC123',
  hostId: 'u1',
  hostName: 'host',
  hostEmoji: '🎧',
  hostColor: 0,
  visibility: RoomVisibility.public,
  mode: RoomMode.music,
  capacity: 25,
);

void main() {
  final a = _t('aaaaaaaaaaa');
  final b = _t('bbbbbbbbbbb');
  final c = _t('ccccccccccc');

  test('a finished track moves to Played instead of vanishing', () {
    var s = const RoomSession(room: _room, myUid: 'u1');
    s = s.withPlayback(_playing(a, 1), const {});
    expect(s.played, isEmpty);
    s = s.withPlayback(_playing(b, 2), const {});
    expect(s.played.map((t) => t.id), [a.id]);
    s = s.withPlayback(_playing(c, 3), const {});
    expect(s.played.map((t) => t.id), [b.id, a.id]);
  });

  test('pause/seek on the same track does not add history', () {
    var s = const RoomSession(room: _room, myUid: 'u1').withPlayback(_playing(a, 1), const {});
    s = s.withPlayback(
      RoomPlayback(track: a, status: PlaybackStatus.paused, positionMs: 5000, updatedAt: 1, seq: 1),
      const {},
    );
    expect(s.played, isEmpty);
  });

  test('replaying a track keeps one Played entry, newest first, capped', () {
    var s = const RoomSession(room: _room, myUid: 'u1');
    var seq = 0;
    for (final t in [a, b, a, c]) {
      s = s.withPlayback(_playing(t, ++seq), const {});
    }
    expect(s.played.map((t) => t.id), [a.id, b.id]);

    for (var i = 0; i < RoomSession.maxPlayed + 5; i++) {
      s = s.withPlayback(_playing(_t('x${i.toString().padLeft(10, '0')}'), ++seq), const {});
    }
    expect(s.played.length, RoomSession.maxPlayed);
  });

  test('Now playing keeps "added by" after the entry leaves the live queue', () {
    final item = _q('-q1', b);
    var s = RoomSession(room: _room, myUid: 'u1', queue: [item]).withPlayback(_playing(a, 1), const {});
    s = s.withPlayback(_playing(b, 2, qid: '-q1'), {'-q1': item});
    expect(s.playingItem?.addedByName, 'priya');
    expect(s.upcoming, isEmpty, reason: 'the playing entry is not listed as up next');

    // Entry deleted from the live queue; a later transport update keeps it.
    s = s
        .copyWith(queue: const [])
        .withPlayback(
          RoomPlayback(
            track: b,
            status: PlaybackStatus.paused,
            positionMs: 1,
            updatedAt: 1,
            seq: 2,
            queueItemId: '-q1',
          ),
          const {},
        );
    expect(s.playingItem?.id, '-q1');

    // Autoplay pick (no queue entry) clears it.
    s = s.withPlayback(_playing(c, 3), const {});
    expect(s.playingItem, isNull);
  });

  test('"song ended" clears as soon as the room moves on', () {
    var s = const RoomSession(room: _room, myUid: 'u1').withPlayback(_playing(a, 1), const {});
    s = s.copyWith(songEnded: true);
    expect(s.withPlayback(_playing(b, 2), const {}).songEnded, isFalse, reason: 'next song');
    expect(
      s
          .withPlayback(
            RoomPlayback(track: a, status: PlaybackStatus.playing, positionMs: 0, updatedAt: 9, seq: 1),
            const {},
          )
          .songEnded,
      isFalse,
      reason: 'host restarted it',
    );
  });

  group('autoplay replay fallback (no YouTube key / quota used up)', () {
    test('plays what the room played longest ago, never the song that just ended', () {
      // Most recent first.
      expect(RoomRules.replayCandidate([c, b, a], currentId: c.id)?.id, a.id);
      expect(RoomRules.replayCandidate([c, b, a], currentId: a.id)?.id, b.id);
    });

    test('nothing to replay → null (the room waits for a queued song)', () {
      expect(RoomRules.replayCandidate(const []), isNull);
      expect(RoomRules.replayCandidate([a], currentId: a.id), isNull);
    });
  });
}
