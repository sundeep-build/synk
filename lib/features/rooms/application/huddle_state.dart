import 'package:flutter/foundation.dart';

import '../data/peer_link.dart';
import '../domain/huddle_models.dart';

enum HuddlePhase { idle, joining, live }

/// The user's own huddle session (voice call inside the room they're in).
@immutable
class HuddleState {
  const HuddleState({
    this.roomId,
    this.myUid,
    this.phase = HuddlePhase.idle,
    this.members = const [],
    this.peers = const {},
    this.mic = true,
    this.cam = false,
    this.frontCamera = true,
    this.speaker = true,
    this.revision = 0,
  });

  final String? roomId;
  final String? myUid;
  final HuddlePhase phase;

  /// Everyone in the huddle, us included, in join order.
  final List<HuddleMember> members;

  /// Connection to each other member, by uid.
  final Map<String, PeerStatus> peers;

  final bool mic;
  final bool cam;
  final bool frontCamera;
  final bool speaker;

  /// Bumps when a connection or its remote stream changes, so video tiles
  /// pick up the new stream.
  final int revision;

  bool get live => phase == HuddlePhase.live;

  HuddleMember? member(String uid) => members.where((m) => m.uid == uid).firstOrNull;

  HuddleState copyWith({
    HuddlePhase? phase,
    List<HuddleMember>? members,
    Map<String, PeerStatus>? peers,
    bool? mic,
    bool? cam,
    bool? frontCamera,
    bool? speaker,
    bool bump = false,
  }) => HuddleState(
    roomId: roomId,
    myUid: myUid,
    phase: phase ?? this.phase,
    members: members ?? this.members,
    peers: peers ?? this.peers,
    mic: mic ?? this.mic,
    cam: cam ?? this.cam,
    frontCamera: frontCamera ?? this.frontCamera,
    speaker: speaker ?? this.speaker,
    revision: bump ? revision + 1 : revision,
  );
}
