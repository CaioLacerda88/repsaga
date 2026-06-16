/// Integration tests for the Phase 38b cardio persistence path
/// (migration 00078 — `cardio_sessions` table + `save_workout(p_cardio)`).
///
/// Requires local Supabase running: `npx supabase start`
///
/// Contract under test:
///
///   * A finished workout carrying a completed cardio entry writes EXACTLY
///     one `cardio_sessions` row with the raw inputs (duration / distance /
///     RPE).
///   * Phase 38c contract: the cardio *entry's* raw row persists, and cardio
///     XP now legitimately accrues — but via the STRENGTH-density cross-credit
///     (one `cardio_session` xp_events row, session_id = workout_id) derived
///     from the bench set, NOT from the treadmill entry. The bench STRENGTH
///     `set` xp_events row is unaffected. (Pre-38c this test asserted cardio
///     earned nothing; 38c's cross-credit intentionally fires for every
///     workout with completed working strength sets.)
///   * The strength set in the same mixed workout still earns normally.
///   * Re-saving the same workout converges (DELETE+INSERT keyed by
///     workout_id — no duplicate cardio rows).
///   * Backward compatibility: the legacy 3-argument `save_workout` call
///     shape (no `p_cardio`) still resolves — pre-38b clients and queued
///     offline payloads replay unchanged.
///   * RLS: another authenticated user cannot read the cardio row.
///
/// Run: flutter test --tags integration test/integration/cardio_save_roundtrip_test.dart
@Tags(['integration'])
library;

