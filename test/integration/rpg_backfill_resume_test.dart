/// Integration tests for Phase 18a `backfill_rpg_v1` resume-after-kill
/// semantics.
///
/// Requires local Supabase running: `npx supabase start`
///
/// What these tests validate:
///
/// 1. **Resume via checkpoint** — a backfill is run with chunk_size=5 so it
///    stops mid-way. The `backfill_progress.last_set_id` cursor is durably
///    written. A second backfill invocation (simulating a restart after kill)
///    processes the remaining sets and arrives at the same final state as a
///    single-run backfill on the same data.
///
/// 2. **No double-counting on resume** — the body_part_progress totals after a
///    partial run are strictly less than or equal to the final totals (the
///    cursor skips already-processed sets).
///
/// 3. **Advisory lock serialization** — two concurrent backfill calls for the
///    same user must produce a correct final state with no XP double-counting
///    and exactly one xp_events row per set.
///
/// Run: flutter test --tags integration test/integration/rpg_backfill_resume_test.dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'rpg_integration_setup.dart';
import 'rpg_backfill_test.dart'
    show
        BackfillFixture,
        ExerciseDef,
        seedFixtureWorkouts,
        computeDartReference,
        kBackfillTol;

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------------------
  // Small fixture for resume tests
  //
  // 5 weeks × 1 session × 3 exercises = 15 sets.
  // Small enough that chunk_size=5 creates 3 deterministic chunks.
  // ---------------------------------------------------------------------------

  // Phase 24a Phase F: each ExerciseDef carries the curated difficulty_mult
  // from migration 00053 so the Dart reference (computeDartReference shared
  // with rpg_backfill_test.dart) mirrors what `_rpg_backfill_chunk` reads
  // from `exercises.difficulty_mult` per set.
  const kSmallFixture = BackfillFixture(
    exercises: [
      ExerciseDef(
        slug: 'barbell_bench_press',
        weightKg: 80.0,
        reps: 8,
        attribution: {'chest': 0.70, 'shoulders': 0.20, 'arms': 0.10},
        difficultyMult: 1.09,
      ),
      ExerciseDef(
        slug: 'lat_pulldown',
        weightKg: 60.0,
        reps: 10,
        attribution: {'back': 0.75, 'arms': 0.20, 'core': 0.05},
        difficultyMult: 0.99,
      ),
      ExerciseDef(
        slug: 'barbell_squat',
        weightKg: 100.0,
        reps: 5,
        attribution: {'legs': 0.80, 'core': 0.10, 'back': 0.10},
        difficultyMult: 1.19,
      ),
    ],
    weeksCount: 5,
    sessionsPerWeek: 1,
  );

  group('backfill_rpg_v1 resume-after-kill', () {
    late TestUser user;
    late TestUser referenceUser;

    setUp(() async {
      user = await createTestUser('rpg-resume-$runId@test.local');
      referenceUser = await createTestUser('rpg-resume-ref-$runId@test.local');
    });

    tearDown(() async {
      await deleteTestUser(user.userId);
      await deleteTestUser(referenceUser.userId);
    });

    test(
      'partial chunk + resume produces same final state as single full run',
      () async {
        final adminClient = serviceRoleClient();
        final userClient = authenticatedClient(user);
        final refClient = authenticatedClient(referenceUser);

        // Seed identical workout data for both users.
        await seedFixtureWorkouts(adminClient, user.userId, kSmallFixture);
        await seedFixtureWorkouts(
          adminClient,
          referenceUser.userId,
          kSmallFixture,
        );

        // REFERENCE: single full run (large chunk_size = no interruption).
        await runBackfillDirect(
          userClient: refClient,
          userId: referenceUser.userId,
          chunkSize: 500,
        );

        // USER: partial first chunk (5 of 15 sets).
        final result1 = await userClient.rpc(
          'backfill_rpg_v1',
          params: {'p_user_id': user.userId, 'p_chunk_size': 5},
        );
        final firstChunkRow = _firstRow(result1);
        expect(
          firstChunkRow['out_is_complete'],
          isFalse,
          reason: 'First 5-set chunk out of 15 must not be complete',
        );
        expect(
          (firstChunkRow['out_processed'] as num).toInt(),
          equals(5),
          reason: 'First chunk must process exactly 5 sets',
        );

        // Checkpoint must be written.
        final progressAfterChunk1 = await getBackfillProgressDirect(
          userClient: userClient,
        );
        expect(progressAfterChunk1, isNotNull);
        expect(
          progressAfterChunk1!['last_set_id'],
          isNotNull,
          reason:
              'backfill_progress.last_set_id must be persisted after chunk 1',
        );
        expect(progressAfterChunk1['completed_at'], isNull);
        expect(
          (progressAfterChunk1['sets_processed'] as num).toInt(),
          equals(5),
        );

        // RESUME: run to completion.
        final resumeTotal = await runBackfillDirect(
          userClient: userClient,
          userId: user.userId,
          chunkSize: 5,
        );
        expect(
          resumeTotal,
          equals(kSmallFixture.totalSets),
          reason:
              'Total processed after resume must equal fixture total '
              '(${kSmallFixture.totalSets}), got $resumeTotal',
        );

        // Final progress must be complete.
        final finalProgress = await getBackfillProgressDirect(
          userClient: userClient,
        );
        expect(finalProgress!['completed_at'], isNotNull);

        // Compare final body_part_progress with reference user.
        final userRows = await userClient
            .from('body_part_progress')
            .select('body_part, total_xp, rank')
            .order('body_part');
        final refRows = await refClient
            .from('body_part_progress')
            .select('body_part, total_xp, rank')
            .order('body_part');

        expect(
          (userRows as List).length,
          equals((refRows as List).length),
          reason:
              'User and reference must have the same number of '
              'body_part_progress rows after resume',
        );

        final userRowsList = userRows as List;
        final refRowsList = refRows as List;
        for (var i = 0; i < userRowsList.length; i++) {
          final uRow = Map<String, dynamic>.from(userRowsList[i] as Map);
          final rRow = Map<String, dynamic>.from(refRowsList[i] as Map);

          final bp = uRow['body_part'] as String;
          expect(
            bp,
            equals(rRow['body_part']),
            reason: 'Row $i body_part mismatch',
          );

          final uXp = (uRow['total_xp'] as num).toDouble();
          final rXp = (rRow['total_xp'] as num).toDouble();
          expect(
            (uXp - rXp).abs(),
            lessThanOrEqualTo(_kResumeTol),
            reason:
                '$bp: resumed XP $uXp vs reference XP $rXp '
                '(delta ${(uXp - rXp).abs()})',
          );

          expect(
            uRow['rank'],
            equals(rRow['rank']),
            reason:
                '$bp: resumed rank ${uRow["rank"]} vs reference rank '
                '${rRow["rank"]}',
          );
        }
      },
    );

    test(
      'resume from cursor skips already-processed sets (no double-counting)',
      () async {
        final adminClient = serviceRoleClient();
        final userClient = authenticatedClient(user);

        await seedFixtureWorkouts(adminClient, user.userId, kSmallFixture);

        // Run first chunk (5 sets).
        await userClient.rpc(
          'backfill_rpg_v1',
          params: {'p_user_id': user.userId, 'p_chunk_size': 5},
        );

        // Snapshot XP after first chunk.
        final rowsAfterChunk1 = await userClient
            .from('body_part_progress')
            .select('body_part, total_xp');
        final xpAfterChunk1 = {
          for (final row in rowsAfterChunk1 as List)
            (row as Map<String, dynamic>)['body_part'] as String:
                (row['total_xp'] as num).toDouble(),
        };

        // Run to completion.
        await runBackfillDirect(
          userClient: userClient,
          userId: user.userId,
          chunkSize: 5,
        );

        // Final XP for every body part must be >= intermediate value.
        final rowsFinal = await userClient
            .from('body_part_progress')
            .select('body_part, total_xp');
        final xpFinal = {
          for (final row in rowsFinal as List)
            (row as Map<String, dynamic>)['body_part'] as String:
                (row['total_xp'] as num).toDouble(),
        };

        for (final entry in xpAfterChunk1.entries) {
          final bp = entry.key;
          final xpChunk1 = entry.value;
          final xpCompleted = xpFinal[bp] ?? 0.0;
          expect(
            xpCompleted,
            greaterThanOrEqualTo(xpChunk1 - 1e-9),
            reason:
                '$bp: final XP $xpCompleted must be >= post-chunk-1 XP '
                '$xpChunk1 (resume must not wipe after first chunk)',
          );
        }

        // Also verify final state matches the Dart reference.
        final dartRef = computeDartReference(kSmallFixture);
        for (final entry in dartRef.entries) {
          final bp = entry.key;
          final dartXp = entry.value;
          if (dartXp < 0.001) continue;
          final pgXp = xpFinal[bp] ?? 0.0;
          expect(
            (pgXp - dartXp).abs(),
            lessThanOrEqualTo(kBackfillTol),
            reason: '$bp: resumed final XP $pgXp vs Dart $dartXp',
          );
        }
      },
    );
  });

  group('backfill_rpg_v1 advisory lock serialization', () {
    late TestUser user;

    setUp(() async {
      user = await createTestUser('rpg-lock-$runId@test.local');
    });

    tearDown(() async {
      await deleteTestUser(user.userId);
    });

    test('concurrent backfill loops for same user: no double-counting in '
        'xp_events', () async {
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      await seedFixtureWorkouts(adminClient, user.userId, kSmallFixture);

      // Launch two concurrent backfill loops.
      await Future.wait([
        runBackfillDirect(
          userClient: userClient,
          userId: user.userId,
          chunkSize: 5,
        ),
        runBackfillDirect(
          userClient: userClient,
          userId: user.userId,
          chunkSize: 5,
        ),
      ]);

      // Completed.
      final progress = await getBackfillProgressDirect(userClient: userClient);
      expect(
        progress?['completed_at'],
        isNotNull,
        reason: 'backfill_progress must be complete after concurrent runs',
      );

      // xp_events must have exactly totalSets rows (no duplicates).
      final events = await userClient.from('xp_events').select('id');
      expect(
        (events as List).length,
        equals(kSmallFixture.totalSets),
        reason:
            'Expected ${kSmallFixture.totalSets} xp_events rows; concurrent '
            'run must not insert duplicates. Got ${(events).length}',
      );

      // body_part_progress must match the Dart reference.
      final dartRef = computeDartReference(kSmallFixture);
      final pgRows = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp');
      final pgByBp = {
        for (final row in pgRows as List)
          (row as Map<String, dynamic>)['body_part'] as String:
              (row['total_xp'] as num).toDouble(),
      };

      for (final entry in dartRef.entries) {
        final bp = entry.key;
        final dartXp = entry.value;
        if (dartXp < 0.001) continue;
        final pgXp = pgByBp[bp] ?? 0.0;
        expect(
          (pgXp - dartXp).abs(),
          lessThanOrEqualTo(kBackfillTol),
          reason: '$bp: concurrent XP $pgXp vs Dart $dartXp',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _firstRow(dynamic result) {
  if (result is List && result.isNotEmpty) {
    return Map<String, dynamic>.from(result.first as Map);
  }
  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }
  throw Exception('Unexpected RPC result shape: $result');
}

/// Tolerance for resume parity checks. Slightly wider than the parity
/// tolerance because the weekly_volume window can shift by 1-2 ms between
/// the reference run and the interrupted run depending on wall-clock timing
/// during the test.
const double _kResumeTol = 0.5;
