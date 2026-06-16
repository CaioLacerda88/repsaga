/// Integration tests for Phase 38c cardio earning (migration 00079 —
/// `record_cardio_session` wired into `save_workout`).
///
/// Requires local Supabase running: `npx supabase start` + `npx supabase db
/// reset` (so 00079 is applied).
///
/// Contract under test (behavior, not wiring — every assertion pins a live DB
/// value):
///
///   1. **SQL ↔ Dart parity** — a finished workout carrying a cardio entry
///      writes `body_part_progress['cardio'].total_xp` equal to the Dart
///      `CardioXpCalculator.computeSessionXp(...)` value within 0.01 (the
///      live row rounds per-bp XP to 4 dp before persisting).
///   2. **Re-save idempotency (BUG-RPG-001)** — saving the same workout twice
///      does NOT double the cardio XP. The reversal reverts the cardio
///      attribution; record_cardio_session re-adds from scratch.
///   3. **Cardio is invisible to character level** — a cardio-only workout
///      leaves `character_state.character_level` at 1 (cardio is NOT an active
///      body part; that's Phase 38d).
///   4. **est-VO₂max writeback** — a run WITH distance updates
///      `profiles.cardio_vo2max` to the pace-derived rolling best-of.
///
/// Run: flutter test --tags integration test/integration/cardio_earning_parity_test.dart
@Tags(['integration'])
library;

// Same dynamic-client pattern as the sibling RPG integration tests.
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/cardio_xp_calculator.dart';
import 'package:repsaga/features/rpg/domain/est_vo2max.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:uuid/uuid.dart';

import 'rpg_integration_setup.dart';

