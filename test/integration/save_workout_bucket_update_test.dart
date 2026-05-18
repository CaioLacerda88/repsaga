/// Integration tests for the Phase 26e Task 3 bucket find-or-create logic
/// in migration 00063 (`save_workout` extension).
///
/// Verifies the full first-completion-wins state machine:
///   1. Planned hit fills the matched entry.
///   2. No match appends a spontaneous entry.
///   3. Duplicate routine prefers filling the planned entry.
///   4. Already-completed match → new spontaneous (re-save same day).
///   5. Idempotent re-save — same workout id is a no-op.
///   6. No plan for current week → no-op.
///   7. Multi-workout same day — both entries land correctly.
///
/// Requires local Supabase running: `npx supabase start`.
///
/// Run:
///   export PATH="/c/flutter/bin:$PATH"
///   flutter test --tags integration test/integration/save_workout_bucket_update_test.dart
@Tags(['integration'])
library;

// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';

import 'rpg_integration_setup.dart';

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;
  TestUser? currentUser;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('weekly-plan-26e-$runId-$idx@test.local');
    currentUser = u;
    return u;
  }

  tearDown(() async {
    if (currentUser != null) {
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  // ---------------------------------------------------------------------------
  // Helper: cast rows from readCurrentWeeklyPlan routines list.
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> routinesList(Map<String, dynamic> plan) {
    final raw = plan['routines'] as List;
    return raw.cast<Map<String, dynamic>>();
  }

  group('save_workout — bucket find-or-create', () {
    // =========================================================================
    // 1. Planned hit: uncompleted entry whose routine_id matches → fill it.
    // =========================================================================
    test(
      'should fill an uncompleted planned entry when routine_id matches',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final r1 = seedRoutineId();

        // Seed a weekly_plans row with one uncompleted entry for r1.
        await seedWeeklyPlan(
          adminClient: admin,
          userId: user.userId,
          routines: [
            {
              'routine_id': r1,
              'order': 1,
              'completed_workout_id': null,
              'completed_at': null,
            },
          ],
        );

        final seed = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
          routineId: r1,
        );

        final plan = await readCurrentWeeklyPlan(admin, user.userId);
        expect(plan, isNotNull, reason: 'weekly_plan row must still exist');
        final routines = routinesList(plan!);
        expect(routines, hasLength(1), reason: 'no extra entry should appear');
        expect(
          routines.first['completed_workout_id'],
          seed.workoutId,
          reason: 'completed_workout_id must be set to the saved workout',
        );
        expect(
          routines.first['completed_at'],
          isNotNull,
          reason: 'completed_at must be stamped',
        );
        expect(
          routines.first['is_spontaneous'],
          isNot(true),
          reason: 'planned hit must not be flagged is_spontaneous',
        );
      },
    );

    // =========================================================================
    // 2. No match: different routine_id → append spontaneous entry.
    // =========================================================================
    test(
      'should append a spontaneous entry when no uncompleted match exists',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final r1 = seedRoutineId();
        final r2 = seedRoutineId(); // the workout will carry r2, plan has r1

        await seedWeeklyPlan(
          adminClient: admin,
          userId: user.userId,
          routines: [
            {
              'routine_id': r1,
              'order': 1,
              'completed_workout_id': null,
              'completed_at': null,
            },
          ],
        );

        final seed = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
          routineId: r2,
        );

        final plan = await readCurrentWeeklyPlan(admin, user.userId);
        final routines = routinesList(plan!);
        expect(routines, hasLength(2), reason: 'spontaneous entry must append');
        final spontaneous = routines.where((r) => r['routine_id'] == r2);
        expect(
          spontaneous.length,
          1,
          reason: 'exactly one entry for r2 must exist',
        );
        expect(
          spontaneous.first['is_spontaneous'],
          true,
          reason: 'appended entry must be flagged is_spontaneous',
        );
        expect(
          spontaneous.first['completed_workout_id'],
          seed.workoutId,
          reason: 'spontaneous entry must carry the workout id',
        );
        // Original r1 entry must remain untouched.
        final r1Entry = routines.where((r) => r['routine_id'] == r1).toList();
        expect(
          r1Entry.first['completed_workout_id'],
          isNull,
          reason: 'r1 planned entry must remain uncompleted',
        );
      },
    );

    // =========================================================================
    // 3. Duplicate routine: plan has an uncompleted entry AND the same workout
    //    could go spontaneous — should prefer filling the planned entry.
    // =========================================================================
    test(
      'should prefer filling an uncompleted planned entry over appending spontaneous',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final r1 = seedRoutineId();

        // Plan has TWO entries for r1: one already completed, one not.
        // The RPC must fill the uncompleted one, not append spontaneous.
        await seedWeeklyPlan(
          adminClient: admin,
          userId: user.userId,
          routines: [
            {
              'routine_id': r1,
              'order': 1,
              'completed_workout_id': 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
              'completed_at': '2026-05-18T06:00:00.000Z',
            },
            {
              'routine_id': r1,
              'order': 2,
              'completed_workout_id': null,
              'completed_at': null,
            },
          ],
        );

        final seed = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
          routineId: r1,
        );

        final plan = await readCurrentWeeklyPlan(admin, user.userId);
        final routines = routinesList(plan!);
        // Still exactly 2 entries — no spontaneous appended.
        expect(
          routines,
          hasLength(2),
          reason:
              'no spontaneous entry should be appended when a planned match exists',
        );
        // The second entry (order=2) should now be filled.
        final order2 = routines.where((r) => (r['order'] as int) == 2).toList();
        expect(order2, hasLength(1));
        expect(
          order2.first['completed_workout_id'],
          seed.workoutId,
          reason: 'second planned entry must be filled',
        );
      },
    );

    // =========================================================================
    // 4. Already-completed match → append spontaneous (re-save same day).
    // =========================================================================
    test(
      'should append a spontaneous entry when the matching planned entry is already completed',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final r1 = seedRoutineId();
        // Pre-fill the plan's entry as already completed (simulate morning workout).
        const existingWorkoutId = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';

        await seedWeeklyPlan(
          adminClient: admin,
          userId: user.userId,
          routines: [
            {
              'routine_id': r1,
              'order': 1,
              'completed_workout_id': existingWorkoutId,
              'completed_at': '2026-05-18T07:00:00.000Z',
            },
          ],
        );

        // Second workout of same routine today.
        final seed = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 70.0,
          reps: 5,
          numSets: 3,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 70.0,
          reps: 5,
          numSets: 3,
          routineId: r1,
        );

        final plan = await readCurrentWeeklyPlan(admin, user.userId);
        final routines = routinesList(plan!);
        expect(
          routines,
          hasLength(2),
          reason: 'second same-routine workout must append as spontaneous',
        );
        final newEntry = routines.where(
          (r) => r['completed_workout_id'] == seed.workoutId,
        );
        expect(newEntry, hasLength(1));
        expect(
          newEntry.first['is_spontaneous'],
          true,
          reason: 'second same-routine workout is spontaneous',
        );
      },
    );

    // =========================================================================
    // 5. Idempotent re-save — same workout id twice does not append duplicate.
    // =========================================================================
    test('should be idempotent on re-save of the same workout id', () async {
      final user = await freshUser();
      final admin = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final r1 = seedRoutineId();

      await seedWeeklyPlan(
        adminClient: admin,
        userId: user.userId,
        routines: [
          {
            'routine_id': r1,
            'order': 1,
            'completed_workout_id': null,
            'completed_at': null,
          },
        ],
      );

      final seed = await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'barbell_bench_press',
        weightKg: 60.0,
        reps: 5,
        numSets: 3,
      );

      // First save.
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed,
        userId: user.userId,
        weightKg: 60.0,
        reps: 5,
        numSets: 3,
        routineId: r1,
      );

      // Second save with same workout id — must be a no-op for the bucket.
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed,
        userId: user.userId,
        weightKg: 60.0,
        reps: 5,
        numSets: 3,
        routineId: r1,
      );

      final plan = await readCurrentWeeklyPlan(admin, user.userId);
      final routines = routinesList(plan!);
      expect(
        routines,
        hasLength(1),
        reason: 're-saving the same workout must not append a duplicate entry',
      );
      expect(
        routines.first['completed_workout_id'],
        seed.workoutId,
        reason: 'the single entry must carry the workout id',
      );
    });

    // =========================================================================
    // 6. No plan for current week → no-op bucket update.
    // =========================================================================
    test(
      'should no-op the bucket update when no weekly_plan exists for the current week',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();
        final userClient = authenticatedClient(user);

        // Deliberately do NOT seed a weekly_plans row.
        final r1 = seedRoutineId();

        final seed = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
        );

        // Should not throw — no plan row is a valid state.
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
          routineId: r1,
        );

        final plan = await readCurrentWeeklyPlan(admin, user.userId);
        expect(
          plan,
          isNull,
          reason: 'no weekly_plans row should be auto-created by save_workout',
        );
      },
    );

    // =========================================================================
    // 7. Multi-workout same day: two workouts with different routines both land.
    // =========================================================================
    test(
      'should fill both entries when two workouts of different routines run on the same day',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final r1 = seedRoutineId();
        final r2 = seedRoutineId();

        await seedWeeklyPlan(
          adminClient: admin,
          userId: user.userId,
          routines: [
            {
              'routine_id': r1,
              'order': 1,
              'completed_workout_id': null,
              'completed_at': null,
            },
            {
              'routine_id': r2,
              'order': 2,
              'completed_workout_id': null,
              'completed_at': null,
            },
          ],
        );

        // First workout: routine r1.
        final seed1 = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed1,
          userId: user.userId,
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
          routineId: r1,
        );

        // Second workout: routine r2 (use a different exercise slug to avoid
        // any accidental shared-state in the XP chain).
        final seed2 = await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'deadlift',
          weightKg: 80.0,
          reps: 5,
          numSets: 3,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed2,
          userId: user.userId,
          weightKg: 80.0,
          reps: 5,
          numSets: 3,
          routineId: r2,
        );

        final plan = await readCurrentWeeklyPlan(admin, user.userId);
        final routines = routinesList(plan!);
        expect(
          routines,
          hasLength(2),
          reason:
              'both planned entries should be filled, no extra entries appended',
        );

        final r1Entry = routines.where((r) => r['routine_id'] == r1).toList();
        final r2Entry = routines.where((r) => r['routine_id'] == r2).toList();

        expect(r1Entry, hasLength(1));
        expect(
          r1Entry.first['completed_workout_id'],
          seed1.workoutId,
          reason: 'r1 entry must be filled with the first workout',
        );

        expect(r2Entry, hasLength(1));
        expect(
          r2Entry.first['completed_workout_id'],
          seed2.workoutId,
          reason: 'r2 entry must be filled with the second workout',
        );
      },
    );
  });
}
