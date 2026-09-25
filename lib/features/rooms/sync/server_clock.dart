import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// Server-aligned clock. Realtime Database measures each client's offset from
/// server time for free (`.info/serverTimeOffset`), which is exactly what
/// playback sync needs — no NTP, no Cloud Function.
class ServerClock {
  ServerClock(FirebaseDatabase db) {
    _sub = db.ref('.info/serverTimeOffset').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is num) _offsetMs = value.toInt();
    });
  }

  late final StreamSubscription<DatabaseEvent> _sub;
  int _offsetMs = 0;

  int get offsetMs => _offsetMs;

  int nowMs() => DateTime.now().millisecondsSinceEpoch + _offsetMs;

  Future<void> dispose() => _sub.cancel();
}
