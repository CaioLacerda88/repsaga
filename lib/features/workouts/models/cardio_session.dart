// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'cardio_session.freezed.dart';
part 'cardio_session.g.dart';

/// A single manual cardio entry inside a workout (Phase 38b).
///
/// Mirrors [ExerciseSet]'s lifecycle: lives on the in-memory
/// `ActiveWorkoutState` (as `ActiveWorkoutExercise.cardioSession`), survives
/// crash-recovery through the Hive JSON round-trip, and is persisted to the
/// `cardio_sessions` table by the `save_workout` RPC when the workout
/// finishes — but ONLY when [isCompleted] is true (the user tapped
/// "Concluir cardio"). Incomplete entries are dropped at save time, exactly
/// like incomplete strength sets.
///
/// Stores RAW user inputs only (duration / distance / RPE). The earning
/// formula's derived values (`met`, `met_minutes`, `est_met`) are a Phase
/// 38c concern and have no Dart-side fields yet.
@freezed
abstract class CardioSession with _$CardioSession {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory CardioSession({
    required String id,
    required String workoutId,
    required String exerciseId,

    /// Mandatory — the hero input. Always > 0 by UI construction: the
    /// DurationStepper floors decrement at one increment (30s), so 0:00 is
    /// unreachable. The DB CHECK (`duration_seconds > 0`) is the hard
    /// backstop.
    required int durationSeconds,

    /// Optional distance in METERS (the DB canonical unit). The UI converts
    /// to/from the profile display unit (km when weightUnit is kg, mi when
    /// lbs) at the edge — see `cardio_format.dart`.
    double? distanceM,

    /// Optional rate of perceived exertion, 1–10.
    int? rpe,

    /// Client-side completion state ("Concluir cardio" tapped). NOT a DB
    /// column — completed entries are the only ones persisted, so the
    /// stored rows are implicitly all completed. Kept in the Hive JSON so
    /// crash recovery restores the collapsed card state.
    @JsonKey(defaultValue: false) required bool isCompleted,
    required DateTime createdAt,
  }) = _CardioSession;

  factory CardioSession.fromJson(Map<String, dynamic> json) =>
      _$CardioSessionFromJson(json);
}

/// Single source of truth for the snake_case cardio payload sent as one
/// element of `save_workout`'s `p_cardio` array — and queued as
/// `cardioJson` on offline `PendingSaveWorkout`.
///
/// Mirrors `ExerciseSetRpcJson`: both call sites (online RPC + offline
/// replay) MUST serialize identically — drift between the two was the root
/// cause of BUG-001 on the sets path. `is_completed` is intentionally
/// EXCLUDED: the `cardio_sessions` table has no such column (only completed
/// entries are ever sent).
extension CardioSessionRpcJson on CardioSession {
  Map<String, dynamic> toRpcJson() => <String, dynamic>{
    'id': id,
    'workout_id': workoutId,
    'exercise_id': exerciseId,
    'duration_seconds': durationSeconds,
    'distance_m': distanceM,
    'rpe': rpe,
    'created_at': createdAt.toIso8601String(),
  };
}
