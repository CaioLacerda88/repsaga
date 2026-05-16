import 'package:hive/hive.dart';

import '../models/body_part.dart';

/// 24h dot-pulse window per body part (Phase 26b).
///
/// After a rank-up celebration is dismissed, [recordRankUp] writes the
/// trigger timestamp; `BodyPartRankRow` reads via [isPulsing] to decide
/// whether to render the glow-ring on the body-part dot.
///
/// **Why Hive (not Riverpod state):** the pulse must survive an app
/// restart — the user may dismiss a celebration overlay, force-quit the
/// app, and re-open the next morning to see the after-glow. An in-memory
/// notifier would lose the state on relaunch. The data is small (6 entries
/// max) so a dedicated box is fine; sharing with another box (e.g.
/// `workout_local_storage`) would couple unrelated lifetimes.
///
/// **Why ISO-8601 strings, not a typed adapter:** the box stores 6 entries
/// max; the serialization cost is negligible. A `TypeAdapter<DateTime>`
/// would add registration overhead at app startup for no real benefit.
///
/// **NOT in `cacheSchemaBoxes`:** pulse timestamps are durable user state,
/// not server-cached data. A schema-version bump should NOT wipe the active
/// pulse window. (Same lifetime contract as `offlineQueue`.)
class RankUpPulseRepository {
  RankUpPulseRepository({Box<dynamic>? box})
    : _box = box ?? Hive.box<dynamic>(boxName);

  static const String boxName = 'rank_up_pulse';
  static const Duration pulseDuration = Duration(hours: 24);

  final Box<dynamic> _box;

  /// Returns true iff [bodyPart] has an active pulse window at [now].
  /// Defaults [now] to `DateTime.now()` — overridable for tests.
  bool isPulsing(BodyPart bodyPart, {DateTime? now}) {
    final at = _box.get(bodyPart.dbValue);
    if (at == null) return false;
    final triggeredAt = DateTime.parse(at as String);
    final expiresAt = triggeredAt.add(pulseDuration);
    return (now ?? DateTime.now()).isBefore(expiresAt);
  }

  /// Mark [bodyPart] as having just ranked up. Subsequent [isPulsing]
  /// calls within [pulseDuration] of [at] return true. Overwrites any
  /// prior trigger for the same body part.
  Future<void> recordRankUp(BodyPart bodyPart, {DateTime? at}) async {
    final t = at ?? DateTime.now();
    await _box.put(bodyPart.dbValue, t.toIso8601String());
  }

  /// Defensive cleanup — clear expired entries. The UI tolerates expired
  /// entries ([isPulsing] handles it) so this is opportunistic, called by
  /// the provider on startup to keep the box from growing across years.
  Future<void> sweepExpired({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    final keysToDelete = <String>[];
    for (final key in _box.keys.cast<String>()) {
      final at = _box.get(key);
      if (at == null) continue;
      final triggeredAt = DateTime.parse(at as String);
      if (ref.isAfter(triggeredAt.add(pulseDuration))) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await _box.delete(key);
    }
  }
}
