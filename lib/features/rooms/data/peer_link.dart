import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/huddle_models.dart';
import '../domain/huddle_rules.dart';

enum PeerStatus { connecting, connected, failed }

typedef PeerSend = Future<void> Function(SignalType type, {String? sdp, List<IceCandidateData> candidates});

/// One WebRTC connection to one other member of the huddle.
///
/// Both an audio and a video transceiver are negotiated up front (the video
/// one empty until a camera is on), so turning a camera on or off is a local
/// track swap. It never needs another offer/answer round trip.
class PeerLink {
  PeerLink._(this.uid, this.sid, this.offerer, this._pc, this._send, this._onChange);

  /// Opens a connection to [uid]'s session [sid]. The [offerer] side sends
  /// the offer right away; the other side waits for [acceptOffer].
  static Future<PeerLink> open({
    required String uid,
    required String sid,
    required bool offerer,
    required Map<String, dynamic> config,
    required MediaStream local,
    required MediaStreamTrack? video,
    required int peers,
    required PeerSend send,
    required void Function(PeerLink link) onChange,
  }) async {
    final pc = await createPeerConnection(config);
    final link = PeerLink._(uid, sid, offerer, pc, send, onChange).._wire();
    if (offerer) {
      try {
        await link._offer(local, video, peers);
      } catch (_) {
        await link.close();
        rethrow;
      }
    }
    return link;
  }

  /// Gives up on a connection that hasn't come up by then (lost signal,
  /// unreachable network); the controller decides whether to retry.
  static const _connectTimeout = Duration(seconds: 20);

  /// ICE candidates trickle out a few at a time; batching them saves writes.
  static const _iceBatch = Duration(milliseconds: 150);

  final String uid;
  final String sid;
  final bool offerer;
  final RTCPeerConnection _pc;
  final PeerSend _send;
  final void Function(PeerLink link) _onChange;

  RTCRtpTransceiver? _audio;
  RTCRtpTransceiver? _video;
  final List<IceCandidateData> _outIce = [];
  final List<IceCandidateData> _inIce = [];
  Timer? _iceTimer;
  Timer? _watchdog;
  bool _sdpSent = false;
  bool _remoteSet = false;
  bool _closed = false;

  /// Group size the video budget was last set for.
  int _peers = 1;

  PeerStatus status = PeerStatus.connecting;

  /// Their audio and video (the video track has frames only while their
  /// camera is on). Audio plays by itself; video needs a renderer.
  MediaStream? remoteStream;

  bool get closed => _closed;

