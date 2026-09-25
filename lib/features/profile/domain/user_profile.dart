import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Public profile stored at `users/{uid}`.
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatarEmoji,
    required this.avatarColor,
    this.vibes = const [],
    this.isPro = false,
    this.createdAt,
  });

  final String uid;
  final String username;
  final String displayName;
  final String avatarEmoji;
  final int avatarColor;
  final List<String> vibes;
  final bool isPro;
  final DateTime? createdAt;

  String get firstName => displayName.split(' ').first;

  factory UserProfile.fromJson(String uid, Json json) => UserProfile(
    uid: uid,
    username: json.str('username'),
    displayName: json.str('displayName', json.str('username')),
    avatarEmoji: json.str('avatarEmoji', '🎧'),
    avatarColor: json.integer('avatarColor'),
    vibes: json.strings('vibes'),
    isPro: json.boolean('isPro'),
    createdAt: json.time('createdAt'),
  );

  UserProfile copyWith({String? displayName, String? avatarEmoji, int? avatarColor, List<String>? vibes}) =>
      UserProfile(
        uid: uid,
        username: username,
        displayName: displayName ?? this.displayName,
        avatarEmoji: avatarEmoji ?? this.avatarEmoji,
        avatarColor: avatarColor ?? this.avatarColor,
        vibes: vibes ?? this.vibes,
        isPro: isPro,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.uid == uid &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarEmoji == avatarEmoji &&
      other.avatarColor == avatarColor &&
      other.isPro == isPro &&
      listEquals(other.vibes, vibes);

  @override
  int get hashCode => Object.hash(uid, username, displayName, avatarEmoji, avatarColor, isPro, Object.hashAll(vibes));
}
