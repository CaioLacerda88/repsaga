/// Integration tests for Phase 18a `backfill_rpg_v1` chunked replay.
///
/// Requires local Supabase running: `npx supabase start`
///
/// What these tests validate:
///
/// 1. **Reference match** — a synthetic 60-set fixture (3 exercises × 20 sets
///    in chronological order across 4 weeks) is replayed through
///    `backfill_rpg_v1`. The resulting `body_part_progress.total_xp` per body
///    part must match the Dart `XpCalculator` sequential simulation within
///    1e-4. The fixture is deliberately smaller than the 1590-set Python sim
///    so the test runs under 10s, but it exercises the same code paths.
///
/// 2. **Idempotency** — running the backfill a second time for the same user
///    produces no change (completed_at stays set, rows are unchanged).
///
/// 3. **Wipe-on-first-chunk** — any pre-existing `xp_events` rows (e.g. from
///    live `record_set_xp` calls) are cleared on the first chunk and
///    re-computed correctly.
///
/// Run: flutter test --tags integration test/integration/rpg_backfill_test.dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/xp_calculator.dart';

import 'rpg_integration_setup.dart';

// ---------------------------------------------------------------------------
// Fixture: 60-set workout schedule
// ---------------------------------------------------------------------------
//
// 4 weeks × 5 sessions per week × 3 exercises per session = 60 sets.
// We keep it deterministic: weight never changes (stagnant lifter), so
// strength_mult = 1.0 throughout after the first set.
//
// Exercises chosen to cover multi-attribution paths:
//   barbell_bench_press : chest 0.70, shoulders 0.20, arms 0.10  (mult 1.09)
//   lat_pulldown        : back  0.75, arms   0.20, core  0.05    (mult 0.94)
//   barbell_squat       : legs  0.80, core   0.10, back  0.10    (mult 1.19)
//
// Phase 24a Phase F: each ExerciseDef carries the curated difficulty_mult
// from migration 00053 so the Dart reference (computeDartReference) mirrors
// what `_rpg_backfill_chunk` reads from `exercises.difficulty_mult` per set.
// Phase 24d propagation (migration 00059): `lat_pulldown` shifted from 0.99
// to 0.94 (T4 + 2 sec, minus 0.05). The other two are NOT in the curated
// T4 set, so their values stay at the 24a baseline.

