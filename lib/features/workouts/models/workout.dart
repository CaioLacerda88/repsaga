// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout.freezed.dart';
part 'workout.g.dart';

@freezed
abstract class Workout with _$Workout {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Workout({
    required String id,
    required String userId,
    required String name,
    required DateTime startedAt,
    DateTime? finishedAt,
    int? durationSeconds,
    @JsonKey(defaultValue: false) required bool isActive,
    String? notes,
    required DateTime createdAt,

    /// Computed at query time — not a DB column.
    /// E.g. "Bench Press, Squat, Deadlift +2"
    @JsonKey(includeFromJson: false, includeToJson: false)
    String? exerciseSummary,

    /// Total XP earned during this session.
    ///
    /// Sourced from the Phase 32 PR 32f `get_workout_history_with_aggregates`
    /// (history list) and `get_workout_xp` (detail) RPCs, which `COALESCE(SUM
    /// (xp_events.total_xp), 0)` over events linked by `session_id`. Defaults
    /// to 0 so legacy non-RPC paths (offline-saved-then-reloaded local rows,
    /// raw `.from('workouts')` reads if any survive) deserialize cleanly.
    @JsonKey(name: 'total_xp', defaultValue: 0) @Default(0) int totalXp,

    /// Personal-record count for this session.
    ///
    /// Sourced from the same Phase 32 PR 32f RPCs as [totalXp]; counts rows
    /// in `personal_records` joined via `sets → workout_exercises →
    /// workouts.id`. Defaults to 0 so the UI renders without surprise when
    /// the RPC returns null (legacy paths) and so legacy callers that don't
    /// route through the aggregate RPC still construct valid [Workout]
    /// instances.
    @JsonKey(name: 'pr_count', defaultValue: 0) @Default(0) int prCount,
  }) = _Workout;

  factory Workout.fromJson(Map<String, dynamic> json) =>
      _$WorkoutFromJson(json);
}
