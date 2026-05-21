/// Integration tests for the `earned_titles` award-at-detection path
/// (`record_session_xp_batch` extension in migration 00060) and the one-shot
/// `backfill_earned_titles` RPC (migration 00061).
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
/// Also pins idempotency on both paths: re-running either RPC never produces
/// duplicate rows (every INSERT uses `ON CONFLICT (user_id, title_id) DO NOTHING`).
/// The backfill group additionally pins that the ON CONFLICT clause preserves
/// `is_active` and the original `earned_at` on rows already inserted via the
/// detection path.
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

  test('should INSERT character-level "wanderer" title when character level '
      'crosses 10 (canonical formula — PR#252 regression pin)', () async {
    final user = await freshUser();
    final admin = serviceRoleClient();
    final userClient = authenticatedClient(user);

    // Character level (canonical formula, migration 00040 §9 / 00065 §8):
    //   character_level = GREATEST(1, FLOOR((SUM(rank) − N_active) / 4.0) + 1)
    //
    // The BUGGY pre-PR#252 formula was `rpg_rank_for_xp(SUM(total_xp))`, which
    // applied the per-body-part XP→rank curve to a cross-BP sum and produced
    // wildly inflated character levels. The old test seed (2 BPs at rank 6,
    // total_xp ~800) relied on the buggy formula returning pre-level=9 and
    // post-level=10; under the canonical formula the same seed gives level 3
    // pre and 3 post — wanderer never fires.
    //
    // Correct seed for canonical formula (wanderer = char-level 10):
    //   Pre-state:  5 BPs at rank 7, 1 BP (chest) at rank 6
    //     → SUM(rank) = 5×7 + 6 = 41, N_active = 6
    //     → char_level = floor((41 − 6) / 4) + 1 = floor(35/4) + 1 = 8+1 = 9
    //   Post-state: bench workout bumps chest r6 → r7 (all 6 BPs at rank 7)
    //     → SUM(rank) = 42, char_level = floor((42 − 6) / 4) + 1 = 9+1 = 10
    //     → wanderer threshold 10 fires (pre=9, post=10, threshold between)
    //
    // XP seed values chosen to be self-consistent with the rank curve:
    //   rank 7 = cumulativeXpForRank(7) = 60 × (1.10^6 − 1) / 0.10 ≈ 462.94
    //   rank 6 = cumulativeXpForRank(6) = 60 × (1.10^5 − 1) / 0.10 ≈ 366.31
    //   Chest seeded at 462.0 — just below the rank-7 threshold (462.94);
    //   any positive XP from bench 80×5 crosses it.
    //
    // No body-part title should fire for rank 7 because the catalog jumps
    // chest_r5 → chest_r10 (no rank-7 milestone), matching the title table.
    const rank7Xp = 462.94; // cumulativeXpForRank(7) ≈ 462.94
    const rank6Xp = 462.0; // just below rank-7 threshold

    // 5 BPs at rank 7 (the already-levelled body parts).
    for (final bp in ['back', 'legs', 'shoulders', 'arms', 'core']) {
      await seedBodyPartProgress(
        adminClient: admin,
        userId: user.userId,
        bodyPart: bp,
        totalXp: rank7Xp,
        rank: 7,
      );
    }
    // Chest at rank 6, just below rank-7 threshold — the workout bumps it.
    await seedBodyPartProgress(
      adminClient: admin,
      userId: user.userId,
      bodyPart: 'chest',
      totalXp: rank6Xp,
      rank: 6,
    );

    // Bench press: chest 0.70 / shoulders 0.20 / arms 0.10.
    // Even a single set of 80×5 (base_xp ≈ 6.3 at tier_diff_mult ~1 with
    // already-high rank, novelty=1.0 first set) gives chest ~4.4 XP attributed
    // (0.70 × ~6.3), safely crossing the 0.94 XP gap to rank 7.
    final seed = await seedWorkout(
      adminClient: admin,
      userId: user.userId,
      exerciseSlug: 'barbell_bench_press',
      weightKg: 80,
      reps: 5,
      numSets: 3,
    );
    await saveWorkoutRpc(
      userClient: userClient,
      seed: seed,
      userId: user.userId,
      weightKg: 80,
      reps: 5,
      numSets: 3,
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
          'character_level crosses 9→10 under the canonical formula '
          'GREATEST(1, FLOOR((SUM(rank) − N_active) / 4.0) + 1). '
          'Pre-state: 5 BPs at rank 7 + 1 at rank 6 → char-level 9. '
          'Post-state: chest crosses rank 6→7 → all 6 at rank 7 → char-level 10.',
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

  // -------------------------------------------------------------------------
  // 5. backfill_earned_titles RPC (migration 00061)
  //
  // The detection-time INSERT in 00060 only fires going forward — users who
  // crossed thresholds before 00060 shipped have zero earned_titles rows.
  // The backfill RPC walks current ranks + character level + cross-build
  // predicates once and inserts every title the user already qualifies for.
  // ON CONFLICT (user_id, title_id) DO NOTHING preserves live state (the
  // is_active flag + the original earned_at) on rows already inserted via
  // the detection path. See `00061_backfill_earned_titles.sql`.
  // -------------------------------------------------------------------------

  group('backfill_earned_titles', () {
    // Curve: cumulative(n) = 60 × (1.10^(n-1) - 1) / 0.10.
    //   rank 11 begins at ≈  956.25
    //   rank 12 begins at ≈ 1111.87
    //   rank 13 begins at ≈ 1283.06
    // 1200 maps to rank 12 (verified by `rpg_rank_for_xp(1200) = 12`).
    const chestRank12Xp = 1200.0;

    test(
      'should INSERT missing rows for a user with historical rank crossings',
      () async {
        // Simulates the pre-26d bug: user dismissed the R5 + R10 celebrations
        // without tapping equip, so earned_titles is empty but their chest is
        // at rank 12.
        final user = await freshUser();
        final admin = serviceRoleClient();
        await seedBodyPartProgress(
          adminClient: admin,
          userId: user.userId,
          bodyPart: 'chest',
          totalXp: chestRank12Xp,
          rank: 12,
        );
        await admin.from('earned_titles').delete().eq('user_id', user.userId);

        final userClient = authenticatedClient(user);
        await userClient.rpc(
          'backfill_earned_titles',
          params: {'p_user_id': user.userId},
        );

        final rows = await admin
            .from('earned_titles')
            .select('title_id')
            .eq('user_id', user.userId);
        final slugs = (rows as List)
            .map((r) => r['title_id'] as String)
            .toSet();
        expect(
          slugs,
          containsAll(<String>[
            'chest_r5_initiate_of_the_forge',
            'chest_r10_plate_bearer',
          ]),
          reason: 'every body-part title at or below rank 12 must be inserted',
        );
        // Upper boundary: threshold 15 must NOT fire for rank 12. Pins the
        // predicate so a regression from `<=` to `<` (or vice versa) fails.
        expect(
          slugs,
          isNot(contains('chest_r15_forge_marked')),
          reason:
              'chest_r15_forge_marked (threshold 15) must not fire for rank 12',
        );
      },
    );

    test('should produce the same rows on re-run (idempotent)', () async {
      final user = await freshUser();
      final admin = serviceRoleClient();
      await seedBodyPartProgress(
        adminClient: admin,
        userId: user.userId,
        bodyPart: 'chest',
        totalXp: chestRank12Xp,
        rank: 12,
      );
      await admin.from('earned_titles').delete().eq('user_id', user.userId);

      final userClient = authenticatedClient(user);

      await userClient.rpc(
        'backfill_earned_titles',
        params: {'p_user_id': user.userId},
      );
      final first = await admin
          .from('earned_titles')
          .select('title_id')
          .eq('user_id', user.userId);

      await userClient.rpc(
        'backfill_earned_titles',
        params: {'p_user_id': user.userId},
      );
      final second = await admin
          .from('earned_titles')
          .select('title_id')
          .eq('user_id', user.userId);

      final firstList = (first as List).cast<Map<String, dynamic>>();
      final secondList = (second as List).cast<Map<String, dynamic>>();
      expect(
        secondList.length,
        firstList.length,
        reason:
            'ON CONFLICT DO NOTHING must dedupe — no duplicate rows on re-run',
      );
      expect(
        secondList.map((r) => r['title_id']).toSet(),
        firstList.map((r) => r['title_id']).toSet(),
        reason: 're-run must produce the exact same slug set',
      );
    });

    test('should preserve is_active and earned_at on rows already INSERTed '
        'via detection', () async {
      final user = await freshUser();
      final admin = serviceRoleClient();
      await seedBodyPartProgress(
        adminClient: admin,
        userId: user.userId,
        bodyPart: 'chest',
        totalXp: chestRank12Xp,
        rank: 12,
      );
      await admin.from('earned_titles').delete().eq('user_id', user.userId);

      // Simulate pre-existing row from detection-time INSERT, equipped by the
      // user at an earlier date. The backfill MUST NOT flip is_active back
      // to FALSE or overwrite the earlier earned_at.
      final originalEarnedAt = DateTime.utc(2026, 5, 1).toIso8601String();
      await admin.from('earned_titles').insert(<String, dynamic>{
        'user_id': user.userId,
        'title_id': 'chest_r5_initiate_of_the_forge',
        'is_active': true,
        'earned_at': originalEarnedAt,
      });

      final userClient = authenticatedClient(user);
      await userClient.rpc(
        'backfill_earned_titles',
        params: {'p_user_id': user.userId},
      );

      final r5 = await admin
          .from('earned_titles')
          .select('is_active, earned_at')
          .eq('user_id', user.userId)
          .eq('title_id', 'chest_r5_initiate_of_the_forge')
          .single();
      expect(
        r5['is_active'],
        true,
        reason: 'ON CONFLICT DO NOTHING must not flip the active flag',
      );
      // earned_at comes back as ISO string from PostgREST.
      expect(
        DateTime.parse(r5['earned_at'] as String).toUtc(),
        DateTime.parse(originalEarnedAt).toUtc(),
        reason: 'ON CONFLICT DO NOTHING must not overwrite earned_at',
      );
    });
  });
}
