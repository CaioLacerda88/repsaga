import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
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
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
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
/// **PR data loading / error guard (PR-6 / M6).** While
/// `exercisePRsProvider(exerciseId)` is `AsyncLoading` (or `AsyncError`),
/// this provider returns a list of plain [PrRowState.none] displays — one
/// per set, preserving the 1:1 alignment contract — instead of running the
/// resolver against an empty `existingRecords` baseline. Pre-fix the empty
/// fallback caused returning users with a slow `personal_records` fetch to
/// see every completed working set briefly classified as a standing PR
/// (gold stripe + bracket), then reclassified once data landed. Visual
/// flicker, false predicted-PR celebration cue. The "first-ever workout"
/// behavior is unaffected: when records actually load to `AsyncData([])`,
/// the resolver runs as before and the first completed working set with
/// positive load becomes the standing PR. Finish-time PR celebration is
/// likewise unaffected — that path uses `pr_cache` directly via
/// `PRDetectionService`, not this row provider. `AsyncError` collapses to
/// the same `none` shape on purpose: we don't have authoritative baseline
/// data, so we don't speculate. As records load, the provider rebuilds and
/// rows reclassify naturally.
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

      // PR-6 / M6: gate on the AsyncValue's resolution state instead of
      // `.value ?? []`. While the FIRST emission is in flight (or errored
      // with no prior data) we return one `PrRowState.none` per set —
      // preserving the 1:1 alignment contract — instead of feeding an
      // empty baseline to the resolver and producing transient false
      // standing-PR signals. A refresh that's still in flight while a
      // prior `AsyncData` is held keeps using that stale value rather
      // than blanking the rows; the resolver runs as before. As records
      // arrive, Riverpod rebuilds this provider and rows reclassify
      // naturally.
      final prsAsync = ref.watch(exercisePRsProvider(key.exerciseId));
      // `AsyncValue.value` is nullable: it returns null while the FIRST
      // emission is in flight (loading with no prior data) and on error
      // with no prior data. A refresh that overlays a stale `AsyncData`
      // returns that stale value here, so we keep classifying with the
      // last-known baseline rather than blanking the rows.
      final existingRecords = prsAsync.value;
      if (existingRecords == null) {
        return List<PrRowDisplay>.unmodifiable([
          for (var i = 0; i < exercise.sets.length; i++)
            const PrRowDisplay.plain(PrRowState.none),
        ]);
      }

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
