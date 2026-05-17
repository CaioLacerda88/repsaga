/// Integration tests for Phase 26d Task 2 — `earned_titles` award-at-detection.
///
/// Validates that `record_session_xp_batch` (the production save_workout
/// hot path) INSERTs into `earned_titles` whenever:
///   1. A body-part rank crosses a catalog threshold during the call.
///   2. The character level (sum of all body_part_progress.total_xp) crosses
///      one of the 7 character-level thresholds.
///   3. A cross-build distinction predicate (from migration 00043's
///      `evaluate_cross_build_titles_for_user`) fires against the post-save
///      rank distribution.
///
/// Also pins idempotency: re-running the RPC against the same workout never
/// produces duplicate `earned_titles` rows (the function's INSERT uses
/// `ON CONFLICT (user_id, title_id) DO NOTHING`).
///
/// Requires local Supabase running: `npx supabase start`.
///
/// Run: flutter test --tags integration test/integration/rpg_award_at_detection_test.dart
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
    final u = await createTestUser('rpg-award-$runId-$idx@test.local');
    currentUser = u;
    return u;
  }

  tearDown(() async {
    if (currentUser != null) {
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  // -------------------------------------------------------------------------
  // 1. Body-part rank crossing
  // -------------------------------------------------------------------------

  test('should INSERT body-part earned_titles row when chest rank crosses '
      'threshold during save_workout', () async {
    final user = await freshUser();
    final admin = serviceRoleClient();
    final userClient = authenticatedClient(user);

    // Seed chest body_part_progress just below rank 5. The cumulative curve
    // is `60 × (1.1^(n-1) - 1) / 0.10`; rank 5 requires ≈ 278.46 total_xp.
    // Seed at 278.0 so any positive XP from the workout pushes past it.
    // rank field on the seed must match rpg_rank_for_xp(278.0) = 4 to keep
    // the seed self-consistent.
    await seedBodyPartProgress(
      adminClient: admin,
      userId: user.userId,
      bodyPart: 'chest',
      totalXp: 278.0,
      rank: 4,
    );

    // Bench press → chest 0.70 / shoulders 0.20 / arms 0.10. Any
    // positive XP from 5 sets at 80 kg × 8 reps will push chest past rank 5.
    final seed = await seedWorkout(
      adminClient: admin,
      userId: user.userId,
      exerciseSlug: 'barbell_bench_press',
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );
    await saveWorkoutRpc(
      userClient: userClient,
      seed: seed,
      userId: user.userId,
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );

    final rows = await admin
        .from('earned_titles')
        .select('title_id, is_active, earned_at')
        .eq('user_id', user.userId);
    final list = (rows as List).cast<Map<String, dynamic>>();

    final chestR5 = list.where(
      (r) => r['title_id'] == 'chest_r5_initiate_of_the_forge',
    );
    expect(
      chestR5.length,
      1,
      reason:
          'chest_r5_initiate_of_the_forge must be inserted exactly once '
          'after the save_workout pushed chest past rank 5. Rows returned: $list',
    );
    expect(
      chestR5.first['is_active'],
      false,
      reason: 'detection-time INSERTs default is_active to FALSE',
    );
  });

  // -------------------------------------------------------------------------
  // 2. Idempotency (ON CONFLICT DO NOTHING)
  // -------------------------------------------------------------------------

  test('should not duplicate earned_titles row when RPC re-runs', () async {
    final user = await freshUser();
    final admin = serviceRoleClient();
    final userClient = authenticatedClient(user);

    await seedBodyPartProgress(
      adminClient: admin,
      userId: user.userId,
      bodyPart: 'chest',
      totalXp: 278.0,
      rank: 4,
    );

    final seed = await seedWorkout(
      adminClient: admin,
      userId: user.userId,
      exerciseSlug: 'barbell_bench_press',
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );

    // First save inserts the title row.
    await saveWorkoutRpc(
      userClient: userClient,
      seed: seed,
      userId: user.userId,
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );

    // Second save (same workout id) MUST NOT produce a duplicate row.
    await saveWorkoutRpc(
      userClient: userClient,
      seed: seed,
      userId: user.userId,
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );

    final rows = await admin
        .from('earned_titles')
        .select('title_id')
        .eq('user_id', user.userId)
        .eq('title_id', 'chest_r5_initiate_of_the_forge');
    expect(
      (rows as List).length,
      1,
      reason: 'ON CONFLICT (user_id, title_id) DO NOTHING must dedupe re-saves',
    );
  });

  // -------------------------------------------------------------------------
  // 3. Character-level crossing
  // -------------------------------------------------------------------------

  test('should INSERT character-level "wanderer" title when total XP crosses '
      'character level 10', () async {
    final user = await freshUser();
    final admin = serviceRoleClient();
    final userClient = authenticatedClient(user);

    // Character level = rpg_rank_for_xp(SUM(body_part_progress.total_xp)).
    // Curve: cumulative(n) = 60 × (1.1^(n-1) - 1) / 0.10.
    //   rank  9 begins at ≈ 686.15
    //   rank 10 begins at ≈ 814.77
    // Seed two body parts at 400 each (SUM = 800 → pre char level = 9,
    // each part still at rank 6 — far below the body-part thresholds, so
    // the body-part block won't accidentally fire). After the workout the
    // chest delta pushes SUM > 814.77, triggering the rank-10 wanderer.
    await seedBodyPartProgress(
      adminClient: admin,
      userId: user.userId,
      bodyPart: 'chest',
      totalXp: 400.0,
      rank: 6,
    );
    await seedBodyPartProgress(
      adminClient: admin,
      userId: user.userId,
      bodyPart: 'back',
      totalXp: 400.0,
      rank: 6,
    );

    final seed = await seedWorkout(
      adminClient: admin,
      userId: user.userId,
      exerciseSlug: 'barbell_bench_press',
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );
    await saveWorkoutRpc(
      userClient: userClient,
      seed: seed,
      userId: user.userId,
      weightKg: 80,
      reps: 8,
      numSets: 5,
    );

    final rows = await admin
        .from('earned_titles')
        .select('title_id')
        .eq('user_id', user.userId)
        .eq('title_id', 'wanderer');
    expect(
      (rows as List).length,
      1,
      reason:
          'wanderer (character level 10) must be inserted when '
          'SUM(body_part_progress.total_xp) crosses ≈ 853.59',
    );
  });

  // -------------------------------------------------------------------------
  // 4. Cross-build distinction (iron_bound: chest ≥ 60 AND back ≥ 60 AND legs ≥ 60)
  // -------------------------------------------------------------------------

  test('should INSERT cross-build "iron_bound" title when chest+back+legs all '
      'sit at rank 60', () async {
    final user = await freshUser();
    final admin = serviceRoleClient();
    final userClient = authenticatedClient(user);

    // Seed chest/back/legs at rank 60 directly. The save_workout call only
    // needs to fire the cross-build INSERT — the helper reads current
    // body_part_progress.rank values regardless of XP delta.
    //
    // rpg_cumulative_xp_for_rank(60) ≈ 60 × (1.1^59 - 1) / 0.1 ≈ 174 832.
    // Use any value at-or-above that.
    for (final bp in ['chest', 'back', 'legs']) {
      await seedBodyPartProgress(
        adminClient: admin,
        userId: user.userId,
        bodyPart: bp,
        totalXp: 200000.0,
        rank: 60,
      );
    }

    // Save any workout — XP delta doesn't matter for cross-build; the
    // helper scans the post-save rank distribution.
    final seed = await seedWorkout(
      adminClient: admin,
      userId: user.userId,
      exerciseSlug: 'barbell_bench_press',
      weightKg: 80,
      reps: 8,
      numSets: 1,
    );
    await saveWorkoutRpc(
      userClient: userClient,
      seed: seed,
      userId: user.userId,
      weightKg: 80,
      reps: 8,
      numSets: 1,
    );

    final rows = await admin
        .from('earned_titles')
        .select('title_id')
        .eq('user_id', user.userId)
        .eq('title_id', 'iron_bound');
    expect(
      (rows as List).length,
      1,
      reason:
          'iron_bound must be inserted when chest+back+legs all sit at rank ≥ 60. '
          'Verifies the cross-build helper from migration 00043 is wired into '
          'record_session_xp_batch.',
    );
  });
}
