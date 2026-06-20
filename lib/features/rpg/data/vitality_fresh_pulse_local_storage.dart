import 'package:hive/hive.dart';

import '../models/body_part.dart';

/// 24h "charged today" pulse window per body part (Phase Vitality PR 2).
///
/// Sibling of [RankUpPulseLocalStorage] (same API shape, same lifetime
/// contract), but a SECOND trigger source for the saga-row pulse: after a
/// saved session, [recordCharged] is written for every body part trained
/// (not just the ones that ranked up). `BodyPartRankRow` ORs this with the
/// rank-up pulse so a row reads "fresh today" for 24h after the user lifts
/// it, reflecting the save-time vitality rebuild (PR 1) — no new visual,
/// just a second trigger feeding the existing emphasis styling.
///
/// **Why a separate box from `rank_up_pulse`:** the two pulses have
/// different trigger semantics (every-trained-bp vs rank-up-only) and the
/// rank-up box is written from the celebration orchestrator AFTER the
/// celebration plays. Sharing one box would entangle the two lifecycles and
/// make a rank-up's longer-lived emphasis indistinguishable from a plain
/// fresh-today pulse if the policy ever diverges. Both stay durable
/// (excluded from `cacheSchemaBoxes`).
///
/// **Why Hive (not Riverpod state):** the pulse must survive an app restart
/// — the user finishes a workout, force-quits, re-opens later, and the saga
/// rows should still read "fresh today" within the 24h window. Same
/// rationale as [RankUpPulseLocalStorage].
///
/// **Why ISO-8601 strings, not a typed adapter:** 6 entries max; the
/// serialization cost is negligible and a `TypeAdapter<DateTime>` would add
/// startup registration overhead for no benefit.
class VitalityFreshPulseLocalStorage {
  VitalityFreshPulseLocalStorage({Box<dynamic>? box})
    : _box = box ?? Hive.box<dynamic>(boxName);

  static const String boxName = 'vitality_fresh_pulse';
  static const Duration pulseDuration = Duration(hours: 24);

  final Box<dynamic> _box;

  /// Returns true iff [bodyPart] has an active fresh-today window at [now].
  /// Defaults [now] to `DateTime.now()` — overridable for tests.
  bool isPulsing(BodyPart bodyPart, {DateTime? now}) {
    final at = _box.get(bodyPart.dbValue);
    if (at == null) return false;
    try {
      final triggeredAt = DateTime.parse(at as String);
      final expiresAt = triggeredAt.add(pulseDuration);
      return (now ?? DateTime.now()).isBefore(expiresAt);
    } on FormatException {
      // Corrupted Hive entry — treat as "no pulse"; calling from build()
      // must never throw.
      return false;
    }
  }

  /// Mark [bodyPart] as freshly charged. Subsequent [isPulsing] calls within
  /// [pulseDuration] of [at] return true. Overwrites any prior trigger for
  /// the same body part (a fresh save re-arms the full 24h window).
  Future<void> recordCharged(BodyPart bodyPart, {DateTime? at}) async {
    final t = at ?? DateTime.now();
    await _box.put(bodyPart.dbValue, t.toIso8601String());
  }

  /// Record a batch of trained body parts in one pass — the save-flow
  /// helper. Skips nothing; re-arming an already-pulsing bp is intentional
  /// (the most recent save anchors the window).
  Future<void> recordChargedBatch(
    Iterable<BodyPart> bodyParts, {
    DateTime? at,
  }) async {
    final t = at ?? DateTime.now();
    for (final bp in bodyParts) {
      await recordCharged(bp, at: t);
    }
  }

  /// Defensive cleanup — clear expired entries. Opportunistic; the UI
  /// tolerates expired entries ([isPulsing] handles them). Called by the
  /// provider on startup to keep the box bounded over years.
  Future<void> sweepExpired({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    final keysToDelete = <String>[];
    for (final key in _box.keys.cast<String>()) {
      final at = _box.get(key);
      if (at == null) continue;
      try {
        final triggeredAt = DateTime.parse(at as String);
        if (ref.isAfter(triggeredAt.add(pulseDuration))) {
          keysToDelete.add(key);
        }
      } on FormatException {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await _box.delete(key);
    }
  }
}
