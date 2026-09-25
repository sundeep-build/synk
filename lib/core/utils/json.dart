import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore gives `Map<String, dynamic>`, Realtime Database gives
/// `Map<Object?, Object?>`. Both are read through these null-safe helpers so a
/// malformed document degrades to defaults instead of crashing a list.
typedef Json = Map<Object?, Object?>;

extension JsonRead on Map<Object?, Object?> {
  String str(String key, [String fallback = '']) => switch (this[key]) {
    final String s => s,
    _ => fallback,
  };

  String? strOrNull(String key) => switch (this[key]) {
    final String s when s.isNotEmpty => s,
    _ => null,
  };

  int integer(String key, [int fallback = 0]) => switch (this[key]) {
    final int i => i,
    final num n => n.toInt(),
    _ => fallback,
  };

  bool boolean(String key, [bool fallback = false]) => switch (this[key]) {
    final bool b => b,
    _ => fallback,
  };

  Json? json(String key) => switch (this[key]) {
    final Map<Object?, Object?> m => m,
    _ => null,
  };

  List<Object?> list(String key) => switch (this[key]) {
    final List<Object?> l => l,
    _ => const [],
  };

  List<String> strings(String key) => list(key).whereType<String>().toList(growable: false);

  /// Accepts Firestore [Timestamp] or epoch millis (RTDB server timestamps).
  DateTime? time(String key) => switch (this[key]) {
    final Timestamp t => t.toDate(),
    final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
    _ => null,
  };
}