// Same dynamic-client pattern as the sibling RPG integration tests — see
// rpg_record_set_xp_test.dart for the rationale.
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
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
    final u = await createTestUser('cardio-roundtrip-$runId-$idx@test.local');
    usersToDelete.add(u.userId);
    return u;
  }

  tearDown(() async {
    for (final id in usersToDelete) {
      await deleteTestUser(id);
    }
    usersToDelete.clear();
  });

  group('save_workout p_cardio — persistence round-trip', () {
    test('mixed workout (bench + treadmill cardio entry): cardio_sessions row '
        'persists the raw inputs; strength still earns; cardio XP accrues via '
        'the strength-density cross-credit (not the treadmill entry)', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      final seeded = await _seedActiveWorkout(
        adminClient: adminClient,
        userId: user.userId,
      );
      final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');
      final cardioId = _uuid.v4();

      await client.rpc(
        'save_workout',
        params: {
          'p_workout': seeded.workoutJson,
          'p_exercises': seeded.exercisesJson,
          'p_sets': seeded.setsJson,
          'p_cardio': [
            {
              'id': cardioId,
              'workout_id': seeded.workoutId,
              'exercise_id': treadmillId,
              'duration_seconds': 1725,
              'distance_m': 5200.0,
              'rpe': 7,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
          ],
        },
      );

      // 1. Exactly one cardio row, raw inputs intact.
      final cardioRows = await client
          .from('cardio_sessions')
          .select('id, exercise_id, duration_seconds, distance_m, rpe')
          .eq('workout_id', seeded.workoutId);
      expect(cardioRows as List, hasLength(1));
      final row = cardioRows.single;
      expect(row['id'], cardioId);
      expect(row['exercise_id'], treadmillId);
      expect(row['duration_seconds'], 1725);
      expect((row['distance_m'] as num).toDouble(), 5200.0);
      expect(row['rpe'], 7);

      // 2. Phase 38c contract: cardio XP accrues via the strength-density
      //    cross-credit (NOT the treadmill entry). The cross-credit fires
      //    because the workout has a completed working bench set.
      final cardioBpp = await client
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'cardio')
          .maybeSingle();
      expect(
        cardioBpp,
        isNotNull,
        reason:
            'Phase 38c cross-credit: a workout with completed working '
            'strength sets writes a cardio body_part_progress row derived '
            'from work density.',
      );
      expect(
        ((cardioBpp as Map<String, dynamic>)['total_xp'] as num).toDouble(),
        greaterThan(0),
      );

      // The session has exactly TWO xp_events rows: the bench STRENGTH set
      // (event_type='set') + ONE cardio cross-credit row
      // (event_type='cardio_session', no set_id). The treadmill ENTRY produces
      // neither — it has no set, and the cross-credit is attributed to the
      // strength sets, not the cardio entry.
      final strengthSetEvents = await client
          .from('xp_events')
          .select('id, set_id')
          .eq('session_id', seeded.workoutId)
          .eq('event_type', 'set');
      expect(
        strengthSetEvents as List,
        hasLength(1),
        reason:
            'Only the bench set may produce a strength `set` xp_events row — '
            'the cardio entry has no set and writes no strength event.',
      );
      final cardioEvents = await client
          .from('xp_events')
          .select('id, set_id, session_id')
          .eq('session_id', seeded.workoutId)
          .eq('event_type', 'cardio_session');
      expect(
        cardioEvents as List,
        hasLength(1),
        reason:
            'Exactly one cardio_session xp_events row per workout (the '
            'cross-credit), session_id = workout_id, no set_id.',
      );
      expect(
        cardioEvents.single['set_id'],
        isNull,
        reason: 'the cardio cross-credit event carries no set_id',
      );

      // 3. The strength set still earned (bench: chest 0.70 dominant).
      final chest = await client
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'chest')
          .maybeSingle();
      expect(chest, isNotNull);
      expect(
        ((chest as Map<String, dynamic>)['total_xp'] as num).toDouble(),
        greaterThan(0),
      );

      // 4. RLS — a different authenticated user sees nothing.
      final intruder = await freshUser();
      final intruderClient = authenticatedClient(intruder);
      final foreignRows = await intruderClient
          .from('cardio_sessions')
          .select('id')
          .eq('workout_id', seeded.workoutId);
      expect(
        foreignRows as List,
        isEmpty,
        reason:
            'cardio_sessions RLS is owner-scoped through the parent '
            'workout — another user must read zero rows.',
      );
    });

    test('re-saving the same workout converges to ONE cardio row '
        '(DELETE+INSERT idempotency)', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      final seeded = await _seedActiveWorkout(
        adminClient: adminClient,
        userId: user.userId,
      );
      final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');

      Future<void> save({required int durationSeconds}) {
        return client.rpc(
          'save_workout',
          params: {
            'p_workout': seeded.workoutJson,
            'p_exercises': seeded.exercisesJson,
            'p_sets': seeded.setsJson,
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
      }

      await save(durationSeconds: 1800);
      await save(durationSeconds: 2400); // offline retry / re-save shape

      final rows = await client
          .from('cardio_sessions')
          .select('duration_seconds')
          .eq('workout_id', seeded.workoutId);
      expect(
        rows as List,
        hasLength(1),
        reason:
            'Re-save must replace, not append — the RPC deletes the '
            'workout\'s cardio rows before inserting.',
      );
      expect(
        rows.single['duration_seconds'],
        2400,
        reason: 'The LAST save wins, mirroring the workout_exercises shape.',
      );
    });

    test('legacy 3-argument call (no p_cardio) still resolves — pre-38b '
        'clients and queued offline payloads replay unchanged', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      final seeded = await _seedActiveWorkout(
        adminClient: adminClient,
        userId: user.userId,
      );

      // No p_cardio key at all — PostgREST must match the 4-arg function
      // via the parameter DEFAULT.
      final result = await client.rpc(
        'save_workout',
        params: {
          'p_workout': seeded.workoutJson,
          'p_exercises': seeded.exercisesJson,
          'p_sets': seeded.setsJson,
        },
      );
      expect(result, isNotNull);
      expect((result as Map<String, dynamic>)['id'], seeded.workoutId);

      final rows = await client
          .from('cardio_sessions')
          .select('id')
          .eq('workout_id', seeded.workoutId);
      expect(rows as List, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SeededWorkout {
  const _SeededWorkout({
    required this.workoutId,
    required this.workoutJson,
    required this.exercisesJson,
    required this.setsJson,
  });

  final String workoutId;
  final Map<String, dynamic> workoutJson;
  final List<Map<String, dynamic>> exercisesJson;
  final List<Map<String, dynamic>> setsJson;
}

/// Seeds an ACTIVE workout row (save_workout requires the row to pre-exist,
/// matching the production flow where `createActiveWorkout` runs at start
/// time) plus the strength payload: one bench exercise with one completed
/// working set. Returns the JSON payload shapes the RPC call needs.
Future<_SeededWorkout> _seedActiveWorkout({
  required supabase.SupabaseClient adminClient,
  required String userId,
}) async {
  final ts = DateTime.now().toUtc();
  final workoutRow = await adminClient
      .from('workouts')
      .insert({
        'user_id': userId,
        'name': 'Cardio Roundtrip Integration Workout',
        'started_at': ts.toIso8601String(),
        'is_active': true,
      })
      .select('id')
      .single();
  final workoutId = workoutRow['id'] as String;

  final benchId = await exerciseIdForSlug(adminClient, 'barbell_bench_press');
  final weId = _uuid.v4();
  final setId = _uuid.v4();

  return _SeededWorkout(
    workoutId: workoutId,
    workoutJson: {
      'id': workoutId,
      'user_id': userId,
      'name': 'Cardio Roundtrip Integration Workout',
      'finished_at': ts.add(const Duration(minutes: 45)).toIso8601String(),
      'duration_seconds': 2700,
      'notes': null,
      'routine_id': null,
    },
    exercisesJson: [
      {
        'id': weId,
        'workout_id': workoutId,
        'exercise_id': benchId,
        'order': 0,
        'rest_seconds': null,
      },
    ],
    setsJson: [
      {
        'id': setId,
        'workout_exercise_id': weId,
        'set_number': 1,
        'reps': 8,
        'weight': 60.0,
        'rpe': null,
        'set_type': 'working',
        'notes': null,
        'is_completed': true,
        'created_at': ts.toIso8601String(),
      },
    ],
  );
}
