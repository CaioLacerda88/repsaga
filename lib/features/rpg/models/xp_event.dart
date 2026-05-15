// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'xp_event.freezed.dart';
part 'xp_event.g.dart';

/// Polymorphic event log row (spec §11.1, locked decision D4).
///
/// v1 records `event_type = 'set'` with `set_id` populated and
/// `session_id` (the workout) populated. v2 will record
/// `event_type = 'cardio_session' | 'hr_zone' | 'kcal'` without schema
/// rework — the `source_payload` JSONB is the polymorphic shape.
///
/// `setId` and `sessionId` are surfaced as first-class FK columns (rather
/// than burying them in `source_payload`) to enable indexed lookups for
/// per-workout celebration replay (Phase 18c) and per-set audit trails
/// (debugging XP discrepancies in production).
@freezed
abstract class XpEvent with _$XpEvent {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory XpEvent({
    required String id,
    required String userId,
    required String eventType, // 'set' in v1; 'cardio_session' etc in v2
    String? setId, // FK to sets.id when event_type = 'set'
    String?
    sessionId, // FK to workouts.id (the session) when event_type = 'set'
    String? sourceType, // free-form discriminator within event_type
    Map<String, dynamic>? sourcePayload,
    required Map<String, dynamic> payload, // breakdown components
    required Map<String, dynamic> attribution, // {chest: xp_to_chest, ...}
    required double totalXp,
    // Per-exercise difficulty composite snapshotted at write time
    // (Phase 24a). Nullable because legacy events written before the
    // 24a migration don't carry this field; the SQL RPC populates it
    // for every set written under the new function. Consumers that
    // need the value should fall back to 1.0 when null.
    //
    // Storage shape: this field is NOT a top-level column on
    // `xp_events` — it's snapshotted INSIDE `payload` as
    // `payload.difficulty_mult` by `record_set_xp` /
    // `record_session_xp_batch` / `_rpg_backfill_chunk` (migration
    // 00054). The `fromJson` factory below promotes that nested key to
    // the top level so the generated deserializer reads it where it
    // expects. See the factory's docstring for promotion rules.
    double? difficultyMult,
    // Effective load (kg) actually plugged into the volume / strength
    // formulas at write time (Phase 24c). Equals
    // `entered_weight + profile.bodyweight_kg` when the exercise is
    // flagged `uses_bodyweight_load = TRUE` and the user's bodyweight
    // is known; equals the entered weight otherwise. Snapshotted so
    // future re-reads (audit, replay, analytics) see the exact load
    // the formula used — even if the user later edits their
    // bodyweight or the exercise flag flips. Nullable for legacy
    // events written before Phase 24c.
    //
    // Storage shape: same as `difficultyMult` — snapshotted INSIDE
    // `payload` as `payload.effective_load` by the SQL RPCs in
    // migration 00057. Promoted to top level by `fromJson`.
    double? effectiveLoad,
    // Whether the exercise's `uses_bodyweight_load` flag was TRUE at
    // the moment this event was written (Phase 24c). Distinct from
    // "did we add bodyweight" because the flag may be true while the
    // user's `profile.bodyweight_kg` is still null (in which case
    // effective_load == entered_weight via the COALESCE fallback in
    // the SQL RPC). Carries audit-trail clarity even when bodyweight
    // was unknown. Nullable for legacy events.
    //
    // Storage shape: same as `difficultyMult` — snapshotted INSIDE
    // `payload` as `payload.bodyweight_used` by the SQL RPCs in
    // migration 00057. Promoted to top level by `fromJson`.
    bool? bodyweightUsed,
    required DateTime occurredAt,
    required DateTime createdAt,
  }) = _XpEvent;

  /// Deserialize from a raw `xp_events` row.
  ///
  /// Promotes payload-nested snapshot keys to the top level before
  /// delegating to the generated deserializer, because the SQL RPCs
  /// snapshot these values INSIDE the `payload` JSONB sub-object —
  /// not as top-level columns. Without this promotion, the generated
  /// `_$XpEventFromJson` would read each key from the top level and
  /// always get `null`, defeating the snapshots' purpose.
  ///
  /// Promoted keys:
  /// - `payload.difficulty_mult` → top-level `difficulty_mult`
  ///   (Phase 24a — migration 00054 RPCs).
  /// - `payload.effective_load` → top-level `effective_load`
  ///   (Phase 24c — migration 00057 RPCs).
  /// - `payload.bodyweight_used` → top-level `bodyweight_used`
  ///   (Phase 24c — migration 00057 RPCs).
  ///
  /// Promotion rules (per key, applied independently):
  /// 1. If the key is already at the top level (defensive — shouldn't
  ///    happen against a real DB row), use it as-is. This is the
  ///    idempotency / future-proofing path: if a future migration
  ///    promotes any of these to a real top-level column, the
  ///    factory still works without changes.
  /// 2. Else if `payload.<key>` exists, promote it to the top level
  ///    for the generated deserializer.
  /// 3. Else (legacy events written before the relevant migration,
  ///    or payloads without the key), leave it null — the
  ///    corresponding model field will be null and consumers should
  ///    apply their own fallback semantics (e.g. `difficultyMult`
  ///    falls back to 1.0; `bodyweightUsed == null` means "we don't
  ///    know" and is distinct from `false`).
  factory XpEvent.fromJson(Map<String, dynamic> json) {
    final missingDifficulty = !json.containsKey('difficulty_mult');
    final missingEffectiveLoad = !json.containsKey('effective_load');
    final missingBodyweightUsed = !json.containsKey('bodyweight_used');

    if (missingDifficulty || missingEffectiveLoad || missingBodyweightUsed) {
      final payload = json['payload'] as Map<String, dynamic>?;
      final promoted = <String, dynamic>{
        ...json,
        if (missingDifficulty) 'difficulty_mult': payload?['difficulty_mult'],
        if (missingEffectiveLoad) 'effective_load': payload?['effective_load'],
        if (missingBodyweightUsed)
          'bodyweight_used': payload?['bodyweight_used'],
      };
      return _$XpEventFromJson(promoted);
    }
    return _$XpEventFromJson(json);
  }
}
