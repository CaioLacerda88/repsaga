/// Integration tests for the cardio save gate (migration 00077).
///
/// Requires local Supabase running: `npx supabase start`
///
/// Contract under test (docs/cardio-stat-plan.md §1 / §2.6 — the latent
/// cardio mis-attribution bug):
///
/// A completed cardio set (exercise with `muscle_group='cardio'` and
/// `xp_attribution={"cardio":1.0}`) must be CLEANLY IGNORED by every
/// strength-XP writer, pre-feature:
///
///   * ZERO `body_part_progress` rows with `body_part='cardio'`
///   * ZERO `xp_events` rows for the cardio set
///   * ZERO strength peak bookkeeping for the cardio exercise (the
///     weighted-sled case — the "running logged with reps farms a
///     strength rank" vector, sealed structurally)
///
/// AND a strength set saved through the same path is unaffected — it
/// earns exactly the same XP it would earn in a workout with no cardio
/// sets at all (control-user equality).
///
/// All three writers are covered: `record_session_xp_batch` (via
/// save_workout, the hot path), `record_set_xp` (per-set diagnostic),
/// and `_rpg_backfill_chunk` (historical replay via backfill_rpg_v1).
/// Cluster: check-violation-needs-writer-audit.
///
/// Run: flutter test --tags integration test/integration/rpg_cardio_save_gate_test.dart
@Tags(['integration'])
library;

