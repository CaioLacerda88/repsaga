/// Integration tests for the `peak_load_per_body_part` RPC under the Phase 32
/// PR 32j primary-only attribution semantics (migration 00071, replacing the
/// 00064 body in place).
///
/// The function powers the "Carga pico" readout on the stats deep-dive
/// screen — heaviest single-set weight in kg per body part within a
/// time window. Post-32j, a set "counts toward body part X" iff X has the
/// MAX `xp_attribution` share for that exercise (primary-only). Multi-BP
/// exercises no longer bleed their top weight into secondary body parts.
///
/// Requires local Supabase running: `npx supabase start`.
///
/// Run:
///   export PATH="/c/flutter/bin:$PATH"
///   flutter test --tags integration test/integration/peak_load_per_body_part_test.dart
@Tags(['integration'])
library;

// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'rpg_integration_setup.dart';

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;
  TestUser? currentUser;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('peak-load-32j-$runId-$idx@test.local');
    currentUser = u;
    return u;
  }

  tearDown(() async {
    if (currentUser != null) {
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  /// Calls the RPC as the authenticated user and returns a
  /// `{body_part: peak_load_kg}` map. We accept the result as `List<Map>` per
  /// PostgREST's `RETURNS TABLE` serialization.
  Future<Map<String, double>> callRpc({
    required TestUser user,
    int days = 7,
    DateTime? endDate,
  }) async {
    final client = authenticatedClient(user);
    final params = <String, dynamic>{'p_user_id': user.userId, 'p_days': days};
    if (endDate != null) {
      params['p_end_date'] = endDate.toUtc().toIso8601String();
    }
    final raw = await client.rpc('peak_load_per_body_part', params: params);
    final rows = (raw as List).cast<Map<String, dynamic>>();
    return {
      for (final row in rows)
        (row['body_part'] as String): (row['peak_load_kg'] as num).toDouble(),
    };
  }

  /// Inserts a user-owned custom exercise with the exact [xpAttribution]
  /// payload supplied. Returns the new exercise id. Uses the service-role
  /// client so the row is owned by [userId] but the insert bypasses RLS.
  ///
  /// `xp_attribution = null` represents the unmapped-fallback case (the same
  /// shape that user-created exercises ship with pre-attribution-fallback).
  Future<String> seedCustomExercise({
    required supabase.SupabaseClient adminClient,
    required String userId,
    required String name,
    Map<String, double>? xpAttribution,
  }) async {
    final inserted = await adminClient
        .from('exercises')
        .insert({
          'name': name,
          'muscle_group': 'chest', // arbitrary — never read by this RPC
          'equipment_type': 'barbell', // arbitrary — never read by this RPC
          'is_default': false,
          'user_id': userId,
          'xp_attribution': xpAttribution,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Seeds a single-workout / single-exercise / single-set scenario against
  /// the [exerciseId] supplied. Mirrors `seedWorkout` from the harness but
  /// accepts an arbitrary `exercise_id` so tests can target custom-attribution
  /// exercises (which the slug-based `seedWorkout` cannot reach).
  Future<void> seedSetForExercise({
    required supabase.SupabaseClient adminClient,
    required String userId,
    required String exerciseId,
    required double weightKg,
    DateTime? startedAt,
  }) async {
    final ts = (startedAt ?? DateTime.now()).toUtc();
    final workoutRes = await adminClient
        .from('workouts')
        .insert({
          'user_id': userId,
          'name': 'Integration Test Workout',
          'started_at': ts.toIso8601String(),
          'finished_at': ts.add(const Duration(hours: 1)).toIso8601String(),
          'is_active': false,
        })
        .select('id')
        .single();
    final workoutId = workoutRes['id'] as String;

    final weRes = await adminClient
        .from('workout_exercises')
        .insert({
          'workout_id': workoutId,
          'exercise_id': exerciseId,
          'order': 1,
        })
        .select('id')
        .single();
    final weId = weRes['id'] as String;

    await adminClient.from('sets').insert({
      'workout_exercise_id': weId,
      'set_number': 1,
      'reps': 5,
      'weight': weightKg,
      'is_completed': true,
      'set_type': 'working',
    });
  }

  group('peak_load_per_body_part — primary-only attribution', () {
    test(
      'should attribute a multi-BP exercise top weight to the primary BP only — no bleed into secondaries',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // Shoulder press — shoulders is the dominant share. Pre-32j the
        // arms=0.2 share would have bled the 30 kg into arms too.
        final shoulderPressId = await seedCustomExercise(
          adminClient: admin,
          userId: user.userId,
          name: 'Integration Shoulder Press 32j',
          xpAttribution: {'shoulders': 0.7, 'arms': 0.3},
        );
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: shoulderPressId,
          weightKg: 30,
        );

        // A separate arms-primary (effectively arms-only) exercise at a
        // lighter weight. Arms should pick up THIS value — NOT the 30 kg
        // from the shoulder press.
        final armsOnlyId = await seedCustomExercise(
          adminClient: admin,
          userId: user.userId,
          name: 'Integration Arms Only 32j',
          xpAttribution: {'arms': 1.0},
        );
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: armsOnlyId,
          weightKg: 20,
        );

        final peaks = await callRpc(user: user);

        // Shoulders gets the shoulder-press peak (its primary share).
        expect(peaks['shoulders'], 30.0);
        // Arms gets the arms-only peak — the shoulder-press 30 kg does NOT
        // bleed in. This is the exact pre-launch device-verification bug
        // the PR fixes.
        expect(peaks['arms'], 20.0);
        // Body parts the user never touched stay absent.
        expect(peaks.containsKey('chest'), isFalse);
        expect(peaks.containsKey('back'), isFalse);
        expect(peaks.containsKey('legs'), isFalse);
        expect(peaks.containsKey('core'), isFalse);
      },
    );

    test(
      'should include every tied-primary BP when shares are equal (max-share inclusion)',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // Hypothetical exact-tie exercise. No calibrated default ships this
        // shape today, but the RPC must handle it: both chest and back are
        // primary (share = max_share = 0.5), so both absorb the top weight.
        final tiedId = await seedCustomExercise(
          adminClient: admin,
          userId: user.userId,
          name: 'Integration Tied Primary 32j',
          xpAttribution: {'chest': 0.5, 'back': 0.5},
        );
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: tiedId,
          weightKg: 40,
        );

        final peaks = await callRpc(user: user);

        expect(peaks['chest'], 40.0);
        expect(peaks['back'], 40.0);
        // Untouched body parts absent.
        expect(peaks.containsKey('shoulders'), isFalse);
        expect(peaks.containsKey('arms'), isFalse);
      },
    );

    test(
      'should exclude exercises with NULL xp_attribution (no fallback to muscle_group inside the RPC)',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // User-created exercises ship with NULL attribution; the RPC does
        // not perform a primary_muscle_group fallback (that lives at the
        // exercise edit/save layer). So this 50 kg set must NOT surface.
        final unmappedId = await seedCustomExercise(
          adminClient: admin,
          userId: user.userId,
          name: 'Integration Unmapped 32j',
          // null attribution — falls through jsonb_each_text as 0 rows.
        );
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: unmappedId,
          weightKg: 50,
        );

        final peaks = await callRpc(user: user);

        // Empty result — no body part receives the 50 kg.
        expect(peaks, isEmpty);
      },
    );

    test(
      'should honor a half-open window: workout at exactly end_date is IN, at exactly end_date - days is OUT',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        final endDate = DateTime.now().toUtc().subtract(
          const Duration(hours: 1), // a safe distance from "now()"
        );
        const days = 7;
        final windowOpen = endDate.subtract(const Duration(days: days));

        final exId = await seedCustomExercise(
          adminClient: admin,
          userId: user.userId,
          name: 'Integration Window 32j',
          xpAttribution: {'chest': 1.0},
        );

        // Workout at EXACTLY end_date - days → OUT (window is half-open
        // on the left: `> end_date - interval`).
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: exId,
          weightKg: 100, // would dominate if it were in
          startedAt: windowOpen,
        );
        // Workout at EXACTLY end_date → IN (window includes the right edge).
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: exId,
          weightKg: 60,
          startedAt: endDate,
        );

        final peaks = await callRpc(user: user, days: days, endDate: endDate);

        // Only the right-edge 60 kg survives — the 100 kg at the left
        // boundary is excluded by the strict `>` half-open semantics.
        expect(peaks['chest'], 60.0);
      },
    );

    test(
      'should isolate users — one user\'s sets never appear in another\'s peaks',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        final other = await createTestUser(
          'peak-load-32j-isolation-$runId@test.local',
        );
        try {
          // `other` lifts heavy on a chest-primary exercise.
          final otherEx = await seedCustomExercise(
            adminClient: admin,
            userId: other.userId,
            name: 'Integration Isolation Other 32j',
            xpAttribution: {'chest': 1.0},
          );
          await seedSetForExercise(
            adminClient: admin,
            userId: other.userId,
            exerciseId: otherEx,
            weightKg: 200,
          );

          // `user` lifts light on their own chest-primary exercise.
          final ourEx = await seedCustomExercise(
            adminClient: admin,
            userId: user.userId,
            name: 'Integration Isolation Self 32j',
            xpAttribution: {'chest': 1.0},
          );
          await seedSetForExercise(
            adminClient: admin,
            userId: user.userId,
            exerciseId: ourEx,
            weightKg: 50,
          );

          final peaks = await callRpc(user: user);

          // RLS + JOIN on workouts.user_id must hide the other user's 200 kg.
          expect(peaks['chest'], 50.0);
        } finally {
          await deleteTestUser(other.userId);
        }
      },
    );

    test(
      'should ignore zero-weight sets even on primary-attributed exercises',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        final exId = await seedCustomExercise(
          adminClient: admin,
          userId: user.userId,
          name: 'Integration Zero Weight 32j',
          xpAttribution: {'chest': 1.0},
        );
        await seedSetForExercise(
          adminClient: admin,
          userId: user.userId,
          exerciseId: exId,
          weightKg: 0,
        );

        final peaks = await callRpc(user: user);

        // The `s.weight > 0` filter in the CTE drops the bodyweight/unfilled
        // set before it can reach the max-share computation. No row emitted.
        expect(peaks, isEmpty);
      },
    );

    test(
      'should return an empty result for a user with zero workouts',
      () async {
        final user = await freshUser();
        final peaks = await callRpc(user: user);
        expect(peaks, isEmpty);
      },
    );
  });
}
