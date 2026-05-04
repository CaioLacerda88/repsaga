/// Integration tests for the bodyweight-workout regression fixed in
/// `00050_save_workout_skip_zero_weight_peak.sql`.
///
/// Background — production crash on Galaxy S25 Ultra (May 2026):
/// queued workouts containing only bodyweight sets ("Full Body Beginner",
/// "5x5 Strength" — both included Plank/Push-Up/Pull-Up at weight = 0)
/// failed `save_workout` with
///
///     PostgrestException code=23514:
///       new row for relation "exercise_peak_loads" violates check
///       constraint "exercise_peak_loads_peak_weight_check"
///
/// Root cause: `record_session_xp_batch` Step 7 aggregated peak weight from
/// every working-completed set without filtering `weight > 0`. When all sets
/// for an exercise had `weight = 0`, the per-exercise CTE produced a row
/// with `peak_weight = 0`, the bulk INSERT into `exercise_peak_loads` fired,
/// and the column's `CHECK (peak_weight > 0)` rolled the entire transaction
/// back. Net effect: the workout never persisted server-side.
///
/// Fix: 00050 adds `AND s.weight > 0` to the per_set CTE inside Step 7 so
/// bodyweight exercises do not construct an `exercise_peak_loads` row at all.
/// `xp_events` and `body_part_progress` (Steps 5 and 6) continue to apply —
/// bodyweight workouts still earn XP through the per-set inserts.
///
/// What these tests validate:
///
/// 1. Bodyweight-only workout commits — no `exercise_peak_loads` row, but
///    `xp_events` rows ARE created and `body_part_progress.total_xp` advances.
/// 2. Mixed (weighted + bodyweight) workout commits — weighted exercise gets
///    a peak_loads row, bodyweight one does not, both contribute XP.
///
/// Requires local Supabase running: `npx supabase start`
/// Run: flutter test --tags integration test/integration/save_workout_zero_weight_test.dart
@Tags(['integration'])
library;

// Helpers below construct raw RPC payloads; we use `dynamic` for the Supabase
// client surface to avoid leaking the admin/user client distinction into the
// typed API. Production code keeps `avoid_dynamic_calls` on everywhere else.
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';

import 'rpg_integration_setup.dart';

