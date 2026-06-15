// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import 'cardio_session.dart';
import 'exercise_set.dart';
import 'workout.dart';
import 'workout_exercise.dart';

part 'active_workout_state.freezed.dart';
part 'active_workout_state.g.dart';

@freezed
abstract class ActiveWorkoutExercise with _$ActiveWorkoutExercise {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory ActiveWorkoutExercise({
    required WorkoutExercise workoutExercise,
    @JsonKey(defaultValue: <ExerciseSet>[]) required List<ExerciseSet> sets,

    /// Phase 38b — the cardio entry for this exercise when
    /// `workoutExercise.exercise.muscleGroup == cardio`. Cardio entries
    /// carry no weight×reps sets ([sets] stays empty); strength entries
    /// carry no cardio session (this stays null). The muscle group is the
    /// discriminator; this field is the payload. Nullable + absent-key
    /// tolerant so pre-38b Hive crash-recovery JSON deserializes unchanged
    /// (same threading pattern as `ActiveWorkoutState.routineNotes`).
    CardioSession? cardioSession,
  }) = _ActiveWorkoutExercise;

  factory ActiveWorkoutExercise.fromJson(Map<String, dynamic> json) =>
      _$ActiveWorkoutExerciseFromJson(json);
}

@freezed
abstract class ActiveWorkoutState with _$ActiveWorkoutState {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory ActiveWorkoutState({
    required Workout workout,
    @JsonKey(defaultValue: <ActiveWorkoutExercise>[])
    required List<ActiveWorkoutExercise> exercises,

    /// The source routine's ID when this workout was started from a routine.
    /// Used for matching bucket completion in the weekly plan.
    String? routineId,

    /// The source routine's training notes (Q2), captured at start time so the
    /// active-workout screen can render them read-only. Carried on the state
    /// (not read live from the routine) so the notes survive crash-recovery
    /// rehydration through the same Hive JSON round-trip as [routineId]. Null
    /// for ad-hoc workouts and routines without notes — in both cases the
    /// exercise list shows no notes header strip (identical to today).
    String? routineNotes,

    /// Whether the most recent `finishWorkout` saved to the offline queue
    /// instead of syncing to the server.
    ///
    /// Lives on the state (not the notifier) so UI consumers read it through
    /// the same `ref.watch(activeWorkoutProvider)` channel as every other
    /// field — keeps Riverpod's unidirectional data flow intact (BUG-039).
    /// `false` while a workout is in progress; the notifier flips it to
    /// `true` inside `finishWorkout` when the network save fails and the
    /// workout is enqueued for later sync.
    @JsonKey(defaultValue: false) @Default(false) bool savedOffline,
  }) = _ActiveWorkoutState;

  factory ActiveWorkoutState.fromJson(Map<String, dynamic> json) =>
      _$ActiveWorkoutStateFromJson(json);
}
