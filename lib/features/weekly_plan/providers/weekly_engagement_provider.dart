import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../../exercises/models/exercise.dart';
import '../../routines/models/routine.dart';
import '../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../rpg/models/body_part.dart';
import '../data/models/weekly_plan.dart';
import '../data/weekly_engagement_repository.dart';
import '../domain/weekly_engagement.dart';
import 'weekly_plan_provider.dart';

/// Provides the [WeeklyEngagementRepository] singleton. Mirrors
/// [weeklyPlanRepositoryProvider] — same Supabase client + recovery recorder
/// wiring.
final weeklyEngagementRepositoryProvider = Provider<WeeklyEngagementRepository>(
  (ref) {
    return WeeklyEngagementRepository(
      Supabase.instance.client,
      recoveryRecorder: ref.watch(recoveryRecorderProvider),
    );
  },
);

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

/// Compute the per-body-part planned-set counts implied by a weekly [plan]
/// and the [routinesById] map of available routines.
///
/// Pure-Dart seam — the provider's IO side (Supabase, Riverpod) reads the
/// plan + routines, then forwards them here. Exposed for unit testing so
/// Bug A (full-body routines crediting only their primary muscle pre-fix)
/// can be pinned without standing up a full Riverpod + Supabase harness.
///
/// Walks every uncompleted, non-spontaneous bucket entry whose `routine_id`
/// resolves to a known routine. For each routine-exercise:
///   * Reads `xp_attribution` (if present) or falls back to
///     `{muscle_group.name: 1.0}` — the latter is a defense-in-depth safety
///     net for any genuinely-null-attribution exercise (cache-corrupted
///     state, etc.). Post Bug A migration 00066, the fallback should
///     effectively never fire for valid server-curated rows.
///   * Calls [primaryBodyPartsForSet] once and credits each winner
///     `setConfigs.length` times (one credit per planned set sharing the
///     attribution).
Map<BodyPart, int> computePlannedCounts({
  required WeeklyPlan plan,
  required Map<String, Routine> routinesById,
}) {
  final acc = <BodyPart, int>{};
  for (final bucket in plan.routines) {
    // Already-completed bucket entries are accounted for via the done-counts
    // path.
    if (bucket.completedWorkoutId != null) continue;
    // Spontaneous bucket entries (Bug F / migration 00063) carry
    // routine_id: null — no source routine to project planned-set counts
    // from. They're also always already-completed so they almost never
    // reach this point, but the guard documents the contract and keeps
    // Map[String, R][null] inference clean.
    if (bucket.routineId == null) continue;
    final routine = routinesById[bucket.routineId];
    if (routine == null) continue;
    for (final routineExercise in routine.exercises) {
      final exercise = routineExercise.exercise;
      if (exercise == null) continue;
      // Cardio entries carry no muscle sets — their single config is a
      // duration/distance target, NOT a set count — so they contribute zero
      // strength muscle-engagement credits. `setConfigs.length` (== 1 for a
      // cardio entry) must not be credited as a planned set.
      if (exercise.muscleGroup == MuscleGroup.cardio) continue;
      final attrJson = exercise.xpAttribution;
      // `MuscleGroup.name` matches `BodyPart.dbValue` token-for-token
      // (both are lowercase enum names). Fallback when no xp_attribution
      // JSON is available on the exercise yet — defense-in-depth safety
      // net per the contract above.
      final primaryMuscle = exercise.muscleGroup.name;
      final Map<String, num> attrMap = (attrJson != null && attrJson.isNotEmpty)
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
  return acc;
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
      // cluster: jsonb-payload-vs-typed-dart — the raw `.from('sets')` + `as`
      // walks that used to live here now run through
      // [WeeklyEngagementRepository.getDoneCounts], which routes the query
      // through `mapException` and parses the nested JSONB join with
      // json_helpers instead of throwing `as Map` casts.
      final doneCounts = await ref
          .read(weeklyEngagementRepositoryProvider)
          .getDoneCounts(userId: userId, mondayStr: mondayStr);

      // ---- PLANNED COUNTS --------------------------------------------------
      Map<BodyPart, int> plannedCounts = const {};
      if (args.includePlanned) {
        // `.value` returns null while the dependency is loading/in error.
        // Treat that as "no planned data yet" — the bar will fill in on
        // the next emission when those providers resolve.
        final plan = ref.watch(weeklyPlanProvider).value;
        final routines = ref.watch(routineListProvider).value ?? const [];
        if (plan != null) {
          plannedCounts = computePlannedCounts(
            plan: plan,
            routinesById: {for (final r in routines) r.id: r},
          );
        }
      }

      return engagementFromCounts(
        doneCounts: doneCounts,
        plannedCounts: plannedCounts,
        includePlanned: args.includePlanned,
      );
    });
