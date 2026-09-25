import 'package:flutter/foundation.dart';

/// What the local player should do to stay in sync with the room.
sealed class SyncAction {
  const SyncAction();
}

final class SyncHold extends SyncAction {
  const SyncHold();
}

/// Large drift (joining late, buffering stall): jump.
final class SyncSeek extends SyncAction {
  const SyncSeek(this.positionMs);
  final int positionMs;
}

/// Small drift: nudge playback speed so the correction is inaudible.
final class SyncRate extends SyncAction {
  const SyncRate(this.speed);
  final double speed;
}

/// Decides how to correct drift between the local player and the room anchor.
///
/// * |drift| < [softThresholdMs]  → play at 1.0x (hold)
/// * |drift| < [hardThresholdMs]  → play at 1 ± up to [maxRateDelta] so the
///   gap closes over ~[correctionWindowMs] (±6% is below what listeners notice)
/// * otherwise                    → seek, landing [seekLeadMs] ahead to absorb
///   the time the player needs to resume after a seek
@immutable
class DriftCorrector {
  const DriftCorrector({
    this.softThresholdMs = 120,
    this.hardThresholdMs = 900,
    this.maxRateDelta = 0.06,
    this.correctionWindowMs = 4000,
    this.seekLeadMs = 250,
    this.seekOnlyThresholdMs = 1500,
  });

  final int softThresholdMs;
  final int hardThresholdMs;
  final double maxRateDelta;
  final int correctionWindowMs;
  final int seekLeadMs;

  /// Players without fine speed control (YouTube) only seek, and only past this
  /// larger threshold — every YouTube seek briefly re-buffers.
  final int seekOnlyThresholdMs;

  SyncAction decide({
    required int expectedMs,
    required int actualMs,
    required double currentSpeed,
    bool isLive = false,
    bool allowRate = true,
  }) {
    // Live radio has no shared timeline; everyone just hears "now".
    if (isLive) return currentSpeed == 1 ? const SyncHold() : const SyncRate(1);

    final drift = actualMs - expectedMs; // > 0: we're ahead of the room
    final magnitude = drift.abs();

    if (!allowRate) {
      return magnitude >= seekOnlyThresholdMs ? SyncSeek(expectedMs + seekLeadMs) : const SyncHold();
    }

    if (magnitude >= hardThresholdMs) return SyncSeek(expectedMs + seekLeadMs);

    if (magnitude >= softThresholdMs) {
      final raw = 1 - drift / correctionWindowMs;
      final clamped = raw.clamp(1 - maxRateDelta, 1 + maxRateDelta);
      final speed = (clamped * 100).roundToDouble() / 100;
      return speed == currentSpeed ? const SyncHold() : SyncRate(speed);
    }

    return currentSpeed == 1 ? const SyncHold() : const SyncRate(1);
  }
}
