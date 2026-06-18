import '../../exercises/models/exercise.dart';
import '../../routines/models/routine.dart';
import '../../workouts/utils/cardio_format.dart';

/// Rough estimate of the work time spent on a single set (seconds).
///
/// Covers the lift itself plus a short between-set transition (re-racking,
/// stepping back under the bar, etc.). Deliberately coarse — we round the
/// final duration to the nearest 5 min so per-set precision is wasted.
const int _workSecondsPerSet = 30;

/// Fallback estimate (seconds) per exercise when its [RoutineExercise.setConfigs]
/// list is empty. Assumes 3 sets × (90s rest + 30s work) = 360s = 6 min.
///
/// Prevents the estimator from collapsing to 0 min on legacy routines whose
/// set_configs never got migrated — a 6 min per-exercise floor lines up with
/// a typical accessory lift and keeps the CTA stats line believable.
const int _fallbackSecondsPerExercise = 3 * (90 + _workSecondsPerSet);

/// Estimates a routine's total duration in minutes.
///
/// For each exercise: sum `rest_seconds + _workSecondsPerSet` across all
/// set_configs. Exercises with an empty set_configs list contribute
/// [_fallbackSecondsPerExercise] instead of 0, so legacy data still yields
/// a sensible estimate.
///
/// The result is rounded to the nearest 5 min (e.g. 47 → 45, 53 → 55) so the
/// CTA stats line reads as an estimate, not a stopwatch reading. Returns 0
/// for a routine with zero exercises.
///
/// Pure function — no provider access, no clock. Kept at top level (not a
/// static method) so unit tests can call it without instantiating a widget.
int estimateRoutineDurationMinutes(Routine routine) {
  if (routine.exercises.isEmpty) return 0;

  var totalSeconds = 0;
  for (final ex in routine.exercises) {
    // Cardio entries carry no rest×sets shape — their single config holds a
    // duration TARGET. Use it (fallback 30:00) as the whole contribution.
    if (ex.exercise?.muscleGroup == MuscleGroup.cardio) {
      final target = ex.setConfigs.isNotEmpty
          ? ex.setConfigs.first.targetDurationSeconds
          : null;
      totalSeconds += target ?? kDefaultCardioDurationSeconds;
      continue;
    }
    if (ex.setConfigs.isEmpty) {
      totalSeconds += _fallbackSecondsPerExercise;
      continue;
    }
    for (final cfg in ex.setConfigs) {
      final rest =
          cfg.restSeconds ?? 90; // same default as active workout timer
      totalSeconds += rest + _workSecondsPerSet;
    }
  }

  final minutes = totalSeconds / 60;
  // Round to the nearest 5 min (e.g. 53.5 → 55, 47.2 → 45). Clamp to a
  // minimum of 5 min for any non-empty routine so we never render "~0 min".
  final rounded = (minutes / 5).round() * 5;
  return rounded < 5 ? 5 : rounded;
}
