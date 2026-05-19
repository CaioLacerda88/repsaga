/// Integration tests for the Phase 27 L10 `peak_load_per_body_part` RPC
/// (migration 00064).
///
/// The function powers the new "Carga pico" readout on the stats deep-dive
/// screen — heaviest single-set weight in kg per body part within a
/// time window. Replaces the pre-Phase-27 misuse of Vitality EWMA as if
/// it were a weight value.
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

import 'rpg_integration_setup.dart';

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;
  TestUser? currentUser;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('peak-load-27l10-$runId-$idx@test.local');
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

  group('peak_load_per_body_part', () {
    test(
      'should return the heaviest single-set weight per body part for sets in the window',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // Bench press (chest-primary; attributes to chest, shoulders, arms).
        // Two workouts in the last 7 days, weights 60 / 80 — peak is 80.
        await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60.0,
          reps: 5,
          numSets: 3,
          startedAt: DateTime.now().subtract(const Duration(days: 5)),
        );
        await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 80.0,
          reps: 3,
          numSets: 3,
          startedAt: DateTime.now().subtract(const Duration(days: 2)),
        );

        final peaks = await callRpc(user: user);

        // Chest is the primary share — must reflect heaviest bench.
        expect(peaks['chest'], 80.0);
        // Shoulders + arms ride along on bench attribution and inherit the
        // same MAX(weight) — they don't have to be the primary share.
        expect(peaks['shoulders'], 80.0);
        expect(peaks['arms'], 80.0);
        // Body parts the user never trained → absent from result.
        expect(peaks.containsKey('legs'), isFalse);
        expect(peaks.containsKey('back'), isFalse);
        expect(peaks.containsKey('core'), isFalse);
      },
    );

    test('should exclude workouts finished before the window opens', () async {
      final user = await freshUser();
      final admin = serviceRoleClient();

      // 10 days ago — outside the 7-day window. Should not contribute.
      await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'barbell_bench_press',
        weightKg: 100.0,
        reps: 3,
        numSets: 1,
        startedAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      // 3 days ago — inside.
      await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'barbell_bench_press',
        weightKg: 70.0,
        reps: 5,
        numSets: 3,
        startedAt: DateTime.now().subtract(const Duration(days: 3)),
      );

      final peaks = await callRpc(user: user);
      // 100 kg is filtered out by the window; the in-window 70 kg wins.
      expect(peaks['chest'], 70.0);
    });

    test(
      'should ignore zero-weight sets (bodyweight or unfilled entries)',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // 0-kg sets — should not count even if attributed.
        await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 0,
          reps: 10,
          numSets: 3,
        );

        final peaks = await callRpc(user: user);
        // No non-zero-weight sets → body part absent from the result.
        expect(peaks.containsKey('chest'), isFalse);
      },
    );

    test(
      'should isolate users — one user\'s sets must not appear in another user\'s peaks',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // Create a second isolated user with a heavier lift.
        final other = await createTestUser(
          'peak-load-isolation-$runId@test.local',
        );
        try {
          await seedWorkout(
            adminClient: admin,
            userId: other.userId,
            exerciseSlug: 'barbell_bench_press',
            weightKg: 200,
            reps: 1,
            numSets: 1,
          );
          // user (the one being queried) lifts only 50 kg.
          await seedWorkout(
            adminClient: admin,
            userId: user.userId,
            exerciseSlug: 'barbell_bench_press',
            weightKg: 50,
            reps: 5,
            numSets: 3,
          );

          final peaks = await callRpc(user: user);
          // RLS + JOIN filter must isolate users — we see only our own 50 kg.
          expect(peaks['chest'], 50.0);
        } finally {
          await deleteTestUser(other.userId);
        }
      },
    );

    test(
      'should accept a custom end_date for a backward-looking snapshot window',
      () async {
        final user = await freshUser();
        final admin = serviceRoleClient();

        // Heavy lift 35 days ago — inside a window ending "30 days ago" of
        // length 7 days.
        await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 60,
          reps: 5,
          numSets: 3,
          startedAt: DateTime.now().subtract(const Duration(days: 35)),
        );
        // Newer lift inside the current 7-day window — must NOT appear in
        // the snapshot.
        await seedWorkout(
          adminClient: admin,
          userId: user.userId,
          exerciseSlug: 'barbell_bench_press',
          weightKg: 90,
          reps: 3,
          numSets: 3,
          startedAt: DateTime.now().subtract(const Duration(days: 2)),
        );

        final snapshotPeaks = await callRpc(
          user: user,
          days: 7,
          endDate: DateTime.now().subtract(const Duration(days: 30)),
        );
        expect(snapshotPeaks['chest'], 60.0);

        // Sanity: the default (current) window picks up the 90 kg.
        final currentPeaks = await callRpc(user: user);
        expect(currentPeaks['chest'], 90.0);
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