const _uuid = Uuid();

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;
  final usersToDelete = <String>[];

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('cardio-earn-$runId-$idx@test.local');
    usersToDelete.add(u.userId);
    return u;
  }

  tearDown(() async {
    for (final id in usersToDelete) {
      await deleteTestUser(id);
    }
    usersToDelete.clear();
  });

  group('record_cardio_session — SQL ↔ Dart parity', () {
    test('duration-only treadmill entry: cardio body_part_progress matches '
        'CardioXpCalculator within 0.01', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      // Cold-start: profile has no DOB, no gender, no cardio_vo2max.
      // → age 35 (fallback), male table, seed = M:30 p25 = 35.9.
      final seeded = await _seedActiveCardioWorkout(
        adminClient: adminClient,
        userId: user.userId,
      );
      final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');

      const durationSeconds = 1800; // 30 min, duration-only (no distance)
      await client.rpc(
        'save_workout',
        params: {
          'p_workout': seeded.workoutJson,
          'p_exercises': <Map<String, dynamic>>[],
          'p_sets': <Map<String, dynamic>>[],
          'p_cardio': [
            {
              'id': _uuid.v4(),
              'workout_id': seeded.workoutId,
              'exercise_id': treadmillId,
              'duration_seconds': durationSeconds,
              'distance_m': null,
              'rpe': null,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        },
      );

      // Reconstruct the exact inputs the SQL used.
      final seedVo2 = EstVo2max.nonexerciseSeedVo2(age: 35, female: false);
      final absMet = EstVo2max.sessionMetFromCardioLog(
        modality: 'treadmill',
        distanceM: null,
        durationS: durationSeconds.toDouble(),
      );
      final expected = CardioXpCalculator.computeSessionXp(
        vo2max: seedVo2,
        age: 35,
        female: false,
        modality: 'treadmill',
        durationMin: durationSeconds / 60.0,
        kind: 'abs',
        value: absMet,
        currentRank: 1,
      );

      final cardio = await client
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'cardio')
          .maybeSingle();
      expect(
        cardio,
        isNotNull,
        reason: 'a cardio entry must write body_part_progress[cardio]',
      );
      final liveXp = ((cardio as Map<String, dynamic>)['total_xp'] as num)
          .toDouble();
      expect(
        liveXp,
        closeTo(expected.sessionXp, 0.01),
        reason:
            'live cardio XP ($liveXp) must match the Dart calculator '
            '(${expected.sessionXp}) within 0.01',
      );
      expect(liveXp, greaterThan(0));
    });

    test('cardio XP does NOT change character level (stays out of '
        'character_state — Phase 38d gate)', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      final seeded = await _seedActiveCardioWorkout(
        adminClient: adminClient,
        userId: user.userId,
      );
      final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');

      await client.rpc(
        'save_workout',
        params: {
          'p_workout': seeded.workoutJson,
          'p_exercises': <Map<String, dynamic>>[],
          'p_sets': <Map<String, dynamic>>[],
          'p_cardio': [
            {
              'id': _uuid.v4(),
              'workout_id': seeded.workoutId,
              'exercise_id': treadmillId,
              'duration_seconds': 2400,
              'distance_m': null,
              'rpe': null,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        },
      );

      // The cardio row earned XP...
      final cardio = await client
          .from('body_part_progress')
          .select('total_xp, rank')
          .eq('body_part', 'cardio')
          .single();
      expect(((cardio as Map)['total_xp'] as num).toDouble(), greaterThan(0));

      // ...but character_state ignores it entirely (no active strength parts).
      final cs = await client
          .from('character_state')
          .select('character_level')
          .maybeSingle();
      // The view GROUPs by user over the 6 strength parts only; with none
      // present, the user has no character_state row → level is the floor.
      final level = cs == null ? 1 : (cs['character_level'] as num).toInt();
      expect(
        level,
        1,
        reason:
            'cardio XP must NOT lift character level until Phase 38d flips '
            'cardio into the active set',
      );
    });

    test('re-saving the same workout converges (cardio XP not doubled — '
        'reversal pin)', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      final seeded = await _seedActiveCardioWorkout(
        adminClient: adminClient,
        userId: user.userId,
      );
      final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');
      final cardioId = _uuid.v4();

      Future<void> save() => client.rpc(
        'save_workout',
        params: {
          'p_workout': seeded.workoutJson,
          'p_exercises': <Map<String, dynamic>>[],
          'p_sets': <Map<String, dynamic>>[],
          'p_cardio': [
            {
              'id': cardioId,
              'workout_id': seeded.workoutId,
              'exercise_id': treadmillId,
              'duration_seconds': 1800,
              'distance_m': null,
              'rpe': null,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        },
      );

      await save();
      final afterFirst = await client
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'cardio')
          .single();
      final xp1 = ((afterFirst as Map)['total_xp'] as num).toDouble();

      await save(); // offline retry / re-save
      final afterSecond = await client
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'cardio')
          .single();
      final xp2 = ((afterSecond as Map)['total_xp'] as num).toDouble();

      expect(
        xp2,
        closeTo(xp1, 0.01),
        reason: 'cardio XP must converge on re-save, not double ($xp1 → $xp2)',
      );

      // Exactly one cardio xp_events row survives the re-save.
      final events = await client
          .from('xp_events')
          .select('id')
          .eq('session_id', seeded.workoutId)
          .eq('event_type', 'cardio_session');
      expect(events as List, hasLength(1));
    });

    test(
      'run WITH distance writes back a pace-derived profiles.cardio_vo2max',
      () async {
        final adminClient = serviceRoleClient();
        final user = await freshUser();
        final client = authenticatedClient(user);

        final seeded = await _seedActiveCardioWorkout(
          adminClient: adminClient,
          userId: user.userId,
        );
        // treadmill is a DISTANCE_MODALITY → best-effort fires.
        final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');

        const durationSeconds = 1800;
        const distanceM = 5000.0; // 30-min 5k → ~41.9 (the §A worked example)
        await client.rpc(
          'save_workout',
          params: {
            'p_workout': seeded.workoutJson,
            'p_exercises': <Map<String, dynamic>>[],
            'p_sets': <Map<String, dynamic>>[],
            'p_cardio': [
              {
                'id': _uuid.v4(),
                'workout_id': seeded.workoutId,
                'exercise_id': treadmillId,
                'duration_seconds': durationSeconds,
                'distance_m': distanceM,
                'rpe': null,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          },
        );

        final expectedVo2 = EstVo2max.bestEffortVo2FromPace(
          distanceM: distanceM,
          durationS: durationSeconds.toDouble(),
          modality: 'treadmill',
        );
        expect(expectedVo2, isNotNull);

        final profile = await client
            .from('profiles')
            .select('cardio_vo2max')
            .eq('id', user.userId)
            .single();
        final liveVo2 = ((profile as Map)['cardio_vo2max'] as num).toDouble();
        // Profile column is numeric(4,1) → rounds to 1 dp.
        expect(
          liveVo2,
          closeTo(expectedVo2!, 0.05),
          reason:
              'cardio_vo2max must be the pace-derived rolling best-of '
              '($expectedVo2)',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SeededWorkout {
  const _SeededWorkout({required this.workoutId, required this.workoutJson});
  final String workoutId;
  final Map<String, dynamic> workoutJson;
}

/// Seeds an ACTIVE workout row (no strength exercises — cardio-only) so the
/// cardio earning path is isolated from strength XP.
Future<_SeededWorkout> _seedActiveCardioWorkout({
  required supabase.SupabaseClient adminClient,
  required String userId,
}) async {
  final ts = DateTime.now().toUtc();
  final workoutRow = await adminClient
      .from('workouts')
      .insert({
        'user_id': userId,
        'name': 'Cardio Earning Integration Workout',
        'started_at': ts.toIso8601String(),
        'is_active': true,
      })
      .select('id')
      .single();
  final workoutId = workoutRow['id'] as String;

  return _SeededWorkout(
    workoutId: workoutId,
    workoutJson: {
      'id': workoutId,
      'user_id': userId,
      'name': 'Cardio Earning Integration Workout',
      'finished_at': ts.add(const Duration(minutes: 30)).toIso8601String(),
      'duration_seconds': 1800,
      'notes': null,
      'routine_id': null,
    },
  );
}
