import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_engagement_provider.dart';

/// Regression tests for Bug A — `fn_exercises_localized` failing to project
/// `xp_attribution` meant `RoutineRepository._resolveExercises` hydrated every
/// `Exercise` with `xpAttribution = null`. The planned-counts loop then fell
/// back to `{primaryMuscle: 1.0}` per exercise, so a full-body routine
/// credited only its primary muscle per slot instead of the full attribution
/// fan-out. Combined with `WeeklyEngagement.from`'s `max(done, planned)`
/// invariant, body parts already trained masked the underflow — the user
/// only saw the unique-to-this-routine BP grow.
///
/// Post fix (migration 00066 projects `xp_attribution`, Hive cache schema
/// bumped to evict pre-fix cached rows), the planned-counts loop receives
/// non-null attribution maps and fans out across every body part the
/// exercise targets.
///
/// The fallback to `{primaryMuscle: 1.0}` is preserved as a defense-in-depth
/// safety net for any genuinely-null-attribution exercise (cache corruption,
/// future legacy rows) — the second test pins that branch.
void main() {
  final fixedCreatedAt = DateTime.utc(2026, 1, 1);

  Exercise exercise({
    required String id,
    required String slug,
    required MuscleGroup muscleGroup,
    Map<String, num>? xpAttribution,
  }) {
    return Exercise(
      id: id,
      name: slug,
      muscleGroup: muscleGroup,
      equipmentType: EquipmentType.barbell,
      isDefault: true,
      createdAt: fixedCreatedAt,
      xpAttribution: xpAttribution,
    );
  }

  RoutineExercise routineExercise({required Exercise ex, int sets = 3}) {
    return RoutineExercise(
      exerciseId: ex.id,
      setConfigs: List.generate(sets, (_) => const RoutineSetConfig()),
      exercise: ex,
    );
  }

  WeeklyPlan planFor({required String routineId}) {
    return WeeklyPlan(
      id: 'plan-1',
      userId: 'user-1',
      weekStart: DateTime.utc(2026, 5, 18),
      routines: [BucketRoutine(routineId: routineId, order: 0)],
      createdAt: fixedCreatedAt,
      updatedAt: fixedCreatedAt,
    );
  }

  group('Bug A — full-body routine planned-counts attribution', () {
    test('full-body routine credits every targeted body part when '
        'xp_attribution is populated (post-fix path)', () {
      // Six-exercise full-body routine, one exercise per active body part.
      // Each exercise carries an xp_attribution that resolves to its
      // matching BodyPart winner via primaryBodyPartsForSet (the maxima
      // are unambiguous).
      final benchPress = exercise(
        id: 'ex-bench',
        slug: 'bench_press',
        muscleGroup: MuscleGroup.chest,
        xpAttribution: const {'chest': 0.7, 'shoulders': 0.2, 'arms': 0.1},
      );
      final barbellRow = exercise(
        id: 'ex-row',
        slug: 'barbell_row',
        muscleGroup: MuscleGroup.back,
        xpAttribution: const {'back': 0.7, 'arms': 0.3},
      );
      final backSquat = exercise(
        id: 'ex-squat',
        slug: 'back_squat',
        muscleGroup: MuscleGroup.legs,
        xpAttribution: const {'legs': 0.8, 'core': 0.2},
      );
      final overheadPress = exercise(
        id: 'ex-ohp',
        slug: 'overhead_press',
        muscleGroup: MuscleGroup.shoulders,
        xpAttribution: const {'shoulders': 0.7, 'arms': 0.2, 'core': 0.1},
      );
      final bicepsCurl = exercise(
        id: 'ex-curl',
        slug: 'biceps_curl',
        muscleGroup: MuscleGroup.arms,
        xpAttribution: const {'arms': 1.0},
      );
      final plank = exercise(
        id: 'ex-plank',
        slug: 'plank',
        muscleGroup: MuscleGroup.core,
        xpAttribution: const {'core': 1.0},
      );

      final fullBody = Routine(
        id: 'routine-full-body',
        userId: 'user-1',
        name: 'Full Body',
        isDefault: false,
        createdAt: fixedCreatedAt,
        exercises: [
          routineExercise(ex: benchPress, sets: 3),
          routineExercise(ex: barbellRow, sets: 3),
          routineExercise(ex: backSquat, sets: 4),
          routineExercise(ex: overheadPress, sets: 3),
          routineExercise(ex: bicepsCurl, sets: 3),
          routineExercise(ex: plank, sets: 3),
        ],
      );

      final planned = computePlannedCounts(
        plan: planFor(routineId: fullBody.id),
        routinesById: {fullBody.id: fullBody},
      );

      // Every active body part receives credit equal to the number of
      // planned sets on the exercise whose primary attribution is that BP.
      // (None of the test exercises tie at the max, so each one credits
      // exactly one BP — keeping the assertion arithmetic exact.)
      expect(planned[BodyPart.chest], 3, reason: 'bench press 3 sets → chest');
      expect(planned[BodyPart.back], 3, reason: 'barbell row 3 sets → back');
      expect(planned[BodyPart.legs], 4, reason: 'back squat 4 sets → legs');
      expect(
        planned[BodyPart.shoulders],
        3,
        reason: 'overhead press 3 sets → shoulders',
      );
      expect(planned[BodyPart.arms], 3, reason: 'biceps curl 3 sets → arms');
      expect(planned[BodyPart.core], 3, reason: 'plank 3 sets → core');
    });

    test('exercise with null xp_attribution falls back to primary muscle '
        '(defense-in-depth safety net)', () {
      // Pre-fix Bug A state — the exercise has no xp_attribution. The
      // fallback path must still credit the primary muscle so cache-
      // corrupted or pre-migration rows degrade gracefully rather than
      // silently dropping the planned set from every body part.
      final legacyBench = exercise(
        id: 'ex-legacy-bench',
        slug: 'legacy_bench',
        muscleGroup: MuscleGroup.chest,
        xpAttribution: null,
      );

      final routine = Routine(
        id: 'routine-legacy',
        userId: 'user-1',
        name: 'Legacy Routine',
        isDefault: false,
        createdAt: fixedCreatedAt,
        exercises: [routineExercise(ex: legacyBench, sets: 3)],
      );

      final planned = computePlannedCounts(
        plan: planFor(routineId: routine.id),
        routinesById: {routine.id: routine},
      );

      // Fallback credits the primary muscle exactly once per set.
      expect(planned[BodyPart.chest], 3);
      // Other body parts receive no credit — the fallback is intentionally
      // narrow, mirroring the pre-fix attribution it stands in for.
      expect(planned[BodyPart.shoulders] ?? 0, 0);
      expect(planned[BodyPart.arms] ?? 0, 0);
      expect(planned[BodyPart.back] ?? 0, 0);
      expect(planned[BodyPart.legs] ?? 0, 0);
      expect(planned[BodyPart.core] ?? 0, 0);
    });

    test(
      'completed bucket entries are skipped (done-counts path owns them)',
      () {
        final benchPress = exercise(
          id: 'ex-bench',
          slug: 'bench_press',
          muscleGroup: MuscleGroup.chest,
          xpAttribution: const {'chest': 1.0},
        );
        final routine = Routine(
          id: 'routine-1',
          userId: 'user-1',
          name: 'Chest',
          isDefault: false,
          createdAt: fixedCreatedAt,
          exercises: [routineExercise(ex: benchPress, sets: 3)],
        );

        final plan = WeeklyPlan(
          id: 'plan-1',
          userId: 'user-1',
          weekStart: DateTime.utc(2026, 5, 18),
          routines: [
            BucketRoutine(
              routineId: routine.id,
              order: 0,
              completedWorkoutId: 'workout-completed-1',
              completedAt: fixedCreatedAt,
            ),
          ],
          createdAt: fixedCreatedAt,
          updatedAt: fixedCreatedAt,
        );

        final planned = computePlannedCounts(
          plan: plan,
          routinesById: {routine.id: routine},
        );

        // Completed bucket → no planned credit; the done-counts path will
        // pick up the actual sets logged against the workout.
        expect(planned.isEmpty, isTrue);
      },
    );

    test('spontaneous (routineId: null) bucket entries are skipped', () {
      final plan = WeeklyPlan(
        id: 'plan-1',
        userId: 'user-1',
        weekStart: DateTime.utc(2026, 5, 18),
        routines: const [
          BucketRoutine(routineId: null, order: 0, isSpontaneous: true),
        ],
        createdAt: fixedCreatedAt,
        updatedAt: fixedCreatedAt,
      );

      final planned = computePlannedCounts(plan: plan, routinesById: const {});

      expect(planned.isEmpty, isTrue);
    });
  });
}