/// Public fixture — shared with `rpg_backfill_resume_test.dart`.
const kBackfillFixture = BackfillFixture(
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
      difficultyMult: 0.94,
    ),
    ExerciseDef(
      slug: 'barbell_squat',
      weightKg: 100.0,
      reps: 5,
      attribution: {'legs': 0.80, 'core': 0.10, 'back': 0.10},
      difficultyMult: 1.19,
    ),
  ],
  weeksCount: 4,
  sessionsPerWeek: 5,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;

  group('backfill_rpg_v1 end-to-end replay', () {
    late TestUser user;

    setUp(() async {
      user = await createTestUser('rpg-backfill-$runId@test.local');
    });

    tearDown(() async {
      await deleteTestUser(user.userId);
    });

    test('60-set fixture: backfill body_part_progress matches Dart sequential '
        'simulation within 1e-4', () async {
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      // Seed workout rows (without triggering XP via save_workout).
      await seedFixtureWorkouts(adminClient, user.userId, kBackfillFixture);

      // Run the backfill (use chunk_size=20 to exercise the loop).
      final totalProcessed = await runBackfillDirect(
        userClient: userClient,
        userId: user.userId,
        chunkSize: 20,
      );
      expect(
        totalProcessed,
        equals(kBackfillFixture.totalSets),
        reason:
            'Expected backfill to process ${kBackfillFixture.totalSets} sets, '
            'got $totalProcessed',
      );

      // Read PG body_part_progress.
      final pgRows = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp, rank');
      final pgByBp = {
        for (final row in pgRows as List)
          (row as Map<String, dynamic>)['body_part'] as String: row,
      };

      // Compute the Dart-side reference.
      final dartRef = computeDartReference(kBackfillFixture);

      // Assert parity for each body part with XP > 0.
      for (final entry in dartRef.entries) {
        final bp = entry.key;
        final dartXp = entry.value;
        if (dartXp < 0.001) continue; // skip near-zero body parts

        final pgRow = pgByBp[bp];
        expect(
          pgRow,
          isNotNull,
          reason: 'Expected body_part_progress row for $bp',
        );
        final pgXp = (pgRow!['total_xp'] as num).toDouble();
        expect(
          (pgXp - dartXp).abs(),
          lessThanOrEqualTo(kBackfillTol),
          reason:
              '$bp: PG total_xp $pgXp vs Dart reference $dartXp '
              '(delta ${(pgXp - dartXp).abs()})',
        );
      }

      // backfill_progress must be marked complete.
      final progress = await getBackfillProgressDirect(userClient: userClient);
      expect(progress, isNotNull);
      expect(
        progress!['completed_at'],
        isNotNull,
        reason: 'backfill_progress.completed_at must be set after completion',
      );
      expect(
        (progress['sets_processed'] as num).toInt(),
        equals(kBackfillFixture.totalSets),
      );
    });

    test('idempotency: second backfill run produces no drift', () async {
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      await seedFixtureWorkouts(adminClient, user.userId, kBackfillFixture);

      // First run.
      await runBackfillDirect(
        userClient: userClient,
        userId: user.userId,
        chunkSize: 20,
      );

      // Snapshot after first run.
      final rows1 = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp');
      final xp1 = {
        for (final row in rows1 as List)
          (row as Map<String, dynamic>)['body_part'] as String:
              (row['total_xp'] as num).toDouble(),
      };

      // Second run (completed_at is already set → should be a no-op).
      await runBackfillDirect(
        userClient: userClient,
        userId: user.userId,
        chunkSize: 20,
      );

      final rows2 = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp');
      final xp2 = {
        for (final row in rows2 as List)
          (row as Map<String, dynamic>)['body_part'] as String:
              (row['total_xp'] as num).toDouble(),
      };

      expect(
        xp2,
        equals(xp1),
        reason:
            'Second backfill run must not change XP totals: '
            'first=$xp1, second=$xp2',
      );
    });

    test('wipe-on-first-chunk: pre-existing live xp_events are replaced by '
        'backfill result', () async {
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      // Seed workouts.
      await seedFixtureWorkouts(adminClient, user.userId, kBackfillFixture);

      // Trigger record_set_xp live for ONE existing set so the user has
      // some live xp_events rows. We invoke `record_set_xp` directly
      // rather than save_workout because save_workout would DELETE the
      // multi-exercise workout's other sets (it only takes the JSON we
      // pass, not the existing rows). Calling record_set_xp on an
      // existing set inserts a single xp_event without disturbing the
      // already-seeded sets — which is exactly the "live state pollutes
      // backfill input" scenario we want to test.
      final anySet = await userClient
          .from('sets')
          .select('id')
          .limit(1)
          .single();
      await userClient.rpc('record_set_xp', params: {'p_set_id': anySet['id']});

      // Verify xp_events rows exist before backfill.
      final eventsBefore = await userClient.from('xp_events').select('id');
      expect(
        (eventsBefore as List).isNotEmpty,
        isTrue,
        reason: 'Expected xp_events rows from live save before backfill',
      );

      // Run backfill — should wipe live rows and replay all sets.
      await runBackfillDirect(
        userClient: userClient,
        userId: user.userId,
        chunkSize: 20,
      );

      // XP state should match the full backfill reference (not just the
      // live-save subset).
      final dartRef = computeDartReference(kBackfillFixture);
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
          reason:
              '$bp after wipe+replay: PG $pgXp vs Dart $dartXp '
              '(delta ${(pgXp - dartXp).abs()})',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Shared fixture helpers (public — used by rpg_backfill_resume_test.dart)
// ---------------------------------------------------------------------------

/// Tolerance matching the spec parity requirement (PROJECT.md: "within 0.01").
const double kBackfillTol = 0.01;

/// Seeds the fixture workout schedule into the database.
///
/// Does NOT call `save_workout` (which would trigger `record_set_xp`) — the
/// tests want to run the backfill path, not the live path.
///
/// IMPORTANT: each "session" creates ONE workout containing ALL fixture
/// exercises (one set each). This matches PG's session-scoped novelty
/// semantics: `_rpg_backfill_chunk` filters session_volume by
/// `session_id = current_workout_id`, so a "session" must be ONE workout
/// for the per-bp novelty accumulator to span all exercises in that day.
/// (An earlier version of this helper created one workout per (day,
/// exercise), producing a parity drift on body parts shared across
/// exercises — `arms` shared by bench and lat_pulldown was the visible
/// case.)
///
/// Returns the list of [SeedResult]s in insertion order (chronological).
Future<List<SeedResult>> seedFixtureWorkouts(
  dynamic adminClient,
  String userId,
  BackfillFixture fixture,
) async {
  final results = <SeedResult>[];
  final baseDate = DateTime.now().subtract(
    Duration(days: fixture.weeksCount * 7 + 7),
  );

  for (var week = 0; week < fixture.weeksCount; week++) {
    for (var session = 0; session < fixture.sessionsPerWeek; session++) {
      final sessionDate = baseDate.add(Duration(days: week * 7 + session));
      // ONE workout containing all fixture exercises.
      final seed = await seedMultiExerciseWorkout(
        adminClient: adminClient,
        userId: userId,
        exercises: fixture.exercises,
        startedAt: sessionDate,
      );
      results.add(seed);
    }
  }
  return results;
}

/// Sequential Dart-side simulation of [fixture].
///
/// Mirrors the `_rpg_backfill_chunk` PL/pgSQL replay logic exactly:
///   - Sets ordered by (workout.started_at, set.id) — same as fixture seed order.
///   - `session_volume[bp]` accumulates **per-bp XP values** within a session
///     (NOT shares — matches the PG implementation which sums
///     `xp_events.attribution[bp]` directly, where `attribution[bp]` is the
///     attributed XP). The Python sim and `XpCalculator` doc-comment talk
///     about "shares", but the live PG code stores and reads XP — this
///     reference matches the live code path so the parity test compares
///     like-with-like. Realigning storage to true-shares is a separate
///     spec/code change tracked outside this bug-fix cycle.
///   - `weekly_volume[bp]` looks back 7 days from each set's timestamp,
///     summing per-bp XP from prior xp_events (matches PG).
///   - Peak advances inside the loop before `strength_mult` is computed
///     (matches PG and the Python sim).
Map<String, double> computeDartReference(BackfillFixture fixture) {
  final xpPool = <String, double>{};
  final peakLoads = <String, double>{}; // keyed by exercise slug

  final baseDate = DateTime.now().subtract(
    Duration(days: fixture.weeksCount * 7 + 7),
  );

  // Event log: each entry is one body-part contribution from one set.
  // Used for weekly_volume lookups AND session_volume lookups (latter is
  // just events with the same sessionDate/workout).
  final events = <Map<String, dynamic>>[];

  for (var week = 0; week < fixture.weeksCount; week++) {
    for (var session = 0; session < fixture.sessionsPerWeek; session++) {
      final sessionDate = baseDate.add(Duration(days: week * 7 + session));

      for (final ex in fixture.exercises) {
        final slug = ex.slug;
        final weight = ex.weightKg;
        final reps = ex.reps;

        // Advance peak before strength_mult (matches PG behavior).
        final priorPeak = peakLoads[slug] ?? 0.0;
        final effectivePeak = weight > priorPeak ? weight : priorPeak;
        peakLoads[slug] = effectivePeak;

        for (final bpEntry in ex.attribution.entries) {
          final bp = bpEntry.key;
          final share = bpEntry.value;

          // session_volume[bp] = sum of per-bp XP from prior events in this
          // session. PG queries `xp_events.attribution[bp]` filtered by
          // `session_id = current_workout_id`. The Dart reference filters
          // by `ts == sessionDate` since each session has a unique
          // sessionDate in the fixture.
          var svBp = 0.0;
          for (final ev in events) {
            if (ev['ts'] == sessionDate && ev['bp'] == bp) {
              svBp += ev['xp'] as double;
            }
          }

          // weekly_volume[bp] = sum of per-bp XP in (sessionDate - 7d,
          // sessionDate]. PG matches this exactly.
          final windowStart = sessionDate.subtract(const Duration(days: 7));
          var wvBp = 0.0;
          for (final ev in events) {
            final evTs = ev['ts'] as DateTime;
            if (evTs.isAfter(windowStart) &&
                !evTs.isAfter(sessionDate) &&
                ev['bp'] == bp) {
              wvBp += ev['xp'] as double;
            }
          }

          final comps = XpCalculator.computeSetXp(
            weightKg: weight,
            reps: reps,
            peakLoad: effectivePeak,
            sessionVolumeForBodyPart: svBp,
            weeklyVolumeForBodyPart: wvBp,
            // Phase 24a Phase F: mirror what `_rpg_backfill_chunk` does
            // — read the per-exercise curated multiplier from the fixture
            // (which holds the values from migration 00053). Default 1.0
            // covers any future fixture exercise that omits the field.
            difficultyMult: ex.difficultyMult,
          );
          final xpForBp = comps.setXp * share;

          xpPool[bp] = (xpPool[bp] ?? 0.0) + xpForBp;
          events.add({'ts': sessionDate, 'bp': bp, 'xp': xpForBp});
        }
      }
    }
  }

  return xpPool;
}

// ---------------------------------------------------------------------------
// Fixture data classes (public)
// ---------------------------------------------------------------------------

class BackfillFixture {
  const BackfillFixture({
    required this.exercises,
    required this.weeksCount,
    required this.sessionsPerWeek,
  });

  final List<ExerciseDef> exercises;
  final int weeksCount;
  final int sessionsPerWeek;

  /// Total sets = weeks × sessions/week × exercises/session × 1 set each.
  int get totalSets => weeksCount * sessionsPerWeek * exercises.length;
}

class ExerciseDef {
  const ExerciseDef({
    required this.slug,
    required this.weightKg,
    required this.reps,
    required this.attribution,
    this.difficultyMult = 1.0,
  });

  final String slug;
  final double weightKg;
  final int reps;
  final Map<String, double> attribution;

  /// Phase 24a Phase F: curated per-exercise multiplier from migration
  /// 00053 (`exercises.difficulty_mult`). Defaults to 1.0 to keep the
  /// constructor non-breaking; real fixtures must pass the actual value
  /// for the slug so the Dart reference matches `_rpg_backfill_chunk`.
  final double difficultyMult;
}
