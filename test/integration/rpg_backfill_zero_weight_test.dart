/// Integration test for the backfill path of the bodyweight-workout
/// regression — the active production bug fixed by 00051's trigger.
///
/// Background:
/// - 00050 patched `record_session_xp_batch` (the per-save XP function) so
///   `save_workout` no longer fails on bodyweight workouts.
/// - That fix missed `_rpg_backfill_chunk` (the retroactive XP function
///   called from `RpgRepository.runBackfill()` on first home render via
///   `SagaIntroGate._maybeKickRetro`).
/// - Result: production users with bodyweight history hit
///   `code=23514 / exercise_peak_loads_peak_weight_check` on first app
///   launch; the failure was swallowed by `.catchError((_) {})` so the user
///   saw nothing while their stats stayed at 0%.
/// - 00051 installs a BEFORE-INSERT trigger on `exercise_peak_loads` that
///   drops zero-weight rows silently. Backfill now commits cleanly even
///   though `_rpg_backfill_chunk`'s INSERT statement still fires unguarded
///   for bodyweight sets.
///
/// What this test pins:
///
/// 1. `backfill_rpg_v1` runs to completion against a user with bodyweight
///    history (would fail pre-00051 with code=23514).
/// 2. `xp_events` rows ARE created for the bodyweight sets (XP was earned).
/// 3. `body_part_progress.total_xp` advanced for the targeted body part.
/// 4. `exercise_peak_loads` has NO row for the bodyweight exercise — the
///    correct semantic per 00051's design comment.
///
/// Requires local Supabase running: `npx supabase start`
/// Run: flutter test --tags integration test/integration/rpg_backfill_zero_weight_test.dart
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
  late supabase.SupabaseClient admin;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('backfill-zero-$runId-$idx@test.local');
    currentUser = u;
    return u;
  }

  setUpAll(() {
    admin = serviceRoleClient();
  });

  tearDown(() async {
    if (currentUser != null) {
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  test('backfill_rpg_v1 commits a bodyweight-only history without violating '
      'peak_loads CHECK', () async {
    final user = await freshUser();

    // Seed a Plank-only workout (3 sets × 60 reps × 0 kg). This is the
    // exact shape that crashed `_rpg_backfill_chunk` in production.
    final seed = await seedWorkout(
      adminClient: admin,
      userId: user.userId,
      exerciseSlug: 'plank',
      weightKg: 0,
      reps: 60,
      numSets: 3,
    );

    // Run backfill AS THE AUTHENTICATED USER — the production path
    // (RpgRepository.runBackfill) and the only role `backfill_rpg_v1` is
    // GRANTed to (migration 00040 REVOKEs PUBLIC/anon, GRANTs authenticated
    // only; service_role is NOT granted, so the admin client gets 42501).
    // Admin stays the seeding client (RLS bypass for setup), matching the
    // other passing backfill integration tests. Pre-00051 this threw
    // PostgrestException code=23514; post-fix it returns out_is_complete=true.
    final userClient = authenticatedClient(user);
    final result = await userClient.rpc(
      'backfill_rpg_v1',
      params: {'p_user_id': user.userId, 'p_chunk_size': 500},
    );

    // RETURNS TABLE → list of rows.
    expect(result, isA<List<dynamic>>());
    expect((result as List).isNotEmpty, isTrue);
    final row = result.first as Map<String, dynamic>;
    expect(row['out_is_complete'], isTrue);
    expect(row['out_total_processed'] as num, greaterThanOrEqualTo(3));

    // xp_events rows present for all 3 bodyweight sets.
    final events =
        await admin
                .from('xp_events')
                .select()
                .eq('user_id', user.userId)
                .eq('event_type', 'set')
            as List<dynamic>;
    expect(
      events,
      hasLength(3),
      reason:
          'Each completed working set should have an xp_events row even '
          'though weight was 0 — bodyweight sets still earn XP.',
    );

    // body_part_progress was advanced for the body parts attributed to plank.
    // Plank's xp_attribution targets 'core' (per 00040 seed data); we don't
    // hard-code which body parts, just assert at least one row exists with
    // total_xp > 0.
    final bpRows =
        await admin
                .from('body_part_progress')
                .select()
                .eq('user_id', user.userId)
            as List<dynamic>;
    expect(bpRows, isNotEmpty);
    final hasNonZeroXp = bpRows.any(
      (r) => (r as Map<String, dynamic>)['total_xp'] as num > 0,
    );
    expect(
      hasNonZeroXp,
      isTrue,
      reason: 'At least one body_part_progress row should have total_xp > 0',
    );

    // exercise_peak_loads has NO row for the plank exercise — bodyweight
    // exercises shouldn't have peak_loads rows (peak_weight is meaningless).
    final peakRows =
        await admin
                .from('exercise_peak_loads')
                .select()
                .eq('user_id', user.userId)
                .eq('exercise_id', seed.exerciseId)
            as List<dynamic>;
    expect(
      peakRows,
      isEmpty,
      reason:
          'peak_loads should NOT have a row for the bodyweight Plank '
          'exercise. The trigger drops the zero-weight INSERT silently.',
    );
  });

  test(
    'backfill_rpg_v1 commits mixed weighted+bodyweight history correctly',
    () async {
      final user = await freshUser();

      // Two workouts, one weighted (squat) + one bodyweight (push-up).
      final squat = await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'barbell_squat',
        weightKg: 100,
        reps: 5,
        numSets: 3,
        startedAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      final pushup = await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'push_up',
        weightKg: 0,
        reps: 12,
        numSets: 3,
        startedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      // Authenticated-user RPC call (see the first test for the GRANT
      // rationale — backfill_rpg_v1 is authenticated-only).
      final userClient = authenticatedClient(user);
      final result = await userClient.rpc(
        'backfill_rpg_v1',
        params: {'p_user_id': user.userId, 'p_chunk_size': 500},
      );
      final row = (result as List).first as Map<String, dynamic>;
      expect(row['out_is_complete'], isTrue);

      // peak_loads has exactly ONE row — for the squat (weighted), not for
      // the push-up (bodyweight).
      final peakRows =
          await admin
                  .from('exercise_peak_loads')
                  .select()
                  .eq('user_id', user.userId)
              as List<dynamic>;
      expect(peakRows, hasLength(1));
      final peakRow = peakRows.single as Map<String, dynamic>;
      expect(peakRow['exercise_id'], squat.exerciseId);
      expect((peakRow['peak_weight'] as num).toDouble(), 100);
      // Push-up's exerciseId did not produce a peak_loads row.
      expect(peakRow['exercise_id'], isNot(pushup.exerciseId));

      // xp_events for both workouts.
      final events =
          await admin
                  .from('xp_events')
                  .select()
                  .eq('user_id', user.userId)
                  .eq('event_type', 'set')
              as List<dynamic>;
      expect(events, hasLength(6)); // 3 squat + 3 push-up
    },
  );
}
