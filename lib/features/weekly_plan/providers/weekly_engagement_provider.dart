import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../../rpg/models/body_part.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../domain/weekly_engagement.dart';
import 'weekly_plan_provider.dart';

/// Arguments for [weeklyEngagementProvider].
///
/// `includePlanned`: the plan editor passes `true` (the bar shows done +
/// planned stacked). Future Stats deep-dive volume/PR surfaces will pass
/// `false` so only the done portion renders.
class WeeklyEngagementArgs {
  const WeeklyEngagementArgs({required this.includePlanned});

  final bool includePlanned;

  @override
  bool operator ==(Object other) =>
      other is WeeklyEngagementArgs && other.includePlanned == includePlanned;

  @override
  int get hashCode => includePlanned.hashCode;
}

/// Per-body-part counts → [WeeklyEngagement]. Pure-Dart composition seam,
/// exposed for unit testing without the Riverpod + Supabase scaffolding.
///
/// When `includePlanned == false`, `plannedCounts` is dropped entirely;
/// [WeeklyEngagement.from] then sets `plannedFor == doneFor` (the bar reads
/// as fully drained, preserving the `doneFor <= plannedFor` invariant).
WeeklyEngagement engagementFromCounts({
  required Map<BodyPart, int> doneCounts,
  required Map<BodyPart, int> plannedCounts,
  required bool includePlanned,
}) {
  return WeeklyEngagement.from(
    done: doneCounts,
    planned: includePlanned ? plannedCounts : const {},
  );
}

/// Emits the current week's engagement totals.
///
/// IO contract:
///   * Done counts: SELECT every completed working set from the current
///     Monday onward where the parent workout's `user_id == auth.uid()`.
///     Join `workout_exercises → exercises` for the `xp_attribution` JSONB.
///     For each set, apply [primaryBodyPartsForSet] and increment per-bp
///     counters. Warm-up sets and zero-rep rows are skipped.
///   * Planned counts (only when `includePlanned == true`): read the current
///     bucket via [weeklyPlanProvider] + routine details via
///     [routineListProvider]. For each uncompleted bucket entry, walk
///     `Routine.exercises[*]`; each routine-exercise's `setConfigs.length`
///     is the number of planned sets sharing that exercise's attribution.
///     [primaryBodyPartsForSet] is applied once per routine-exercise and
///     the resulting winners are credited `setConfigs.length` times each.
///
/// Provider re-fires whenever [weeklyPlanProvider] or [routineListProvider]
/// emit a new value. The workout-history read is intentionally NOT cached
/// across invalidations — post-save the cache would be stale and the
/// Phase-12-era query is sub-50ms in practice.
final weeklyEngagementProvider = FutureProvider.family
    .autoDispose<WeeklyEngagement, WeeklyEngagementArgs>((ref, args) async {
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) return WeeklyEngagement.empty;

      final monday = currentWeekMonday();
      final mondayStr =
          '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

      // ---- DONE COUNTS -----------------------------------------------------
      // One round-trip: pull every completed working set + its exercise's
      // xp_attribution for the current week. Returns rows like:
      //   { is_completed: true, set_type: 'working', reps: 8,
      //     workout_exercises: { exercise: { xp_attribution: {...},
      //                                      muscle_group: 'chest' },
      //                          workouts: { user_id, finished_at } } }
      final client = Supabase.instance.client;
      final doneRows = await client
          .from('sets')
          .select('''
            is_completed,
            set_type,
            reps,
            workout_exercises!inner(
              workout_id,
              exercise:exercises!inner(xp_attribution, muscle_group),
              workouts!inner(user_id, finished_at)
            )
          ''')
          .eq('workout_exercises.workouts.user_id', userId)
          .gte('workout_exercises.workouts.finished_at', mondayStr)
          .eq('is_completed', true);

      final doneCounts = <BodyPart, int>{};
      for (final row in doneRows as List<dynamic>) {
        final r = row as Map<String, dynamic>;
        final setType = (r['set_type'] as String?) ?? 'working';
        if (setType != 'working') continue;
        final reps = r['reps'] as int?;
        if (reps == null || reps < 1) continue;

        final we = r['workout_exercises'] as Map<String, dynamic>?;
        if (we == null) continue;
        final ex = we['exercise'] as Map<String, dynamic>?;
        if (ex == null) continue;
        final attrJson = ex['xp_attribution'] as Map<String, dynamic>?;
        final primaryMuscle = ex['muscle_group'] as String?;

        final Map<String, num> attrMap;
        if (attrJson != null && attrJson.isNotEmpty) {
          attrMap = attrJson.map((k, v) => MapEntry(k, v as num));
        } else if (primaryMuscle != null) {
          attrMap = <String, num>{primaryMuscle: 1.0};
        } else {
          continue; // No attribution, no muscle_group — nothing to credit.
        }

        final winners = primaryBodyPartsForSet(attrMap);
        for (final bp in winners) {
          doneCounts[bp] = (doneCounts[bp] ?? 0) + 1;
        }
      }

      // ---- PLANNED COUNTS --------------------------------------------------
      Map<BodyPart, int> plannedCounts = const {};
      if (args.includePlanned) {
        // `.value` returns null while the dependency is loading/in error.
        // Treat that as "no planned data yet" — the bar will fill in on
        // the next emission when those providers resolve.
        final plan = ref.watch(weeklyPlanProvider).value;
        final routines = ref.watch(routineListProvider).value ?? const [];
        if (plan != null) {
          final routineMap = {for (final r in routines) r.id: r};
          final acc = <BodyPart, int>{};
          for (final bucket in plan.routines) {
            // Already-completed bucket entries are accounted for via doneRows.
            if (bucket.completedWorkoutId != null) continue;
            final routine = routineMap[bucket.routineId];
            if (routine == null) continue;
            for (final routineExercise in routine.exercises) {
              final exercise = routineExercise.exercise;
              if (exercise == null) continue;
              final attrJson = exercise.xpAttribution;
              // `MuscleGroup.name` matches `BodyPart.dbValue` token-for-token
              // (both are lowercase enum names). Fallback when no
              // xp_attribution JSON is available on the exercise yet.
              final primaryMuscle = exercise.muscleGroup.name;
              final Map<String, num> attrMap =
                  (attrJson != null && attrJson.isNotEmpty)
                  ? attrJson
                  : <String, num>{primaryMuscle: 1.0};
              final winners = primaryBodyPartsForSet(attrMap);
              final setCount = routineExercise.setConfigs.length;
              if (setCount == 0) continue;
              for (final bp in winners) {
                acc[bp] = (acc[bp] ?? 0) + setCount;
              }
            }
          }
          plannedCounts = acc;
        }
      }

      return engagementFromCounts(
        doneCounts: doneCounts,
        plannedCounts: plannedCounts,
        includePlanned: args.includePlanned,
      );
    });