  void _wire() {
    _pc
      ..onIceCandidate = (c) {
        final candidate = c.candidate;
        if (candidate == null || candidate.isEmpty) return;
        _outIce.add((candidate: candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex));
        _scheduleIce();
      }
      ..onTrack = (e) {
        if (e.streams.isEmpty) return;
        if (remoteStream?.id != e.streams.first.id) {
          remoteStream = e.streams.first;
          _onChange(this);
        }
      }
      ..onConnectionState = (s) {
        final next = switch (s) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected => PeerStatus.connected,
          RTCPeerConnectionState.RTCPeerConnectionStateFailed => PeerStatus.failed,
          // "disconnected" often heals by itself (brief network drop).
          _ => status == PeerStatus.connected ? PeerStatus.connecting : status,
        };
        _setStatus(next);
      };
    _watchdog = Timer(_connectTimeout, () {
      if (status != PeerStatus.connected) _setStatus(PeerStatus.failed);
    });
  }

  void _setStatus(PeerStatus next) {
    if (_closed || next == status) return;
    status = next;
    if (next == PeerStatus.connected) _watchdog?.cancel();
    _onChange(this);
  }

  // ── Negotiation ──────────────────────────────────────────────────────────
  Future<void> _offer(MediaStream local, MediaStreamTrack? video, int peers) async {
    final init = RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv, streams: [local]);
    _audio = await _pc.addTransceiver(track: local.getAudioTracks().first, init: init);
    _video = await _pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: init);
    if (video != null) await setVideo(video, peers);
    final offer = await _pc.createOffer();
    await _sendLocal(SignalType.offer, offer);
  }

  /// Answerer side: takes the offer, attaches our tracks to the transceivers
  /// it created, and answers.
  Future<void> acceptOffer(String sdp, MediaStream local, MediaStreamTrack? video, int peers) async {
    await _pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    await _remoteReady();
    for (final t in await _pc.getTransceivers()) {
      // Our offers always put audio at mid 0 and video at mid 1.
      final isVideo = (t.receiver.track?.kind ?? (t.mid == '1' ? 'video' : 'audio')) == 'video';
      if (isVideo) {
        _video = t;
        if (video != null) await t.sender.replaceTrack(video);
      } else {
        _audio = t;
        await t.sender.replaceTrack(local.getAudioTracks().first);
      }
      // Same stream id as the offerer's side, so tracks pair up remotely.
      await t.sender.setStreams([local]);
      await t.setDirection(TransceiverDirection.SendRecv);
    }
    final answer = await _pc.createAnswer();
    await _sendLocal(SignalType.answer, answer);
    if (video != null) await applyVideoBudget(peers);
  }

  Future<void> acceptAnswer(String sdp) async {
    if (!offerer || _remoteSet || _closed) return;
    await _pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    await _remoteReady();
    // Some encoders ignore limits set before negotiation; set them again.
    await applyVideoBudget(_peers);
  }

  Future<void> addIce(List<IceCandidateData> candidates) async {
    if (!_remoteSet) {
      _inIce.addAll(candidates);
      return;
    }
    for (final c in candidates) {
      await _pc.addCandidate(RTCIceCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex));
    }
  }

  Future<void> _remoteReady() async {
    _remoteSet = true;
    final queued = List.of(_inIce);
    _inIce.clear();
    await addIce(queued);
  }

  Future<void> _sendLocal(SignalType type, RTCSessionDescription desc) async {
    final tuned = RTCSessionDescription(HuddleRules.tuneOpus(desc.sdp ?? ''), desc.type);
    await _pc.setLocalDescription(tuned);
    await _send(type, sdp: tuned.sdp);
    // Candidates only after the description, so the other side never
    // receives ICE for a connection it hasn't created yet.
    _sdpSent = true;
    _scheduleIce();
  }

  void _scheduleIce() {
    if (!_sdpSent || _closed || _outIce.isEmpty) return;
    _iceTimer ??= Timer(_iceBatch, () {
      _iceTimer = null;
      if (_closed || _outIce.isEmpty) return;
      // Capped per write so a message stays inside the rules' size limit.
      final batch = _outIce.take(_maxIcePerWrite).toList();
      _outIce.removeRange(0, batch.length);
      _send(
        SignalType.ice,
        candidates: batch,
      ).catchError((Object e, StackTrace st) => AppLogger.error('HuddleIce', e, st));
      _scheduleIce();
    });
  }

  static const _maxIcePerWrite = 10;

  // ── Media ────────────────────────────────────────────────────────────────
  /// Starts or stops sending our camera ([track] null = off). No renegotiation.
  Future<void> setVideo(MediaStreamTrack? track, int peers) async {
    final sender = _video?.sender;
    if (sender == null || _closed) return;
    await sender.replaceTrack(track);
    if (track != null) await applyVideoBudget(peers);
  }

  /// Caps what our camera costs on this connection (see HuddleRules).
  Future<void> applyVideoBudget(int peers) async {
    _peers = peers;
    final sender = _video?.sender;
    if (sender == null || sender.track == null || _closed) return;
    try {
      await sender.setParameters(
        RTCRtpParameters(
          encodings: [
            RTCRtpEncoding(
              maxBitrate: HuddleRules.videoBitrate(peers),
              maxFramerate: HuddleRules.videoFps(peers),
              scaleResolutionDownBy: HuddleRules.videoScaleDown(peers),
            ),
          ],
          degradationPreference: RTCDegradationPreference.BALANCED,
        ),
      );
    } catch (e, st) {
      // Not fatal: the encoder's own congestion control still applies.
      AppLogger.error('HuddleVideoBudget', e, st);
    }
  }

  /// Their voice level (0–1), for the "talking" ring.
  Future<double> remoteLevel() => _level(_audio?.receiver.getStats(), 'inbound-rtp');

  /// Our own mic level as this connection sends it.
  Future<double> localLevel() => _level(_audio?.sender.getStats(), 'media-source');

  Future<double> _level(Future<List<StatsReport>>? stats, String type) async {
    if (stats == null || _closed) return 0;
    try {
      for (final r in await stats) {
        if (r.type == type && r.values['kind'] == 'audio') return (r.values['audioLevel'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {
      // Closing under us; a missed sample is harmless.
    }
    return 0;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _iceTimer?.cancel();
    _watchdog?.cancel();
    _pc
      ..onIceCandidate = null
      ..onTrack = null
      ..onConnectionState = null;
    remoteStream = null;
    try {
      await _pc.close();
      await _pc.dispose();
    } catch (e, st) {
      AppLogger.error('HuddlePeerClose', e, st);
    }
  }
}
