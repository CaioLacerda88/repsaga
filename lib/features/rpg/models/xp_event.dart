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
    required DateTime occurredAt,
    required DateTime createdAt,
  }) = _XpEvent;

  /// Deserialize from a raw `xp_events` row.
  ///
  /// Promotes `payload.difficulty_mult` to the top-level
  /// `difficulty_mult` key before delegating to the generated
  /// deserializer, because the SQL RPCs (migration 00054) snapshot
  /// the multiplier INSIDE the `payload` JSONB sub-object — not as a
  /// top-level column. Without this promotion, the generated
  /// `_$XpEventFromJson` would read `json['difficulty_mult']` and
  /// always get `null` for every event (defeating the snapshot's
  /// purpose).
  ///
  /// Promotion rules:
  /// 1. If `difficulty_mult` is already at the top level (defensive
  ///    — shouldn't happen against a real DB row), use it as-is.
  /// 2. Else if `payload.difficulty_mult` exists, promote it to the
  ///    top level for the generated deserializer.
  /// 3. Else (legacy events written before Phase 24a, or payloads
  ///    without the key), leave it null — `XpEvent.difficultyMult`
  ///    will be null and consumers should fall back to 1.0.
  factory XpEvent.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('difficulty_mult')) {
      return _$XpEventFromJson(json);
    }
    final payload = json['payload'] as Map<String, dynamic>?;
    final promoted = <String, dynamic>{
      ...json,
      'difficulty_mult': payload?['difficulty_mult'],
    };
    return _$XpEventFromJson(promoted);
  }
}
