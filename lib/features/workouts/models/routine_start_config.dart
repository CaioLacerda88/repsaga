import 'package:freezed_annotation/freezed_annotation.dart';

import '../../exercises/models/exercise.dart';

part 'routine_start_config.freezed.dart';

@freezed
abstract class RoutineStartExercise with _$RoutineStartExercise {
  const factory RoutineStartExercise({
    required String exerciseId,
    required Exercise exercise,
    required int setCount,
    int? targetReps,
    int? restSeconds,
  }) = _RoutineStartExercise;
}

@freezed
abstract class RoutineStartConfig with _$RoutineStartConfig {
  const factory RoutineStartConfig({
    required String routineName,
    required List<RoutineStartExercise> exercises,

    /// The source routine's ID, used for bucket-completion matching.
    /// Null when starting a blank workout (not from a routine).
    String? routineId,

    /// The source routine's training notes (Q2), threaded through to
    /// [ActiveWorkoutState] so the active-workout screen can render them
    /// read-only without a separate provider read. Null/blank for ad-hoc
    /// workouts and for routines with no notes — in both cases the
    /// active-workout list shows no notes header strip.
    String? routineNotes,
  }) = _RoutineStartConfig;
}
