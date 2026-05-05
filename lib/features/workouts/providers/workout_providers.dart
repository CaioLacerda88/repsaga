import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/local_storage/cache_service.dart';
import '../../exercises/models/exercise.dart';
import '../../exercises/providers/exercise_providers.dart';
import '../../personal_records/providers/pr_providers.dart';
import '../data/workout_local_storage.dart';
import '../data/workout_repository.dart';
import '../domain/pr_row_state.dart';
import '../domain/pr_row_state_resolver.dart';
import '../models/exercise_set.dart';
import 'notifiers/active_workout_notifier.dart';

export 'notifiers/active_workout_notifier.dart';
export 'notifiers/rest_timer_notifier.dart';

/// Provides the [WorkoutRepository] singleton.
///
/// Stage 6: depends on [exerciseRepositoryProvider] so workout reads can
/// resolve localized exercise names via the batch RPC.
final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(
    Supabase.instance.client,
    ref.watch(cacheServiceProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

/// Provides the [WorkoutLocalStorage] singleton.
final workoutLocalStorageProvider = Provider<WorkoutLocalStorage>((ref) {
  return WorkoutLocalStorage();
});

/// Whether there is an active workout persisted in Hive.
final hasActiveWorkoutProvider = Provider<bool>((ref) {
  return ref.watch(workoutLocalStorageProvider).hasActiveWorkout;
});

/// Batch-fetch previous workout sets for a list of exercise IDs.
///
/// Keyed by a sorted, comma-joined string of exercise IDs for stable caching
/// (two `List<String>` with identical contents are not `==` in Dart).
/// Callers should pass `(exerciseIds..sort()).join(',')`.
/// Uses `autoDispose` so cached entries are freed when the UI screen
/// navigates away (e.g. finishing a workout). Without autoDispose, every
/// distinct comma-joined ID key lives forever.
final lastWorkoutSetsProvider = FutureProvider.autoDispose
    .family<Map<String, List<ExerciseSet>>, String>((ref, joinedIds) {
      final repo = ref.watch(workoutRepositoryProvider);
      final ids = joinedIds.isEmpty ? <String>[] : joinedIds.split(',');
      return repo.getLastWorkoutSets(ids);
    });

/// Per-row [PrRowDisplay] for every set on a single exercise within the
/// active workout (Phase 20 commit 4).
///
/// Reactive read-side projection: watches the active workout state for the
/// matching `workoutExerciseId` AND the exercise's historical PR records,
/// then runs the pure [resolveRowDisplays] resolver. The output is aligned
/// 1:1 with the exercise's `sets` list at read time.
///
/// **Why a derived provider rather than a field on [ActiveWorkoutExercise]:**
/// PR display is a read-side projection over (sets, existingRecords). Adding
/// a `rowDisplays` field on the model would require every notifier mutation
/// (`updateSet`, `completeSet`, `addSet`, `deleteSet`, `restoreSet`,
/// `copyLastSet`, `fillRemainingSets`) to recompute and persist it — easy to
/// forget, easy to drift, and the model would carry derived state that
/// belongs to the view. Riverpod's auto-disposing family handles the
/// reactivity correctly: any state change in either source triggers a fresh
/// resolve, and the provider drops when its consumer unmounts.
///
/// **Empty-list contract:** returns `[]` when the workout is not loaded, the
/// matching exercise is absent, or the exercise carries no sets. The
/// resolver itself is pure and short — recomputing on every set tick
/// (weight/rep change, completion toggle) is cheap and avoids stale
/// projections.
///
/// **First-ever workout cache miss:** when `exercisePRsProvider` is still
/// loading (or errors), this provider falls back to an empty
/// `existingRecords` list. The resolver then projects every positive-load
/// completed working set as a standing-PR — which is the correct semantic
/// for an exercise the user has never trained before. As records load, the
/// provider rebuilds and the projection sharpens.
final activeWorkoutRowDisplaysProvider = Provider.autoDispose
    .family<
      List<PrRowDisplay>,
      ({String workoutExerciseId, String exerciseId})
    >((ref, key) {
      final state = ref.watch(activeWorkoutProvider).value;
      if (state == null) return const <PrRowDisplay>[];

      final exercise = state.exercises
          .where((e) => e.workoutExercise.id == key.workoutExerciseId)
          .firstOrNull;
      if (exercise == null) return const <PrRowDisplay>[];
      if (exercise.sets.isEmpty) return const <PrRowDisplay>[];

      final equipmentType =
          exercise.workoutExercise.exercise?.equipmentType ??
          EquipmentType.bodyweight;

      // Historical records: read-only snapshot. On loading or error we
      // pass an empty list and let the resolver project against an empty
      // baseline — first-ever-workout semantic kicks in naturally.
      final existingRecords =
          ref.watch(exercisePRsProvider(key.exerciseId)).value ?? const [];

      return resolveRowDisplays(
        sets: exercise.sets,
        existingRecords: existingRecords,
        equipmentType: equipmentType,
      );
    });

/// Elapsed time since workout started, emitting every second.
final elapsedTimerProvider = StreamProvider.family<Duration, DateTime>((
  ref,
  startedAt,
) {
  return Stream.periodic(const Duration(seconds: 1), (_) {
    return DateTime.now().toUtc().difference(startedAt);
  });
});