void main() {
  // Unique suffix per test run to avoid email conflicts on reruns.
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;

  TestUser? currentUser;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('save-zero-$runId-$idx@test.local');
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
  // Bodyweight-only workout: every set has weight = 0.
  //
  // Pre-fix: save_workout threw `exercise_peak_loads_peak_weight_check`.
  // Post-fix: save_workout commits, NO exercise_peak_loads row exists for the
  // bodyweight exercise, xp_events rows ARE present, and body_part_progress
  // for the targeted body part advanced.
  // ---------------------------------------------------------------------------
  test(
    'bodyweight-only workout (Plank, all sets weight=0) commits and earns XP '
    'without writing exercise_peak_loads',
    () async {
      const slug = 'plank';
      const weight = 0.0;
      const reps = 60;
      const numSets = 3;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: weight,
        reps: reps,
        numSets: numSets,
      );

      // Pre-fix this RPC threw; post-fix it returns successfully.
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed,
        userId: user.userId,
        weightKg: weight,
        reps: reps,
        numSets: numSets,
      );

      // Assertion 1: NO exercise_peak_loads row was written. The fix's
      // contract is "bodyweight exercises do not record a peak"; if a row
      // appeared anyway, the per_set CTE filter regressed.
      final peakLoads = await userClient
          .from('exercise_peak_loads')
          .select('exercise_id, peak_weight')
          .eq('user_id', user.userId)
          .eq('exercise_id', seed.exerciseId);
      expect(
        peakLoads as List,
        isEmpty,
        reason:
            'exercise_peak_loads must have NO row for a bodyweight-only '
            'exercise — found: $peakLoads',
      );

      // Assertion 2: xp_events rows ARE present. Bodyweight workouts still
      // earn XP through the per-set inserts (Steps 4 + 5). One row per set.
      final events = await userClient
          .from('xp_events')
          .select('id, set_id, total_xp')
          .eq('user_id', user.userId)
          .eq('session_id', seed.workoutId);
      expect(
        events as List,
        hasLength(numSets),
        reason: 'expected one xp_events row per completed set',
      );
      // Every event must have positive total_xp (intensity_mult * base_xp,
      // with strength_mult defaulting to 1.0 when peak is 0/NULL).
      for (final row in events) {
        expect(
          (row['total_xp'] as num).toDouble(),
          greaterThan(0),
          reason: 'xp_events.total_xp must be > 0 for bodyweight sets',
        );
      }

      // Assertion 3: body_part_progress advanced for the exercise's primary
      // muscle. Plank attribution is core-dominant (per 00040 seed data) so
      // we expect the 'core' row to exist with total_xp > 0.
      final bpProgress = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp')
          .eq('user_id', user.userId)
          .gt('total_xp', 0);
      expect(
        bpProgress as List,
        isNotEmpty,
        reason:
            'body_part_progress must have at least one positive row after a '
            'bodyweight workout commits',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Mixed workout: one weighted exercise + one bodyweight exercise in the
  // same RPC call. Both must commit. The weighted exercise gets an
  // exercise_peak_loads row; the bodyweight one does not.
  //
  // This pins that the per_set CTE filter (`AND s.weight > 0`) only excludes
  // the zero-weight rows from the per_exercise aggregator — it does NOT
  // skip OTHER exercises in the same workout that have legitimate peaks.
  // ---------------------------------------------------------------------------
  test('mixed workout (weighted Squat + bodyweight Plank) commits; only the '
      'weighted exercise gets an exercise_peak_loads row', () async {
    const weightedSlug = 'barbell_squat';
    const bodyweightSlug = 'plank';
    const weightedKg = 100.0;
    const weightedReps = 5;
    const bodyweightReps = 60;

    final user = await freshUser();
    final adminClient = serviceRoleClient();
    final userClient = authenticatedClient(user);

    // Resolve both exercise IDs.
    final weightedExId = await exerciseIdForSlug(adminClient, weightedSlug);
    final bodyweightExId = await exerciseIdForSlug(adminClient, bodyweightSlug);

    // Build the workout directly so a single RPC call carries BOTH
    // exercises. seedWorkout/saveWorkoutRpc are single-exercise helpers.
    final ts = DateTime.now().toUtc();
    final workoutId = _uuid();
    final weId1 = _uuid();
    final weId2 = _uuid();
    final setIdSquat = _uuid();
    final setIdPlank = _uuid();

    // Pre-insert the parent rows so save_workout can resolve them. The
    // save_workout RPC accepts the JSON shape but expects FK targets to
    // exist (see saveWorkoutRpc for the shape it produces).
    await adminClient.from('workouts').insert({
      'id': workoutId,
      'user_id': user.userId,
      'name': 'Mixed Test',
      'started_at': ts.toIso8601String(),
      'finished_at': ts.add(const Duration(hours: 1)).toIso8601String(),
      'is_active': false,
    });
    await adminClient.from('workout_exercises').insert([
      {
        'id': weId1,
        'workout_id': workoutId,
        'exercise_id': weightedExId,
        'order': 1,
      },
      {
        'id': weId2,
        'workout_id': workoutId,
        'exercise_id': bodyweightExId,
        'order': 2,
      },
    ]);
    await adminClient.from('sets').insert([
      {
        'id': setIdSquat,
        'workout_exercise_id': weId1,
        'set_number': 1,
        'reps': weightedReps,
        'weight': weightedKg,
        'is_completed': true,
        'set_type': 'working',
      },
      {
        'id': setIdPlank,
        'workout_exercise_id': weId2,
        'set_number': 1,
        'reps': bodyweightReps,
        'weight': 0.0,
        'is_completed': true,
        'set_type': 'working',
      },
    ]);

    // Build save_workout RPC payload covering both exercises.
    final workoutJson = {
      'id': workoutId,
      'user_id': user.userId,
      'name': 'Mixed Test',
      'finished_at': ts.toIso8601String(),
      'duration_seconds': 3600,
      'notes': null,
    };
    final exercisesJson = [
      {
        'id': weId1,
        'workout_id': workoutId,
        'exercise_id': weightedExId,
        'order': 1,
        'rest_seconds': null,
      },
      {
        'id': weId2,
        'workout_id': workoutId,
        'exercise_id': bodyweightExId,
        'order': 2,
        'rest_seconds': null,
      },
    ];
    final setsJson = [
      {
        'id': setIdSquat,
        'workout_exercise_id': weId1,
        'set_number': 1,
        'reps': weightedReps,
        'weight': weightedKg,
        'rpe': null,
        'set_type': 'working',
        'notes': null,
        'is_completed': true,
      },
      {
        'id': setIdPlank,
        'workout_exercise_id': weId2,
        'set_number': 1,
        'reps': bodyweightReps,
        'weight': 0.0,
        'rpe': null,
        'set_type': 'working',
        'notes': null,
        'is_completed': true,
      },
    ];

    // Pre-fix this would have rolled the txn back on the bodyweight
    // exercise's CHECK violation, taking the squat write down with it.
    await userClient.rpc(
      'save_workout',
      params: {
        'p_workout': workoutJson,
        'p_exercises': exercisesJson,
        'p_sets': setsJson,
      },
    );

    // Assertion 1: weighted exercise has a peak row at exactly the lifted
    // load. The per_set CTE filter must NOT exclude positive-weight rows.
    final squatPeak = await userClient
        .from('exercise_peak_loads')
        .select('peak_weight, peak_reps')
        .eq('user_id', user.userId)
        .eq('exercise_id', weightedExId)
        .single();
    expect((squatPeak['peak_weight'] as num).toDouble(), weightedKg);
    expect((squatPeak['peak_reps'] as num).toInt(), weightedReps);

    // Assertion 2: bodyweight exercise has NO peak row.
    final plankPeak = await userClient
        .from('exercise_peak_loads')
        .select('peak_weight')
        .eq('user_id', user.userId)
        .eq('exercise_id', bodyweightExId);
    expect(
      plankPeak as List,
      isEmpty,
      reason:
          'exercise_peak_loads must have NO row for the bodyweight '
          'exercise even when other exercises in the same workout have '
          'legitimate peaks',
    );

    // Assertion 3: BOTH sets produced xp_events. The weighted set and the
    // bodyweight set each get a row.
    final events = await userClient
        .from('xp_events')
        .select('set_id, total_xp')
        .eq('user_id', user.userId)
        .eq('session_id', workoutId);
    expect(events as List, hasLength(2));
    final eventSetIds = {for (final row in events) row['set_id'] as String};
    expect(eventSetIds, containsAll([setIdSquat, setIdPlank]));
  });
}

// ---------------------------------------------------------------------------
// Local UUID generator (mirrors rpg_integration_setup but kept private so
// this test file can construct multi-exercise rows inline without coupling
// to the shared single-exercise helpers).
// ---------------------------------------------------------------------------

int _uuidCounter = 0;

String _uuid() {
  _uuidCounter++;
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
  final b = List<int>.filled(16, 0);
  b[0] = (ts >> 40) & 0xff;
  b[1] = (ts >> 32) & 0xff;
  b[2] = (ts >> 24) & 0xff;
  b[3] = (ts >> 16) & 0xff;
  b[4] = (ts >> 8) & 0xff;
  b[5] = ts & 0xff;
  b[6] = 0x40 | ((_uuidCounter >> 8) & 0x0f);
  b[7] = _uuidCounter & 0xff;
  b[8] = 0x80 | ((_uuidCounter >> 16) & 0x3f);
  b[9] = (_uuidCounter >> 24) & 0xff;
  // bytes 10-15 stay 0 — fine for an integration-test single-process unique
  // id; collisions only matter across parallel runs which we never do here.
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).toList();
  return '${hex.sublist(0, 4).join()}-'
      '${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-'
      '${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10, 16).join()}';
}