// Same dynamic-client pattern as the sibling RPG integration tests — see
// rpg_record_set_xp_test.dart for the rationale.
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'rpg_integration_setup.dart';

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;

  // Track every user created in a test so tearDown can delete all of them
  // (the control-user test creates two).
  final usersToDelete = <String>[];

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('rpg-cardio-gate-$runId-$idx@test.local');
    usersToDelete.add(u.userId);
    return u;
  }

  tearDown(() async {
    for (final id in usersToDelete) {
      await deleteTestUser(id);
    }
    usersToDelete.clear();
  });

  group('cardio save gate — record_session_xp_batch (save_workout path)', () {
    test('completed cardio sets (weight=0 treadmill AND weighted sled) produce '
        'no cardio body_part_progress, no cardio xp_events, no strength peak '
        'rows; the strength set in the same workout earns exactly what a '
        'cardio-free workout earns', () async {
      final adminClient = serviceRoleClient();

      // --- User A: mixed workout (bench + treadmill + weighted sled). ---
      final userA = await freshUser();
      final clientA = authenticatedClient(userA);
      final mixed = await _seedWorkout(
        adminClient: adminClient,
        userId: userA.userId,
        exercises: const [
          _Ex(slug: 'barbell_bench_press', weight: 60.0, reps: 8),
          // The exact latent-bug shape: cardio with weight=0, reps>=1
          // passes the reps gate pre-00077.
          _Ex(slug: 'treadmill', weight: 0.0, reps: 10),
          // The farming vector: cardio WITH real weight — pre-00077 this
          // would also write strength peak rows.
          _Ex(slug: 'sled_push', weight: 40.0, reps: 10),
        ],
      );
      await _saveWorkoutRpc(
        userClient: clientA,
        userId: userA.userId,
        seeded: mixed,
      );

      // 1. ZERO body_part_progress rows for cardio.
      final cardioBpp = await clientA
          .from('body_part_progress')
          .select('body_part, total_xp')
          .eq('body_part', 'cardio');
      expect(
        cardioBpp as List,
        isEmpty,
        reason:
            'A completed cardio set must NOT write a body_part_progress '
            'row for cardio (latent mis-attribution bug, migration 00077). '
            'Got: $cardioBpp',
      );

      // 2. ZERO xp_events for the cardio sets; exactly ONE for the
      //    session (the bench set).
      final treadmillSetId = mixed.exercises[1].setId;
      final sledSetId = mixed.exercises[2].setId;
      final cardioEvents = await clientA
          .from('xp_events')
          .select('id, set_id')
          .inFilter('set_id', [treadmillSetId, sledSetId]);
      expect(
        cardioEvents as List,
        isEmpty,
        reason:
            'Cardio sets must produce NO xp_events rows — not even '
            'zero-XP ones. Got: $cardioEvents',
      );
      final sessionEvents = await clientA
          .from('xp_events')
          .select('id, set_id, total_xp')
          .eq('session_id', mixed.workoutId);
      expect(
        sessionEvents as List,
        hasLength(1),
        reason:
            'Only the bench set may produce an xp_events row. '
            'Got: $sessionEvents',
      );
      expect(
        sessionEvents.first['set_id'],
        equals(mixed.exercises[0].setId),
        reason: 'The single xp_events row must belong to the bench set.',
      );

      // 3. ZERO strength peak bookkeeping for the weighted cardio set.
      final sledPeaks = await clientA
          .from('exercise_peak_loads')
          .select('peak_weight')
          .eq('exercise_id', mixed.exercises[2].exerciseId);
      expect(
        sledPeaks as List,
        isEmpty,
        reason:
            'A weighted cardio set (sled_push 40kg) must not write '
            'exercise_peak_loads — strength peak tracking is part of the '
            'weight×reps machinery the gate excludes.',
      );
      final sledBandPeaks = await clientA
          .from('exercise_peak_loads_by_rep_range')
          .select('best_weight')
          .eq('exercise_slug', 'sled_push');
      expect(
        sledBandPeaks as List,
        isEmpty,
        reason:
            'A weighted cardio set must not write '
            'exercise_peak_loads_by_rep_range either.',
      );

      // 4. Strength regression guard — control-user equality. User B
      //    saves an identical workout WITHOUT the cardio sets. Both
      //    users are fresh (no history), so every multiplier in the
      //    chain resolves identically; the strength XP must match
      //    exactly (within the batch RPC's 4-decimal rounding).
      final userB = await freshUser();
      final clientB = authenticatedClient(userB);
      final control = await _seedWorkout(
        adminClient: adminClient,
        userId: userB.userId,
        exercises: const [
          _Ex(slug: 'barbell_bench_press', weight: 60.0, reps: 8),
        ],
      );
      await _saveWorkoutRpc(
        userClient: clientB,
        userId: userB.userId,
        seeded: control,
      );

      // Bench attribution: chest 0.70 / shoulders 0.20 / arms 0.10.
      for (final bp in ['chest', 'shoulders', 'arms']) {
        final a = await _readBodyPartXp(clientA, bp);
        final b = await _readBodyPartXp(clientB, bp);
        expect(
          a,
          greaterThan(0),
          reason: 'Bench must still earn $bp XP with the gate in place.',
        );
        expect(
          (a - b).abs(),
          lessThanOrEqualTo(_kTol),
          reason:
              'Strength XP must be IDENTICAL whether or not cardio sets '
              'were in the workout. $bp: with-cardio=$a control=$b '
              '(delta ${(a - b).abs()}). A nonzero delta means cardio '
              'sets leaked into the novelty/weekly accumulation.',
        );
      }
    });
  });

  group('cardio save gate — record_set_xp (per-set diagnostic path)', () {
    test(
      'record_set_xp on a completed cardio set returns no rows and writes '
      'nothing; on the strength set of the same workout it still earns',
      () async {
        final adminClient = serviceRoleClient();
        final user = await freshUser();
        final userClient = authenticatedClient(user);

        final seeded = await _seedWorkout(
          adminClient: adminClient,
          userId: user.userId,
          exercises: const [
            _Ex(slug: 'treadmill', weight: 0.0, reps: 15),
            _Ex(slug: 'barbell_bench_press', weight: 60.0, reps: 8),
          ],
        );

        // Cardio set: the RPC must early-return — no result rows, no
        // xp_events, no body_part_progress.
        final cardioResult = await userClient.rpc(
          'record_set_xp',
          params: {'p_set_id': seeded.exercises[0].setId},
        );
        expect(
          cardioResult as List,
          isEmpty,
          reason:
              'record_set_xp must return zero result rows for a cardio set '
              '(same shape as the not-completed / reps gates).',
        );
        final cardioEvents = await userClient
            .from('xp_events')
            .select('id')
            .eq('set_id', seeded.exercises[0].setId);
        expect(cardioEvents as List, isEmpty);
        final cardioBpp = await userClient
            .from('body_part_progress')
            .select('body_part')
            .eq('body_part', 'cardio');
        expect(cardioBpp as List, isEmpty);

        // Strength set through the SAME entry point still earns.
        final strengthResult = await userClient.rpc(
          'record_set_xp',
          params: {'p_set_id': seeded.exercises[1].setId},
        );
        expect(
          strengthResult as List,
          isNotEmpty,
          reason: 'record_set_xp must still score strength sets.',
        );
        final chestXp = await _readBodyPartXp(userClient, 'chest');
        expect(
          chestXp,
          greaterThan(0),
          reason: 'Bench via record_set_xp must still earn chest XP.',
        );
      },
    );
  });

  group('cardio save gate — _rpg_backfill_chunk (historical replay path)', () {
    test(
      'backfill over a history containing cardio sets skips them: no cardio '
      'body_part_progress, no cardio xp_events, strength sets still scored',
      () async {
        final adminClient = serviceRoleClient();
        final user = await freshUser();
        final userClient = authenticatedClient(user);

        // Seed a FINISHED workout directly (no save_workout call — backfill
        // is the writer under test).
        final seeded = await _seedWorkout(
          adminClient: adminClient,
          userId: user.userId,
          exercises: const [
            _Ex(slug: 'barbell_bench_press', weight: 60.0, reps: 8),
            _Ex(slug: 'treadmill', weight: 0.0, reps: 10),
          ],
          startedAt: _threeDaysAgo,
        );

        await runBackfillDirect(userClient: userClient, userId: user.userId);

        final cardioBpp = await userClient
            .from('body_part_progress')
            .select('body_part')
            .eq('body_part', 'cardio');
        expect(
          cardioBpp as List,
          isEmpty,
          reason:
              'Backfill must not replay the cardio mis-attribution '
              '(cluster: check-violation-needs-writer-audit — the backfill '
              'is the third writer of the same invariant).',
        );
        final cardioEvents = await userClient
            .from('xp_events')
            .select('id')
            .eq('set_id', seeded.exercises[1].setId);
        expect(cardioEvents as List, isEmpty);

        // Strength regression: the bench set was scored.
        final benchEvents = await userClient
            .from('xp_events')
            .select('id, total_xp')
            .eq('set_id', seeded.exercises[0].setId);
        expect(benchEvents as List, hasLength(1));
        final chestXp = await _readBodyPartXp(userClient, 'chest');
        expect(
          chestXp,
          greaterThan(0),
          reason: 'Backfill must still score the strength set.',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Absolute XP tolerance — matches the sibling parity tests; the batch RPC
/// rounds per-bp XP to 4 decimals before persisting.
const double _kTol = 0.01;

DateTime get _threeDaysAgo =>
    DateTime.now().toUtc().subtract(const Duration(days: 3));

class _Ex {
  const _Ex({required this.slug, required this.weight, required this.reps});

  final String slug;
  final double weight;
  final int reps;
}

class _SeededExercise {
  const _SeededExercise({
    required this.workoutExerciseId,
    required this.exerciseId,
    required this.setId,
    required this.def,
  });

  final String workoutExerciseId;
  final String exerciseId;
  final String setId;
  final _Ex def;
}

class _SeededWorkout {
  const _SeededWorkout({required this.workoutId, required this.exercises});

  final String workoutId;
  final List<_SeededExercise> exercises;
}

/// Seeds a finished workout with one completed working set per exercise
/// definition. Inline variant of `seedMultiExerciseWorkout` that returns
/// ALL ids (the shared helper only returns the first exercise's ids, and
/// the save_workout payload below needs every row).
Future<_SeededWorkout> _seedWorkout({
  required supabase.SupabaseClient adminClient,
  required String userId,
  required List<_Ex> exercises,
  DateTime? startedAt,
}) async {
  final ts = (startedAt ?? DateTime.now()).toUtc();
  final workoutRow = await adminClient
      .from('workouts')
      .insert({
        'user_id': userId,
        'name': 'Cardio Gate Integration Workout',
        'started_at': ts.toIso8601String(),
        'finished_at': ts.add(const Duration(hours: 1)).toIso8601String(),
        'is_active': false,
      })
      .select('id')
      .single();
  final workoutId = workoutRow['id'] as String;

  final seeded = <_SeededExercise>[];
  for (var i = 0; i < exercises.length; i++) {
    final def = exercises[i];
    final exerciseId = await exerciseIdForSlug(adminClient, def.slug);
    final weRow = await adminClient
        .from('workout_exercises')
        .insert({
          'workout_id': workoutId,
          'exercise_id': exerciseId,
          'order': i + 1,
        })
        .select('id')
        .single();
    final weId = weRow['id'] as String;
    final setRow = await adminClient
        .from('sets')
        .insert({
          'workout_exercise_id': weId,
          'set_number': 1,
          'reps': def.reps,
          'weight': def.weight,
          'is_completed': true,
          'set_type': 'working',
        })
        .select('id')
        .single();
    seeded.add(
      _SeededExercise(
        workoutExerciseId: weId,
        exerciseId: exerciseId,
        setId: setRow['id'] as String,
        def: def,
      ),
    );
  }
  return _SeededWorkout(workoutId: workoutId, exercises: seeded);
}

/// Calls `save_workout` (which PERFORMs record_session_xp_batch) with the
/// full multi-exercise payload mirroring [seeded].
Future<void> _saveWorkoutRpc({
  required supabase.SupabaseClient userClient,
  required String userId,
  required _SeededWorkout seeded,
}) async {
  final ts = DateTime.now().toUtc();
  await userClient.rpc(
    'save_workout',
    params: {
      'p_workout': {
        'id': seeded.workoutId,
        'user_id': userId,
        'name': 'Cardio Gate Integration Workout',
        'finished_at': ts.toIso8601String(),
        'duration_seconds': 3600,
        'notes': null,
        'routine_id': null,
      },
      'p_exercises': [
        for (var i = 0; i < seeded.exercises.length; i++)
          {
            'id': seeded.exercises[i].workoutExerciseId,
            'workout_id': seeded.workoutId,
            'exercise_id': seeded.exercises[i].exerciseId,
            'order': i + 1,
            'rest_seconds': null,
          },
      ],
      'p_sets': [
        for (final ex in seeded.exercises)
          {
            'id': ex.setId,
            'workout_exercise_id': ex.workoutExerciseId,
            'set_number': 1,
            'reps': ex.def.reps,
            'weight': ex.def.weight,
            'rpe': null,
            'set_type': 'working',
            'notes': null,
            'is_completed': true,
          },
      ],
    },
  );
}

Future<double> _readBodyPartXp(dynamic userClient, String bodyPart) async {
  final row = await (userClient as dynamic)
      .from('body_part_progress')
      .select('total_xp')
      .eq('body_part', bodyPart)
      .maybeSingle();
  if (row == null) return 0.0;
  return ((row as Map<String, dynamic>)['total_xp'] as num).toDouble();
}
