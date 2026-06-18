import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connectivity/connectivity_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/models/exercise.dart';
import '../../workouts/models/routine_start_config.dart';
import '../../workouts/providers/workout_providers.dart';
import '../../workouts/ui/widgets/resume_workout_dialog.dart';
import '../models/routine.dart';

/// Builds a [RoutineStartConfig] from a routine and starts an active workout.
///
/// Filters out exercises that are missing or soft-deleted.
/// If an active workout already exists, prompts the user to resume or discard
/// before starting the routine.
Future<void> startRoutineWorkout(
  BuildContext context,
  WidgetRef ref,
  Routine routine,
) async {
  // Guard: starting a workout requires a network call to create it.
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.offlineStartWorkout)));
    }
    return;
  }

  // Guard: check for an active workout before overwriting.
  final existingWorkout = ref.read(activeWorkoutProvider).value;
  if (existingWorkout != null) {
    final result = await ResumeWorkoutDialog.show(
      context,
      workoutName: existingWorkout.workout.name,
      startedAt: existingWorkout.workout.startedAt,
    );
    if (!context.mounted) return;
    if (result == ResumeWorkoutResult.resume) {
      context.go('/workout/active');
      return;
    }
    if (result == ResumeWorkoutResult.discard) {
      try {
        await ref.read(activeWorkoutProvider.notifier).discardWorkout();
      } catch (_) {
        return; // discard failed — don't start a new workout
      }
    } else {
      return; // dismissed
    }
  }

  final exercises = routine.exercises
      .where((re) => re.exercise != null && re.exercise!.deletedAt == null)
      .map((re) {
        final firstCfg = re.setConfigs.isNotEmpty ? re.setConfigs.first : null;
        // A cardio entry persists EXACTLY ONE config carrying its target —
        // pass the duration/distance through so the seed honors it instead of
        // the 30:00 default. `setConfigs.length` is NOT a set count for it.
        final isCardio = re.exercise!.muscleGroup == MuscleGroup.cardio;
        return RoutineStartExercise(
          exerciseId: re.exerciseId,
          exercise: re.exercise!,
          setCount: re.setConfigs.isNotEmpty ? re.setConfigs.length : 3,
          targetReps: firstCfg?.targetReps,
          restSeconds: firstCfg?.restSeconds,
          targetDurationSeconds: isCardio
              ? firstCfg?.targetDurationSeconds
              : null,
          targetDistanceM: isCardio ? firstCfg?.targetDistanceM : null,
        );
      })
      .toList();

  if (exercises.isEmpty) {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.couldNotLoadExercises)));
    }
    return;
  }

  final config = RoutineStartConfig(
    routineName: routine.name,
    exercises: exercises,
    routineId: routine.id,
    // Q2: thread the source routine's training notes onto the start config so
    // the active-workout screen can render them read-only (header strip +
    // sheet). Null/blank routines add no chrome — list is identical to today.
    routineNotes: routine.notes,
  );

  await ref.read(activeWorkoutProvider.notifier).startFromRoutine(config);
  if (!context.mounted) return;
  context.go('/workout/active');
}
