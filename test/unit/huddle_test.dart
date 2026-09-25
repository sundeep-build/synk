import 'package:flutter_test/flutter_test.dart';
import 'package:synk/features/rooms/domain/huddle_models.dart';
import 'package:synk/features/rooms/domain/huddle_rules.dart';

const _sdp =
    'v=0\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 63\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=0\r\n'
    'a=rtpmap:63 red/48000/2\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
    'a=rtpmap:96 VP8/90000\r\n';

void main() {
  group('HuddleRules.isOfferer', () {
    test('exactly one side of every pair offers', () {
      for (final (a, b) in [('alice', 'bob'), ('Zed', 'amy'), ('u1', 'u10')]) {
        expect(HuddleRules.isOfferer(a, b) != HuddleRules.isOfferer(b, a), isTrue, reason: '$a/$b');
      }
    });
  });

  group('video budget', () {
    test('per-peer cost falls as the huddle grows, within bounds', () {
      var lastRate = 1 << 30;
      var lastScale = 0.0;
      for (var peers = 1; peers <= 7; peers++) {
        final rate = HuddleRules.videoBitrate(peers);
        final scale = HuddleRules.videoScaleDown(peers);
        expect(rate, inInclusiveRange(150000, 600000));
        expect(rate, lessThanOrEqualTo(lastRate));
        expect(scale, greaterThanOrEqualTo(lastScale));
        lastRate = rate;
        lastScale = scale;
      }
      // Total upload for a full mesh stays around the 1.2 Mbps target.
      expect(HuddleRules.videoBitrate(7) * 7, lessThanOrEqualTo(1200000 + 150000));
    });

    test('never zero peers', () => expect(HuddleRules.videoBitrate(0), 600000));
  });

  group('HuddleRules.tuneOpus', () {
    test('merges into the existing Opus fmtp line, keeping other params', () {
      final out = HuddleRules.tuneOpus(_sdp);
      final fmtp = out.split('\r\n').firstWhere((l) => l.startsWith('a=fmtp:111 '));
      expect(fmtp, contains('minptime=10'));
      expect(fmtp, contains('useinbandfec=1'));
      expect(fmtp, isNot(contains('useinbandfec=0')));
      expect(fmtp, contains('usedtx=1'));
      expect(fmtp, contains('stereo=0'));
      expect(fmtp, contains('maxaveragebitrate=32000'));
      // Only that line changed.
      expect(out.split('\r\n').length, _sdp.split('\r\n').length);
      expect(out, contains('a=rtpmap:63 red/48000/2\r\n'));
    });

    test('adds an fmtp line when there is none', () {
      final out = HuddleRules.tuneOpus(_sdp.replaceFirst('a=fmtp:111 minptime=10;useinbandfec=0\r\n', ''));
      expect(out, contains('a=rtpmap:111 opus/48000/2\r\na=fmtp:111 usedtx=1;'));
    });

    test('is idempotent and leaves Opus-less SDPs alone', () {
      final once = HuddleRules.tuneOpus(_sdp);
      expect(HuddleRules.tuneOpus(once), once);
      const noOpus = 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n';
      expect(HuddleRules.tuneOpus(noOpus), noOpus);
    });
  });

  test('reconnect backoff doubles and caps', () {
    expect([for (var i = 0; i < 5; i++) HuddleRules.reconnectDelay(i).inSeconds], [2, 4, 8, 16, 16]);
  });

  group('HuddleSignal wire format', () {
    test('ICE batches round-trip through one string field', () {
      const signal = HuddleSignal(
        from: 'alice',
        fromSid: 'sidA',
        toSid: 'sidB',
        type: SignalType.ice,
        candidates: [
          (candidate: 'candidate:1 1 udp 2122260223 10.0.0.2 50000 typ host', sdpMid: '0', sdpMLineIndex: 0),
          (candidate: 'candidate:2 1 udp 1686052607 1.2.3.4 50001 typ srflx', sdpMid: null, sdpMLineIndex: null),
        ],
      );
      final json = signal.toJson();
      expect(json['c'], isA<String>());
      expect(json.containsKey('sdp'), isFalse);
      final back = HuddleSignal.fromJson('k1', json)!;
      expect(back.id, 'k1');
      expect(back.type, SignalType.ice);
      expect((back.from, back.fromSid, back.toSid), ('alice', 'sidA', 'sidB'));
      expect(back.candidates, signal.candidates);
    });

    test('garbage is dropped, not thrown', () {
      expect(HuddleSignal.fromJson('k', {'f': 'a', 't': 'hack'}), isNull);
      expect(HuddleSignal.fromJson('k', {'t': 'offer'}), isNull);
      expect(HuddleSignal.fromJson('k', 'nope'), isNull);
      expect(HuddleSignal.fromJson('k', {'f': 'a', 't': 'ice', 'c': '{not json'})!.candidates, isEmpty);
    });
  });

  test('HuddleMember needs a session id and defaults to mic on, camera off', () {
    expect(HuddleMember.fromJson('u', {'name': 'x'}), isNull);
    final m = HuddleMember.fromJson('u', {'name': 'maya', 'sid': 'abcdefgh', 'joinedAt': 5})!;
    expect((m.mic, m.cam, m.joinedAt), (true, false, 5));
    expect(
      HuddleRules.camerasOn([
        m,
        HuddleMember.fromJson('v', {'sid': 'abcdefgh', 'cam': true})!,
      ]),
      1,
    );
  });
}
