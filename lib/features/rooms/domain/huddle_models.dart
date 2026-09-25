import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Someone in a room's huddle (voice, plus camera if they turn it on).
@immutable
class HuddleMember {
  const HuddleMember({
    required this.uid,
    required this.name,
    required this.emoji,
    required this.color,
    required this.sid,
    required this.joinedAt,
    this.mic = true,
    this.cam = false,
  });

  final String uid;
  final String name;
  final String emoji;
  final int color;

  /// Random per join. A new sid means the member rejoined, so any connection
  /// to their previous session is stale and gets rebuilt.
  final String sid;
  final int joinedAt;
  final bool mic;
  final bool cam;

  static HuddleMember? fromJson(String uid, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final sid = raw.str('sid');
    if (sid.isEmpty) return null;
    return HuddleMember(
      uid: uid,
      name: raw.str('name', 'listener'),
      emoji: raw.str('emoji', '🎧'),
      color: raw.integer('color'),
      sid: sid,
      joinedAt: raw.integer('joinedAt'),
      mic: raw.boolean('mic', true),
      cam: raw.boolean('cam'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HuddleMember &&
      other.uid == uid &&
      other.sid == sid &&
      other.name == name &&
      other.emoji == emoji &&
      other.color == color &&
      other.mic == mic &&
      other.cam == cam;

  @override
  int get hashCode => Object.hash(uid, sid, name, emoji, color, mic, cam);
}

enum SignalType { offer, answer, ice }

/// One ICE candidate, independent of the WebRTC plugin's types.
typedef IceCandidateData = ({String candidate, String? sdpMid, int? sdpMLineIndex});

/// A WebRTC negotiation message, delivered through the recipient's RTDB inbox.
///
/// Addressed by session ([fromSid] → [toSid]), not just by user, so messages
/// that were meant for someone's previous join are ignored.
@immutable
class HuddleSignal {
  const HuddleSignal({
    required this.from,
    required this.fromSid,
    required this.toSid,
    required this.type,
    this.id = '',
    this.sdp,
    this.candidates = const [],
  });

  /// RTDB push key ('' before sending).
  final String id;
  final String from;
  final String fromSid;
  final String toSid;
  final SignalType type;

  /// Offer/answer body.
  final String? sdp;

  /// ICE candidates, batched so one write carries several.
  final List<IceCandidateData> candidates;

  static HuddleSignal? fromJson(String id, Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final type = SignalType.values.asNameMap()[raw.str('t')];
    final from = raw.str('f');
    if (type == null || from.isEmpty) return null;
    return HuddleSignal(
      id: id,
      from: from,
      fromSid: raw.str('fs'),
      toSid: raw.str('ts'),
      type: type,
      sdp: raw.strOrNull('sdp'),
      candidates: _decodeCandidates(raw.strOrNull('c')),
    );
  }

  /// Wire format. `at` (server time) is added by the data source.
  Map<String, Object> toJson() => {
    'f': from,
    'fs': fromSid,
    'ts': toSid,
    't': type.name,
    'sdp': ?sdp,
    if (candidates.isNotEmpty)
      // One string field: simpler rules than validating a nested list.
      'c': jsonEncode([
        for (final c in candidates) {'c': c.candidate, 'm': c.sdpMid, 'i': c.sdpMLineIndex},
      ]),
  };

  static List<IceCandidateData> _decodeCandidates(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final c in list)
          if (c is Map && c['c'] is String)
            (candidate: c['c'] as String, sdpMid: c['m'] as String?, sdpMLineIndex: (c['i'] as num?)?.toInt()),
      ];
    } on FormatException {
      return const [];
    }
  }
}
