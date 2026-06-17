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
///   3. **Cardio counts toward character level (Phase 38e)** — cardio is now
///      an active track in `character_state`, so earning cardio XP raises the
///      established character level once cardio crosses rank 1. (The
///      never-regress invariant still holds: cardio at rank 1 leaves the
///      level unchanged because Σ ranks and N_active both gain 1.)
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

    test('cardio XP DOES raise the established character level '
        '(Phase 38e — cardio is now an active track)', () async {
      final adminClient = serviceRoleClient();
      final user = await freshUser();
      final client = authenticatedClient(user);

      // Establish a NON-trivial character level via the 6 strength parts first.
      // Level = GREATEST(1, FLOOR((SUM(rank) - COUNT(*)) / 4) + 1). Phase 38e
      // counts SEVEN active parts (cardio joined), but with cardio still at
      // rank 1 the numerator is unchanged: six parts at rank 5 + cardio rank 1
      // → FLOOR((31-7)/4)+1 = 7 (the never-regress invariant — same level the
      // pre-38e 6-part math produced).
      for (final bp in const [
        'chest',
        'back',
        'legs',
        'shoulders',
        'arms',
        'core',
      ]) {
        await seedBodyPartProgress(
          adminClient: adminClient,
          userId: user.userId,
          bodyPart: bp,
          totalXp: 5000,
          rank: 5,
        );
      }

      final csBefore = await client
          .from('character_state')
          .select('character_level')
          .single();
      final levelBefore = ((csBefore as Map)['character_level'] as num).toInt();
      expect(
        levelBefore,
        7,
        reason:
            'six strength parts at rank 5 (+ cardio rank 1) must establish '
            'character level 7 — never-regress invariant holds',
      );

      // Now save a cardio workout (earns cardio body_part_progress).
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

      // Cardio body_part_progress grew + reached a real rank...
      final cardio = await client
          .from('body_part_progress')
          .select('total_xp, rank')
          .eq('body_part', 'cardio')
          .single();
      final cardioMap = cardio as Map;
      final cardioXp = (cardioMap['total_xp'] as num).toDouble();
      final cardioRank = (cardioMap['rank'] as num).toInt();
      expect(
        cardioXp,
        greaterThan(0),
        reason: 'the cardio save must have written body_part_progress[cardio]',
      );
      expect(
        cardioRank,
        greaterThan(1),
        reason:
            'a 40-min treadmill must push cardio past rank 1 so the '
            'level delta is observable',
      );

      // ...and the established character level NOW rises — Phase 38e flipped
      // cardio into the active set, so character_state includes it. Pin the
      // EXACT new level from the deterministic formula over the SEVEN active
      // parts (six strength at rank 5 + cardio at its earned rank).
      final csAfter = await client
          .from('character_state')
          .select('character_level')
          .single();
      final levelAfter = ((csAfter as Map)['character_level'] as num).toInt();
      // GREATEST(1, FLOOR((SUM(rank) - COUNT(*)) / 4) + 1) over 7 parts:
      // SUM = 6*5 + cardioRank, COUNT = 7.
      final sumRanks = 6 * 5 + cardioRank;
      final expectedLevel = (((sumRanks - 7) / 4).floor() + 1).clamp(
        1,
        1 << 30,
      );
      expect(
        levelAfter,
        expectedLevel,
        reason:
            'Phase 38e: cardio now contributes to character level — '
            'six strength@5 + cardio@$cardioRank → level $expectedLevel '
            '(before=$levelBefore, after=$levelAfter)',
      );
      expect(
        levelAfter,
        greaterThan(levelBefore),
        reason: 'cardio reaching rank $cardioRank (>1) must raise the level',
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
      'weekly MET-min cap accumulates ACROSS saves within the ISO week — '
      'a second large cardio workout the same week earns LESS (finding [2])',
      () async {
        final adminClient = serviceRoleClient();
        final user = await freshUser();
        final client = authenticatedClient(user);

        final treadmillId = await exerciseIdForSlug(adminClient, 'treadmill');

        // Two SEPARATE workouts (distinct workout_ids) so this is genuinely a
        // cross-SAVE accumulation, not a multi-entry single save. Each carries a
        // long duration-only treadmill session big enough that the running ISO-
        // week eff_met_min crosses WEEKLY_CARDIO_CAP_METMIN (2500) by the second
        // save → the second save's over-cap portion is attenuated (× 0.30).
        const durationSeconds =
            9000; // 150 min @ MET 9.8 ≈ 1470 met-min/session

        // Returns (workoutId, cumulative cardio total_xp after this save) so the
        // assertions can address each save's cardio_session event by its own
        // session_id — never by occurred_at ordering, which ties when two saves
        // land in the same clock resolution.
        Future<({String workoutId, double cardioTotal})>
        saveOneCardioWorkout() async {
          final seeded = await _seedActiveCardioWorkout(
            adminClient: adminClient,
            userId: user.userId,
          );
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
          final row = await client
              .from('body_part_progress')
              .select('total_xp')
              .eq('body_part', 'cardio')
              .single();
          return (
            workoutId: seeded.workoutId,
            cardioTotal: ((row as Map)['total_xp'] as num).toDouble(),
          );
        }

        final first = await saveOneCardioWorkout();
        final second = await saveOneCardioWorkout();
        final afterFirst = first.cardioTotal;
        final afterSecond = second.cardioTotal;

        final firstIncrement = afterFirst;
        final secondIncrement = afterSecond - afterFirst;

        expect(
          firstIncrement,
          greaterThan(0),
          reason: 'the first large cardio workout must earn cardio XP',
        );
        expect(
          secondIncrement,
          greaterThan(0),
          reason: 'the second workout still earns SOMETHING (over-cap × 0.30)',
        );
        // The load-bearing assertion: identical sessions, but the second earns
        // strictly LESS because the weekly cap carried over from the first save.
        // If v_week_used reset to 0 each save (the bug), both increments would be
        // EQUAL. A meaningful margin (second < 80% of first) proves the cap
        // engaged rather than a rounding wobble.
        expect(
          secondIncrement,
          lessThan(firstIncrement * 0.80),
          reason:
              'cross-save weekly cap must attenuate the second identical '
              'workout (first=$firstIncrement, second=$secondIncrement). Equal '
              'increments would mean v_week_used reset per save.',
        );

        // Both cardio xp_events this week carry an eff_met_min payload key (the
        // accumulator the seed query sums). Two distinct sessions → two rows.
        final events = await client
            .from('xp_events')
            .select('payload')
            .eq('event_type', 'cardio_session');
        expect(events as List, hasLength(2));
        for (final e in events) {
          final payload = (e as Map)['payload'] as Map<String, dynamic>;
          expect(
            payload.containsKey('eff_met_min'),
            isTrue,
            reason:
                'each cardio_session event must persist eff_met_min so the next '
                'save can seed v_week_used from it',
          );
        }
        // The second save's week_used_before must equal the FIRST save's
        // eff_met_min (the cross-save carry), not 0. Address each event by its
        // own session_id (workout_id) — NOT by occurred_at ordering, which is a
        // non-deterministic tie when both saves land in the same clock tick.
        final firstEvent = await client
            .from('xp_events')
            .select('payload')
            .eq('event_type', 'cardio_session')
            .eq('session_id', first.workoutId)
            .single();
        final secondEvent = await client
            .from('xp_events')
            .select('payload')
            .eq('event_type', 'cardio_session')
            .eq('session_id', second.workoutId)
            .single();
        final firstEff =
            (((firstEvent as Map)['payload']
                        as Map<String, dynamic>)['eff_met_min']
                    as num)
                .toDouble();
        final secondBefore =
            (((secondEvent as Map)['payload']
                        as Map<String, dynamic>)['week_used_before']
                    as num)
                .toDouble();
        expect(
          secondBefore,
          closeTo(firstEff, 0.01),
          reason:
              'the second save must seed v_week_used from the first save\'s '
              'eff_met_min (carry across saves), not 0',
        );
      },
    );

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
