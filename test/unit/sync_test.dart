import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/catalog/domain/track.dart';
import 'package:synk/features/rooms/domain/room_live_models.dart';
import 'package:synk/features/rooms/domain/room_playback.dart';
import 'package:synk/features/rooms/sync/drift_corrector.dart';
import 'package:synk/features/rooms/sync/room_rules.dart';

const _song = Track(
  id: 'yt:dQw4w9WgXcQ',
  source: TrackSource.youtube,
  title: 'Song',
  artist: 'Artist',
  streamUrl: 'https://example.com/s',
  durationMs: 180000,
);

const _radio = Track(
  id: 'radio:xyz',
  source: TrackSource.radio,
  title: 'Station',
  artist: 'Live',
  streamUrl: 'https://example.com/r',
);

RoomMember _m(String uid, int joinedAt) => RoomMember(uid: uid, name: uid, emoji: '🎧', color: 0, joinedAt: joinedAt);

void main() {
  group('RoomPlayback.expectedPositionMs', () {
    test('advances with server time while playing', () {
      const p = RoomPlayback(track: _song, status: PlaybackStatus.playing, positionMs: 10000, updatedAt: 1000, seq: 1);
      expect(p.expectedPositionMs(6000), 15000);
    });

    test('is frozen while paused', () {
      const p = RoomPlayback(track: _song, status: PlaybackStatus.paused, positionMs: 42000, updatedAt: 1000, seq: 1);
      expect(p.expectedPositionMs(999999), 42000);
    });

    test('clamps to duration and ignores negative clock skew', () {
      const p = RoomPlayback(track: _song, status: PlaybackStatus.playing, positionMs: 170000, updatedAt: 1000, seq: 1);
      expect(p.expectedPositionMs(1000 + 60000), 180000);
      expect(p.expectedPositionMs(500), 170000);
    });

    test('hasEnded only for finished on-demand tracks', () {
      const p = RoomPlayback(track: _song, status: PlaybackStatus.playing, positionMs: 179800, updatedAt: 0, seq: 1);
      expect(p.hasEnded(0), isTrue);
      const live = RoomPlayback(track: _radio, status: PlaybackStatus.playing, positionMs: 0, updatedAt: 0, seq: 1);
      expect(live.hasEnded(999999999), isFalse);
    });

    test('parses RTDB payloads defensively', () {
      expect(RoomPlayback.fromJson(null), RoomPlayback.idle);
      final p = RoomPlayback.fromJson(<Object?, Object?>{
        'track': _song.toJson(),
        'status': 'playing',
        'positionMs': 5,
        'updatedAt': 10,
        'seq': 3,
        'qid': '-Nabc',
      });
      expect(p.isPlaying, isTrue);
      expect(p.seq, 3);
      expect(p.queueItemId, '-Nabc');
    });
  });

  group('DriftCorrector', () {
    const d = DriftCorrector();

    test('holds when in sync', () {
      expect(d.decide(expectedMs: 10000, actualMs: 10050, currentSpeed: 1), isA<SyncHold>());
    });

    test('nudges speed for small drift (slower when ahead, faster when behind)', () {
      final ahead = d.decide(expectedMs: 10000, actualMs: 10400, currentSpeed: 1);
      final behind = d.decide(expectedMs: 10000, actualMs: 9600, currentSpeed: 1);
      expect(ahead, isA<SyncRate>());
      expect((ahead as SyncRate).speed, lessThan(1));
      expect((behind as SyncRate).speed, greaterThan(1));
    });

    test('never exceeds ±6% speed change', () {
      final r = d.decide(expectedMs: 10000, actualMs: 10850, currentSpeed: 1) as SyncRate;
      expect(r.speed, greaterThanOrEqualTo(0.94));
    });

    test('seeks (with lead) for large drift', () {
      final s = d.decide(expectedMs: 30000, actualMs: 20000, currentSpeed: 1);
      expect(s, isA<SyncSeek>());
      expect((s as SyncSeek).positionMs, 30000 + d.seekLeadMs);
    });

    test('restores normal speed once back in sync', () {
      final r = d.decide(expectedMs: 10000, actualMs: 10010, currentSpeed: 1.03);
      expect(r, isA<SyncRate>());
      expect((r as SyncRate).speed, 1);
    });

    test('seek-only mode (YouTube) holds small drift and seeks past its threshold', () {
      expect(d.decide(expectedMs: 10000, actualMs: 10800, currentSpeed: 1, allowRate: false), isA<SyncHold>());
      final s = d.decide(expectedMs: 10000, actualMs: 12000, currentSpeed: 1, allowRate: false);
      expect(s, isA<SyncSeek>());
      expect((s as SyncSeek).positionMs, 10000 + d.seekLeadMs);
    });

    test('live radio is never time-corrected', () {
      expect(d.decide(expectedMs: 0, actualMs: 999999, currentSpeed: 1, isLive: true), isA<SyncHold>());
    });
  });

  group('RoomRules', () {
    test('host is always leader when present', () {
      expect(RoomRules.leader([_m('a', 1), _m('host', 50)], 'host'), 'host');
    });

    test('longest-present member leads when host is away; ties break by uid', () {
      expect(RoomRules.leader([_m('b', 5), _m('a', 9), _m('c', 5)], 'host'), 'b');
      expect(RoomRules.leader(const [], 'host'), isNull);
    });

    test('skip threshold is a simple majority', () {
      expect(RoomRules.skipThreshold(1), 1);
      expect(RoomRules.skipThreshold(2), 1);
      expect(RoomRules.skipThreshold(3), 2);
      expect(RoomRules.skipThreshold(10), 5);
    });

    test('only votes for the current track count', () {
      expect(RoomRules.countSkipVotes({'a': 4, 'b': 4, 'c': 3}, 4), 2);
    });

    test('leader advances immediately, others back off', () {
      expect(RoomRules.advanceDelay(isLeader: true, jitterMs: 900), Duration.zero);
      expect(RoomRules.advanceDelay(isLeader: false, jitterMs: 900), const Duration(milliseconds: 2400));
    });
  });
}
