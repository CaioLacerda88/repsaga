/// Integration tests for Phase 18a `record_set_xp` RPC.
///
/// Requires local Supabase running: `npx supabase start`
///
/// Each test gets its own isolated Supabase user (created in setUp, deleted in
/// tearDown) so tests never share mutable state.
///
/// What these tests validate:
///
/// 1. **PG/Dart parity** — for the same (weight, reps, exercise) inputs, the
///    `record_set_xp` Postgres function and the Dart `XpCalculator` produce
///    `body_part_progress.total_xp` within 0.01 of each other.
///
/// 2. **Re-save idempotency (BUG-RPG-001 regression)** — saving the same
///    workout twice must NOT double `body_part_progress.total_xp`. The fix
///    is the REVERSAL PATTERN inside `save_workout`: before cascading the
///    prior sets, decrement body_part_progress by the contribution of the
///    xp_events linked to this session, then let record_set_xp re-add from
///    scratch.
///
/// 3. **Concurrent same-set guard** — two concurrent `record_set_xp` calls for
///    the same set_id produce exactly one xp_events row.
///
/// 4. **exercise_peak_loads advancement** — new PR advances peak; deload
///    does not regress it.
///
/// Run: flutter test --tags integration test/integration/rpg_record_set_xp_test.dart
@Tags(['integration'])
library;

// Helpers in this file accept Supabase clients as `dynamic` to avoid leaking
// the test-only differentiation between admin and user clients into the typed
// surface. Production code does not use this pattern — the
// `avoid_dynamic_calls` lint stays enabled everywhere else.
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/implied_tier.dart';
import 'package:repsaga/features/rpg/domain/xp_calculator.dart';
import 'package:repsaga/features/rpg/domain/xp_distribution.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/xp_event.dart';

import 'rpg_integration_setup.dart';

void main() {
  // Unique suffix per test run to avoid email conflicts on reruns.
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;

  // Each test creates and destroys its own user for full isolation.
  TestUser? currentUser;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('rpg-rsx-$runId-$idx@test.local');
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
  // PG/Dart parity
  // ---------------------------------------------------------------------------

  group('record_set_xp PG/Dart parity', () {
    /// Bench press 60kg×8 (fresh first set, no prior peak).
    /// Attribution: chest 0.70, shoulders 0.20, arms 0.10.
    test(
      'bench press 60kg×8: body_part_progress matches Dart calculator',
      () async {
        const slug = 'barbell_bench_press';
        const weight = 60.0;
        const reps = 8;

        final user = await freshUser();
        final adminClient = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final seed = await seedWorkout(
          adminClient: adminClient,
          userId: user.userId,
          exerciseSlug: slug,
          weightKg: weight,
          reps: reps,
          numSets: 1,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: weight,
          reps: reps,
          numSets: 1,
        );

        // Phase 24a Phase F: read the curated per-exercise multiplier from
        // the same exercises row the SQL RPC reads (mirror the SQL side).
        final difficulty = await difficultyMultForSlug(adminClient, slug);

        // Dart: fresh first set, no prior peak → strength_mult = 1.0.
        // Phase 29 v2: feed the same implied_tier / current_rank the SQL
        // chain derives for the seeded fresh user (NULL bodyweight → tier
        // 15.0; no progress row → rank 1) so tier_diff_mult /
        // abs_strength_premium match exactly.
        final dartComps = XpCalculator.computeSetXp(
          weightKg: weight,
          reps: reps,
          peakLoad: 0,
          sessionVolumeForBodyPart: 0,
          weeklyVolumeForBodyPart: 0,
          difficultyMult: difficulty,
          impliedTier: _seededImpliedTier(slug, weight, reps),
          currentRank: _seededCurrentRank,
        );
        final dartXp = XpDistribution.distribute(
          setXp: dartComps.setXp,
          attribution: Attribution.fromMap({
            'chest': 0.70,
            'shoulders': 0.20,
            'arms': 0.10,
          }),
        );

        final pgRows = await userClient
            .from('body_part_progress')
            .select('body_part, total_xp')
            .order('body_part');
        final pgByBp = {
          for (final row in pgRows as List)
            (row as Map<String, dynamic>)['body_part'] as String: row,
        };

        for (final bp in [BodyPart.chest, BodyPart.shoulders, BodyPart.arms]) {
          final dartXpBp = dartXp[bp]!;
          final pgRow = pgByBp[bp.dbValue];
          expect(
            pgRow,
            isNotNull,
            reason: 'Expected body_part_progress row for ${bp.dbValue}',
          );
          final pgXp = (pgRow!['total_xp'] as num).toDouble();
          expect(
            (pgXp - dartXpBp).abs(),
            lessThanOrEqualTo(_kTol),
            reason:
                '${bp.dbValue}: PG=$pgXp vs Dart=$dartXpBp '
                '(delta ${(pgXp - dartXpBp).abs().toStringAsFixed(6)})',
          );
        }

        // xp_events: exactly one row + payload carries `difficulty_mult` key.
        // We select the FULL row shape (not just `id, payload`) so we can
        // also exercise XpEvent.fromJson's payload-promotion (PR #222
        // reviewer Blocker): difficulty_mult is snapshotted INSIDE
        // payload, not as a top-level column, so the model's custom
        // factory must promote it for `event.difficultyMult` to be
        // non-null. Without the promotion this assertion fails.
        final events = await userClient
            .from('xp_events')
            .select()
            .eq('set_id', seed.setIds.first);
        expect(events, hasLength(1));
        final eventRow = (events as List).first as Map<String, dynamic>;
        final payload = eventRow['payload'] as Map<String, dynamic>;
        expect(
          payload.containsKey('difficulty_mult'),
          isTrue,
          reason:
              'xp_events.payload must include difficulty_mult key '
              '(Phase 24a Phase D / Dart SetXpComponents.toJson contract)',
        );
        expect(
          (payload['difficulty_mult'] as num).toDouble(),
          closeTo(difficulty, 1e-9),
          reason:
              'payload.difficulty_mult must equal exercises.difficulty_mult '
              'for the seeded slug ($slug, expected $difficulty)',
        );

        // PR #222 Blocker regression: XpEvent.fromJson must promote
        // payload.difficulty_mult to the top-level `difficultyMult`
        // field. The generated `_$XpEventFromJson` reads
        // `json['difficulty_mult']` (top-level), but the SQL RPC writes
        // it INSIDE payload — without the custom factory's promotion,
        // event.difficultyMult would always be null for every event
        // ever written.
        final event = XpEvent.fromJson(eventRow);
        expect(
          event.difficultyMult,
          isNotNull,
          reason:
              'XpEvent.difficultyMult must be non-null after fromJson '
              'round-trip (payload-promotion contract). Raw payload '
              'value: ${payload['difficulty_mult']}',
        );
        expect(
          event.difficultyMult,
          closeTo(difficulty, 1e-9),
          reason:
              'event.difficultyMult ($event.difficultyMult) must equal '
              'exercises.difficulty_mult ($difficulty) — proves the '
              'fromJson factory correctly promoted payload.difficulty_mult '
              'to the model field, not just left it as a payload entry.',
        );
      },
    );

    test('overhead press 80kg×5: three-way attribution matches Dart (shoulders '
        '0.60 / arms 0.20 / core 0.20)', () async {
      const slug = 'overhead_press';
      const weight = 80.0;
      const reps = 5;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: weight,
        reps: reps,
        numSets: 1,
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed,
        userId: user.userId,
        weightKg: weight,
        reps: reps,
        numSets: 1,
      );

      // Phase 24a Phase F: read curated multiplier; SQL RPC reads the same.
      final difficulty = await difficultyMultForSlug(adminClient, slug);
      final dartComps = XpCalculator.computeSetXp(
        weightKg: weight,
        reps: reps,
        peakLoad: 0,
        sessionVolumeForBodyPart: 0,
        weeklyVolumeForBodyPart: 0,
        difficultyMult: difficulty,
        impliedTier: _seededImpliedTier(slug, weight, reps),
        currentRank: _seededCurrentRank,
      );
      final dartXp = XpDistribution.distribute(
        setXp: dartComps.setXp,
        attribution: Attribution.fromMap({
          'shoulders': 0.60,
          'arms': 0.20,
          'core': 0.20,
        }),
      );

      final pgRows = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp');
      final pgByBp = {
        for (final row in pgRows as List)
          (row as Map<String, dynamic>)['body_part'] as String: row,
      };

      for (final bp in [BodyPart.shoulders, BodyPart.arms, BodyPart.core]) {
        final dartXpBp = dartXp[bp]!;
        final pgRow = pgByBp[bp.dbValue];
        expect(pgRow, isNotNull);
        final pgXp = (pgRow!['total_xp'] as num).toDouble();
        expect(
          (pgXp - dartXpBp).abs(),
          lessThanOrEqualTo(_kTol),
          reason: '${bp.dbValue}: PG=$pgXp vs Dart=$dartXpBp',
        );
      }
    });

    test('deadlift 100kg×5: four-way attribution (back 0.40, legs 0.40, core '
        '0.10, arms 0.10) matches Dart', () async {
      const slug = 'deadlift';
      const weight = 100.0;
      const reps = 5;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: weight,
        reps: reps,
        numSets: 1,
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed,
        userId: user.userId,
        weightKg: weight,
        reps: reps,
        numSets: 1,
      );

      // Phase 24a Phase F: read curated multiplier; SQL RPC reads the same.
      final difficulty = await difficultyMultForSlug(adminClient, slug);
      final dartComps = XpCalculator.computeSetXp(
        weightKg: weight,
        reps: reps,
        peakLoad: 0,
        sessionVolumeForBodyPart: 0,
        weeklyVolumeForBodyPart: 0,
        difficultyMult: difficulty,
        impliedTier: _seededImpliedTier(slug, weight, reps),
        currentRank: _seededCurrentRank,
      );
      final dartXp = XpDistribution.distribute(
        setXp: dartComps.setXp,
        attribution: Attribution.fromMap({
          'back': 0.40,
          'legs': 0.40,
          'core': 0.10,
          'arms': 0.10,
        }),
      );

      final pgRows = await userClient
          .from('body_part_progress')
          .select('body_part, total_xp');
      final pgByBp = {
        for (final row in pgRows as List)
          (row as Map<String, dynamic>)['body_part'] as String: row,
      };

      for (final bp in [
        BodyPart.back,
        BodyPart.legs,
        BodyPart.core,
        BodyPart.arms,
      ]) {
        final dartXpBp = dartXp[bp]!;
        final pgRow = pgByBp[bp.dbValue];
        expect(pgRow, isNotNull, reason: '${bp.dbValue} row missing');
        final pgXp = (pgRow!['total_xp'] as num).toDouble();
        expect(
          (pgXp - dartXpBp).abs(),
          lessThanOrEqualTo(_kTol),
          reason: '${bp.dbValue}: PG=$pgXp vs Dart=$dartXpBp',
        );
      }
    });

    /// Phase 24a Phase F: a user-created exercise has `is_default = false`
    /// and reads the `exercises.difficulty_mult` column default (1.0). The
    /// SQL RPC's `COALESCE(difficulty_mult, 1.0)` returns 1.0 and
    /// `payload.difficulty_mult` must equal exactly 1.0 — confirming both
    /// the COALESCE path and the no-effect-at-1.0 invariant.
    ///
    /// We construct a minimal user-owned exercise inline so the test does
    /// not depend on any default-exercise side-effect changes.
    test('user-created exercise reads difficulty_mult column default 1.0 '
        '(COALESCE path)', () async {
      const weight = 80.0;
      const reps = 8;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      // Create a user-owned, non-default exercise via the production RPC
      // (`fn_insert_user_exercise`) — same path the create-exercise screen
      // uses. The RPC leaves `xp_attribution` NULL for user exercises, so
      // the SQL chain's NULL-fallback assigns 1.0 share to the primary
      // muscle_group (chest). Critically, the RPC inserts NO
      // difficulty_mult — the column DEFAULT (1.0, migration 00053) applies.
      final createdRows =
          await userClient.rpc(
                'fn_insert_user_exercise',
                params: {
                  'p_user_id': user.userId,
                  'p_locale': 'en',
                  'p_name': 'Custom Bench Phase24a $runId',
                  'p_muscle_group': 'chest',
                  'p_equipment_type': 'barbell',
                },
              )
              as List;
      final customExerciseId =
          (createdRows.first as Map<String, dynamic>)['id'] as String;

      // Confirm column DEFAULT 1.0 applied + xp_attribution is NULL (so the
      // SQL NULL-fallback at the per-bp loop assigns 1.0 share to chest).
      final customRow = await adminClient
          .from('exercises')
          .select('difficulty_mult, xp_attribution')
          .eq('id', customExerciseId)
          .single();
      expect(
        (customRow['difficulty_mult'] as num).toDouble(),
        equals(1.0),
        reason:
            'User-created exercises must read difficulty_mult = 1.0 '
            'from the column DEFAULT (migration 00053).',
      );
      expect(
        customRow['xp_attribution'],
        isNull,
        reason:
            'fn_insert_user_exercise leaves xp_attribution NULL — '
            'SQL chain falls back to primary muscle_group at 1.0 share.',
      );

      // Seed a workout containing one set of the custom exercise. We use
      // adminClient INSERTs directly (mirroring seedWorkout's shape) since
      // seedWorkout requires a default-exercise slug and we need a
      // user-owned custom exercise here.
      final ts = DateTime.now().toUtc();
      final workoutRow = await adminClient
          .from('workouts')
          .insert({
            'user_id': user.userId,
            'name': 'Integration Test Workout (custom ex)',
            'started_at': ts.toIso8601String(),
            'finished_at': ts.add(const Duration(hours: 1)).toIso8601String(),
            'is_active': false,
          })
          .select('id')
          .single();
      final workoutId = workoutRow['id'] as String;
      final weRow = await adminClient
          .from('workout_exercises')
          .insert({
            'workout_id': workoutId,
            'exercise_id': customExerciseId,
            'order': 1,
          })
          .select('id')
          .single();
      final weId = weRow['id'] as String;
      final setRow = await adminClient
          .from('sets')
          .insert({
            'workout_exercise_id': weId,
            'set_number': 1,
            'reps': reps,
            'weight': weight,
            'is_completed': true,
            'set_type': 'working',
          })
          .select('id')
          .single();
      final setId = setRow['id'] as String;

      // Drive XP via record_set_xp directly (the same code path the
      // production save_workout chain ends up taking).
      await userClient.rpc('record_set_xp', params: {'p_set_id': setId});

      // Dart reference: difficulty_mult = 1.0 (column default). The seeded
      // user has no profile bodyweight → SQL implied_tier = 15.0 (the
      // NULL-bodyweight fallback, independent of the exercise slug since the
      // fallback fires before the family dispatch); no body_part_progress
      // row → current_rank = 1.
      final dartComps = XpCalculator.computeSetXp(
        weightKg: weight,
        reps: reps,
        peakLoad: 0,
        sessionVolumeForBodyPart: 0,
        weeklyVolumeForBodyPart: 0,
        difficultyMult: 1.0,
        impliedTier: _seededImpliedTier('barbell_bench_press', weight, reps),
        currentRank: _seededCurrentRank,
      );

      final pgRow = await userClient
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'chest')
          .single();
      final pgChest = (pgRow['total_xp'] as num).toDouble();
      // attribution chest=1.0 → entire setXp lands on chest.
      expect(
        (pgChest - dartComps.setXp).abs(),
        lessThanOrEqualTo(_kTol),
        reason:
            'User-created exercise XP must match Dart with '
            'difficulty_mult=1.0. PG=$pgChest, Dart=${dartComps.setXp}',
      );

      // Payload key contract: difficulty_mult present and exactly 1.0.
      final events = await userClient
          .from('xp_events')
          .select('payload')
          .eq('set_id', setId);
      expect(events, hasLength(1));
      final payload =
          ((events as List).first as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      expect(
        payload.containsKey('difficulty_mult'),
        isTrue,
        reason: 'payload must include difficulty_mult key',
      );
      expect(
        (payload['difficulty_mult'] as num).toDouble(),
        closeTo(1.0, 1e-9),
        reason:
            'User-created exercise payload must record difficulty_mult=1.0 '
            'from the COALESCE(NULL, 1.0) → DEFAULT path',
      );
    });

    /// Novelty diminishing returns: 5 back-to-back bench sets. The session
    /// volume for chest accumulates, reducing later sets' XP. The total chest
    /// XP must be less than 5× a single set's XP.
    test('novelty diminishing returns: 5 bench sets in one session earn less '
        'than 5× a single set', () async {
      const slug = 'barbell_bench_press';
      const weight = 80.0;
      const reps = 8;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: weight,
        reps: reps,
        numSets: 5,
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed,
        userId: user.userId,
        weightKg: weight,
        reps: reps,
        numSets: 5,
      );

      final pgRow = await userClient
          .from('body_part_progress')
          .select('total_xp')
          .eq('body_part', 'chest')
          .single();
      final pgChestTotal = (pgRow['total_xp'] as num).toDouble();

      // Phase 24a Phase F: read curated multiplier (bench is T3 + 2 sec → 1.09
      // per migration 00053). The 5×-bound stays valid regardless of the
      // multiplier value because both sides scale by the same constant; we
      // still mirror what record_set_xp uses for completeness.
      final difficulty = await difficultyMultForSlug(adminClient, slug);
      // Single set XP at 80kg×8 (strength_mult=1.0 for first set). Phase 29
      // v2: mirror the SQL implied_tier / current_rank for the seeded fresh
      // user so the single-set reference is on the same scale as the 5
      // accumulated sets (both bounds scale identically by tier_diff_mult).
      final singleComps = XpCalculator.computeSetXp(
        weightKg: weight,
        reps: reps,
        peakLoad: 0,
        sessionVolumeForBodyPart: 0,
        weeklyVolumeForBodyPart: 0,
        difficultyMult: difficulty,
        impliedTier: _seededImpliedTier(slug, weight, reps),
        currentRank: _seededCurrentRank,
      );
      final singleChestXp = singleComps.setXp * 0.70;

      // 5 sets with diminishing returns must total LESS than 5× single set.
      expect(
        pgChestTotal,
        lessThan(singleChestXp * 5),
        reason:
            'Chest XP from 5 sets ($pgChestTotal) must be less than '
            '5× single-set ($singleChestXp × 5 = ${singleChestXp * 5}) '
            'due to novelty diminishing returns',
      );
      // Must also be positive and > single-set (at least 1 set counted).
      expect(pgChestTotal, greaterThan(singleChestXp * 0.9));

      // 5 strength `set` xp_events rows. Scoped to event_type='set' because
      // Phase 38c's strength→cardio cross-credit adds one extra
      // 'cardio_session' row per save (derived from these strength sets) — a
      // legitimate, separate event that the original "5 sets" intent excludes.
      final events = await userClient
          .from('xp_events')
          .select('id')
          .eq('session_id', seed.workoutId)
          .eq('event_type', 'set');
      expect(events, hasLength(5));
    });
  });

  // ---------------------------------------------------------------------------
  // BUG-RPG-001: save_workout re-save doubles body_part_progress XP
  // ---------------------------------------------------------------------------

  group('record_set_xp idempotency / cascade', () {
    /// BUG-RPG-001 regression — REVERSAL PATTERN.
    ///
    /// `save_workout` deletes old workout_exercises (cascade-deleting sets +
    /// xp_events) and re-inserts them. The xp_events rows are wiped. The fix
    /// (inside the migration) decrements `body_part_progress.total_xp` by
    /// the per-bp contributions of the prior session's xp_events BEFORE the
    /// cascade, so `record_set_xp` rebuilds the totals from a clean baseline
    /// for that session.
    ///
    /// Acceptance: re-saving the same workout produces the SAME final
    /// `body_part_progress.total_xp` as a single save (within numeric
    /// tolerance), regardless of how many times the user re-saves.
    test(
      'BUG-RPG-001 regression: re-save does NOT double body_part_progress XP',
      () async {
        const slug = 'barbell_bench_press';
        const weight = 100.0;
        const reps = 5;

        final user = await freshUser();
        final adminClient = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final seed = await seedWorkout(
          adminClient: adminClient,
          userId: user.userId,
          exerciseSlug: slug,
          weightKg: weight,
          reps: reps,
          numSets: 2,
        );

        // First save.
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: weight,
          reps: reps,
          numSets: 2,
        );
        final chestAfterFirst = await _readBodyPartXp(userClient, 'chest');
        final shouldersAfterFirst = await _readBodyPartXp(
          userClient,
          'shoulders',
        );
        final armsAfterFirst = await _readBodyPartXp(userClient, 'arms');

        // Second save of the same workout.
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: weight,
          reps: reps,
          numSets: 2,
        );
        final chestAfterSecond = await _readBodyPartXp(userClient, 'chest');
        final shouldersAfterSecond = await _readBodyPartXp(
          userClient,
          'shoulders',
        );
        final armsAfterSecond = await _readBodyPartXp(userClient, 'arms');

        // After fix: re-save reverts the prior contribution before re-adding,
        // so totals match the single-save totals (within rounding tolerance).
        expect(
          (chestAfterSecond - chestAfterFirst).abs(),
          lessThanOrEqualTo(_kTol),
          reason:
              'Re-save must not change chest XP. '
              'After first save: $chestAfterFirst, after second: $chestAfterSecond '
              '(delta ${(chestAfterSecond - chestAfterFirst).abs()}).',
        );
        expect(
          (shouldersAfterSecond - shouldersAfterFirst).abs(),
          lessThanOrEqualTo(_kTol),
          reason:
              'Re-save must not change shoulders XP. '
              'first=$shouldersAfterFirst second=$shouldersAfterSecond',
        );
        expect(
          (armsAfterSecond - armsAfterFirst).abs(),
          lessThanOrEqualTo(_kTol),
          reason:
              'Re-save must not change arms XP. '
              'first=$armsAfterFirst second=$armsAfterSecond',
        );
      },
    );

    /// Re-save with SAME workout id but DIFFERENT weights/reps must update the
    /// totals to the new value (not stack). This guards against a regression
    /// where the reversal pattern accidentally only handles the equal-weights
    /// case.
    test(
      'BUG-RPG-001 regression: re-save with different weights replaces, not stacks',
      () async {
        const slug = 'barbell_bench_press';
        const reps = 5;

        final user = await freshUser();
        final adminClient = serviceRoleClient();
        final userClient = authenticatedClient(user);

        // First save: 80kg×5
        final seed = await seedWorkout(
          adminClient: adminClient,
          userId: user.userId,
          exerciseSlug: slug,
          weightKg: 80.0,
          reps: reps,
          numSets: 1,
        );
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 80.0,
          reps: reps,
          numSets: 1,
        );

        // Second save: 90kg×5 (heavier — peak advances, strength_mult=1.0
        // both times because peak advances inline before strength_mult).
        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: 90.0,
          reps: reps,
          numSets: 1,
        );

        // Final state must equal the 90kg×5 award ALONE — NOT (80kg + 90kg)
        // stacked. The reversal pattern reverts the prior 80kg contribution
        // before re-adding, so chest holds only the second save's award.
        final finalChest = await _readBodyPartXp(userClient, 'chest');

        // Reference: a fresh user whose state EXACTLY reproduces the re-save
        // user's at the moment its 90kg×5 set is (re-)processed, so the two
        // chest totals are deterministically equal.
        //
        // Why not a single fresh 90kg×5 save? Phase 29 v2's overload_mult
        // (Refinement #2) reads exercise_peak_loads_by_rep_range — a SEPARATE
        // per-band PR tracker NOT cascade-deleted by save_workout's re-save.
        // After the re-save user's first save (80kg×5), its 'strength'-band
        // PR is 80kg×5; the second save's 90 > 80 legitimately earns
        // overload_mult = 1.15. A fresh single 90kg×5 save has no prior band
        // → overload_mult = 1.0, under-rewarding by exactly 1.15× — NOT a
        // valid oracle. (This 1.15× gap, not a stacking bug, is what the old
        // 0.5 tolerance masked and then failed on once Phase 29 v2 shipped.)
        //
        // We can't replay the 80kg×5 as a real prior WORKOUT either: that
        // would add a second chest session in the 7d window, bumping
        // frequency_mult to 1.06 (the re-save user's 80kg was the SAME
        // session, reverted, so its frequency_mult stays 1.00). Instead we
        // seed ONLY the band-peak ladder directly (admin, bypassing RLS) —
        // the exact residual state the re-save leaves — then save 90kg×5 as
        // the user's only chest workout. Result: overload_mult = 1.15,
        // frequency_mult = 1.00, no extra chest XP stacked. The reference
        // chest must then equal the re-save user's final chest EXACTLY.
        final ref = await freshUser();
        final refClient = authenticatedClient(ref);
        await adminClient.from('exercise_peak_loads_by_rep_range').insert({
          'user_id': ref.userId,
          'exercise_slug': slug,
          'rep_band': 'strength', // 5 reps → 'strength' band (rpg_rep_band)
          'best_weight': 80.0,
          'best_reps': reps,
        });
        final refSeed = await seedWorkout(
          adminClient: adminClient,
          userId: ref.userId,
          exerciseSlug: slug,
          weightKg: 90.0,
          reps: reps,
          numSets: 1,
        );
        await saveWorkoutRpc(
          userClient: refClient,
          seed: refSeed,
          userId: ref.userId,
          weightKg: 90.0,
          reps: reps,
          numSets: 1,
        );
        final refChest = await _readBodyPartXp(refClient, 'chest');

        // Deterministic equality: re-save replaced (kept only the 90kg×5
        // award), and both 90kg×5 awards carry the identical 11-multiplier
        // chain (overload 1.15 from the seeded 80kg×5 strength-band PR).
        expect(
          (finalChest - refChest).abs(),
          lessThanOrEqualTo(_kTol),
          reason:
              'Re-save with heavier weight must REPLACE the prior award, '
              'leaving exactly the 90kg×5 award. Re-saved chest=$finalChest, '
              'reference 90kg×5 award=$refChest, '
              'delta=${(finalChest - refChest).abs()}. A delta ≈ the 80kg '
              'award means the reversal stacked; a delta ≈ 1.15× factor means '
              'the overload ladders diverged.',
        );
      },
    );

    test(
      'xp_events cascade: re-save deletes old events and creates fresh ones',
      () async {
        const slug = 'barbell_bench_press';
        const weight = 100.0;
        const reps = 5;

        final user = await freshUser();
        final adminClient = serviceRoleClient();
        final userClient = authenticatedClient(user);

        final seed = await seedWorkout(
          adminClient: adminClient,
          userId: user.userId,
          exerciseSlug: slug,
          weightKg: weight,
          reps: reps,
          numSets: 2,
        );

        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: weight,
          reps: reps,
          numSets: 2,
        );
        // Scope to event_type='set': Phase 38c's strength→cardio cross-credit
        // adds one separate 'cardio_session' row per save (also deleted + freshly
        // re-inserted on re-save). The original intent here is the STRENGTH `set`
        // event cascade — two sets → two `set` rows whose IDs change on re-save.
        final ids1 = {
          for (final row
              in (await userClient
                      .from('xp_events')
                      .select('id')
                      .eq('session_id', seed.workoutId)
                      .eq('event_type', 'set'))
                  as List)
            (row as Map<String, dynamic>)['id'] as String,
        };
        expect(ids1, hasLength(2));

        await saveWorkoutRpc(
          userClient: userClient,
          seed: seed,
          userId: user.userId,
          weightKg: weight,
          reps: reps,
          numSets: 2,
        );
        final ids2 = {
          for (final row
              in (await userClient
                      .from('xp_events')
                      .select('id')
                      .eq('session_id', seed.workoutId)
                      .eq('event_type', 'set'))
                  as List)
            (row as Map<String, dynamic>)['id'] as String,
        };
        expect(ids2, hasLength(2));

        // IDs must be NEW (old ones were cascade-deleted and new ones created).
        expect(
          ids2.intersection(ids1),
          isEmpty,
          reason:
              'xp_events IDs must change on re-save (cascade delete + fresh '
              'insert by record_set_xp)',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Concurrent same-set guard
  // ---------------------------------------------------------------------------

  group('record_set_xp concurrent same-set guard', () {
    test('two concurrent record_set_xp calls for the same set_id produce '
        'exactly one xp_events row (UNIQUE INDEX guard)', () async {
      const slug = 'barbell_bench_press';

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: 100.0,
        reps: 5,
        numSets: 1,
      );

      // Call record_set_xp twice concurrently for the same set_id.
      await Future.wait([
        userClient.rpc(
          'record_set_xp',
          params: {'p_set_id': seed.setIds.first},
        ),
        userClient.rpc(
          'record_set_xp',
          params: {'p_set_id': seed.setIds.first},
        ),
      ]);

      final events = await userClient
          .from('xp_events')
          .select('id')
          .eq('set_id', seed.setIds.first);
      expect(
        events,
        hasLength(1),
        reason:
            'Concurrent calls for the same set_id must produce exactly '
            'one xp_events row. Got ${(events as List).length}',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // exercise_peak_loads
  // ---------------------------------------------------------------------------

  group('exercise_peak_loads advancement', () {
    test('new PR advances peak_weight', () async {
      const slug = 'barbell_bench_press';
      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed1 = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: 80.0,
        reps: 5,
        numSets: 1,
        startedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed1,
        userId: user.userId,
        weightKg: 80.0,
        reps: 5,
        numSets: 1,
      );

      final peak1 = await userClient
          .from('exercise_peak_loads')
          .select('peak_weight')
          .eq('exercise_id', seed1.exerciseId)
          .single();
      expect((peak1['peak_weight'] as num).toDouble(), equals(80.0));

      final seed2 = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: 90.0,
        reps: 5,
        numSets: 1,
        startedAt: DateTime.now(),
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed2,
        userId: user.userId,
        weightKg: 90.0,
        reps: 5,
        numSets: 1,
      );

      final peak2 = await userClient
          .from('exercise_peak_loads')
          .select('peak_weight')
          .eq('exercise_id', seed1.exerciseId)
          .single();
      expect(
        (peak2['peak_weight'] as num).toDouble(),
        equals(90.0),
        reason: 'Peak must advance from 80 to 90 on new PR',
      );
    });

    test('deload does not lower peak_weight', () async {
      const slug = 'barbell_bench_press';
      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      final seed1 = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: 100.0,
        reps: 5,
        numSets: 1,
        startedAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed1,
        userId: user.userId,
        weightKg: 100.0,
        reps: 5,
        numSets: 1,
      );

      final seed2 = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: 70.0,
        reps: 5,
        numSets: 1,
        startedAt: DateTime.now(),
      );
      await saveWorkoutRpc(
        userClient: userClient,
        seed: seed2,
        userId: user.userId,
        weightKg: 70.0,
        reps: 5,
        numSets: 1,
      );

      final peakAfterDeload = await userClient
          .from('exercise_peak_loads')
          .select('peak_weight')
          .eq('exercise_id', seed1.exerciseId)
          .single();
      expect(
        (peakAfterDeload['peak_weight'] as num).toDouble(),
        equals(100.0),
        reason: 'Peak must remain 100 after deload at 70',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 24c — bodyweight load semantics (PR #TBD)
  //
  // Validates the migration 00057 contract for the four boundary scenarios
  // captured in the regenerated rpg_xp_fixtures.json (set_xp_examples block):
  //
  //   1. pure bodyweight       — pull_up, weight=0, bodyweight=70
  //   2. weighted bodyweight   — pull_up, weight=20 (belt), bodyweight=70
  //   3. flag off (negative)   — bench press, weight=80, bodyweight=70 (ignored)
  //   4. null bodyweight       — pull_up, weight=20, bodyweight=NULL (graceful
  //                              fallback: effective = entered, flag still on)
  //
  // For each scenario we assert:
  //   * payload.effective_load matches the SQL CASE expression
  //   * payload.bodyweight_used matches exercises.uses_bodyweight_load
  //   * payload.volume_load = effective_load × reps (re-derived from
  //     effective_weight per migration 00057's snapshot rule)
  //   * XpEvent.bodyweightUsed matches payload.bodyweight_used after the
  //     fromJson factory promotes the payload-nested key (Phase 24c-3
  //     contract validated end-to-end against a live SQL row).
  //
  // Each test seeds the workout with adminClient + calls record_set_xp
  // directly (skipping save_workout's record_session_xp_batch path) so the
  // assertion targets the per-set RPC's payload writer specifically. The
  // batch RPC is exercised by the existing PG/Dart parity group above and
  // by the wider save_workout integration tests.
  // ---------------------------------------------------------------------------

  group('Phase 24c — bodyweight load semantics', () {
    /// Pure bodyweight: pull-up with NO added weight on a lifter with a
    /// known bodyweight. The SQL CASE adds bodyweight (70) to entered
    /// weight (0) → effective_load = 70. volume_load = 70 × 8 = 560.
    /// Without Phase 24c the bare entered weight (0) would zero out
    /// volume_load to GREATEST(1.0, 0) = 1.0 — silently under-counting
    /// every bodyweight set ever logged.
    test('pull-up with bodyweight=70, weight=0 (pure bodyweight): payload '
        'effective_load=70, volume_load=560, bodyweight_used=true', () async {
      const slug = 'pull_up';
      const enteredWeight = 0.0;
      const reps = 8;
      const bodyweight = 70.0;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      // Set bodyweight on the user's profile BEFORE seeding the workout.
      // record_set_xp pre-fetches profiles.bodyweight_kg once at Step 1.5;
      // setting it here ensures the SQL chain reads 70 for this user.
      await adminClient.from('profiles').upsert({
        'id': user.userId,
        'bodyweight_kg': bodyweight,
      }, onConflict: 'id');

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: enteredWeight,
        reps: reps,
        numSets: 1,
      );
      await userClient.rpc(
        'record_set_xp',
        params: {'p_set_id': seed.setIds.first},
      );

      // Sanity: the curated 20-slug list (migration 00056) marked pull_up.
      final usesBw = await bodyweightLoadForSlug(adminClient, slug);
      expect(
        usesBw,
        isTrue,
        reason:
            'pull_up must be flagged uses_bodyweight_load=TRUE per the '
            '20-slug curation in migration 00056. If this fails, the '
            'curation list drifted.',
      );

      final events = await userClient
          .from('xp_events')
          .select()
          .eq('set_id', seed.setIds.first);
      expect(
        events,
        hasLength(1),
        reason: 'record_set_xp must produce exactly one xp_events row',
      );
      final eventRow = (events as List).first as Map<String, dynamic>;
      final payload = eventRow['payload'] as Map<String, dynamic>;

      expect(
        (payload['effective_load'] as num).toDouble(),
        closeTo(bodyweight, 1e-9),
        reason:
            'payload.effective_load must equal bodyweight ($bodyweight) when '
            'entered weight is 0 and uses_bodyweight_load=TRUE. Got '
            '${payload['effective_load']}.',
      );
      expect(
        payload['bodyweight_used'],
        isTrue,
        reason:
            'payload.bodyweight_used must be true for a uses_bodyweight_load '
            'exercise regardless of entered weight.',
      );
      expect(
        (payload['volume_load'] as num).toDouble(),
        closeTo(bodyweight * reps, 1e-9),
        reason:
            'payload.volume_load must be re-derived from effective_load × '
            'reps ($bodyweight × $reps = ${bodyweight * reps}), NOT from '
            'entered weight. This is the bug Phase 24c fixes — without it, '
            'pure-bodyweight sets had volume_load=1.0 forever.',
      );

      // End-to-end: XpEvent.fromJson must promote payload.bodyweight_used
      // and payload.effective_load to top-level model fields. This validates
      // the Phase 24c-3 factory promotion against a real SQL-emitted row
      // (the 24c-3 unit tests cover synthetic rows; this exercises the
      // promotion against authentic migration 00057 output).
      final event = XpEvent.fromJson(eventRow);
      expect(
        event.bodyweightUsed,
        isTrue,
        reason:
            'XpEvent.bodyweightUsed must equal payload.bodyweight_used after '
            'the fromJson factory promotes the payload-nested key. If this '
            'fails, the 24c-3 promotion is broken end-to-end.',
      );
      expect(
        event.effectiveLoad,
        closeTo(bodyweight, 1e-9),
        reason:
            'XpEvent.effectiveLoad must equal payload.effective_load after '
            'fromJson promotion (live integration parity).',
      );
    });

    /// Weighted bodyweight: pull-up with a 20kg weight belt on a 70kg lifter.
    /// SQL CASE: effective_load = COALESCE(20, 0) + COALESCE(70, 0) = 90.
    /// volume_load = 90 × 8 = 720. Same flag semantics as scenario 1 — the
    /// bodyweight contribution applies on top of the entered (belt) weight.
    test('pull-up with bodyweight=70, weight=20 (belt-weighted): payload '
        'effective_load=90, volume_load=720, bodyweight_used=true', () async {
      const slug = 'pull_up';
      const enteredWeight = 20.0; // belt weight
      const reps = 8;
      const bodyweight = 70.0;
      const expectedEffective = enteredWeight + bodyweight; // 90.0

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      await adminClient.from('profiles').upsert({
        'id': user.userId,
        'bodyweight_kg': bodyweight,
      }, onConflict: 'id');

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: enteredWeight,
        reps: reps,
        numSets: 1,
      );
      await userClient.rpc(
        'record_set_xp',
        params: {'p_set_id': seed.setIds.first},
      );

      final events = await userClient
          .from('xp_events')
          .select()
          .eq('set_id', seed.setIds.first);
      expect(events, hasLength(1));
      final eventRow = (events as List).first as Map<String, dynamic>;
      final payload = eventRow['payload'] as Map<String, dynamic>;

      expect(
        (payload['effective_load'] as num).toDouble(),
        closeTo(expectedEffective, 1e-9),
        reason:
            'payload.effective_load must equal entered ($enteredWeight) + '
            'bodyweight ($bodyweight) = $expectedEffective for a '
            'uses_bodyweight_load exercise with both inputs non-null.',
      );
      expect(payload['bodyweight_used'], isTrue);
      expect(
        (payload['volume_load'] as num).toDouble(),
        closeTo(expectedEffective * reps, 1e-9),
        reason:
            'payload.volume_load must be re-derived from effective_load × '
            'reps ($expectedEffective × $reps = ${expectedEffective * reps}).',
      );

      final event = XpEvent.fromJson(eventRow);
      expect(event.bodyweightUsed, isTrue);
      expect(
        event.effectiveLoad,
        closeTo(expectedEffective, 1e-9),
        reason: 'XpEvent.effectiveLoad must promote to $expectedEffective.',
      );
    });

    /// Flag-off scenario: bench press has uses_bodyweight_load=FALSE per the
    /// curation in migration 00056, so the SQL CASE picks the ELSE branch:
    /// effective_load = COALESCE(weight, 0) = 80. The user's bodyweight is
    /// IGNORED — proves the flag (not the profile column) gates the
    /// behavior. Without this guard, every weighted exercise would
    /// double-count bodyweight, breaking 180 of the 200 default exercises.
    test('bench press with bodyweight=70, weight=80 (uses_bodyweight_load='
        'FALSE): payload effective_load=80, bodyweight_used=false (BW '
        'ignored)', () async {
      const slug = 'barbell_bench_press';
      const enteredWeight = 80.0;
      const reps = 5;
      const bodyweight = 70.0;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      // Set bodyweight even though bench press shouldn't use it — this is
      // the load-bearing case: a known bodyweight that MUST be ignored
      // because the exercise's flag is FALSE.
      await adminClient.from('profiles').upsert({
        'id': user.userId,
        'bodyweight_kg': bodyweight,
      }, onConflict: 'id');

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: enteredWeight,
        reps: reps,
        numSets: 1,
      );
      await userClient.rpc(
        'record_set_xp',
        params: {'p_set_id': seed.setIds.first},
      );

      // Sanity: bench is NOT in the curated 20-slug list.
      final usesBw = await bodyweightLoadForSlug(adminClient, slug);
      expect(
        usesBw,
        isFalse,
        reason:
            'barbell_bench_press must NOT be flagged uses_bodyweight_load. '
            'If this fails, the curation drifted to include barbells.',
      );

      final events = await userClient
          .from('xp_events')
          .select()
          .eq('set_id', seed.setIds.first);
      expect(events, hasLength(1));
      final eventRow = (events as List).first as Map<String, dynamic>;
      final payload = eventRow['payload'] as Map<String, dynamic>;

      expect(
        (payload['effective_load'] as num).toDouble(),
        closeTo(enteredWeight, 1e-9),
        reason:
            'payload.effective_load must equal entered weight only '
            '($enteredWeight) when uses_bodyweight_load=FALSE — bodyweight '
            'must be IGNORED. Got ${payload['effective_load']}; if this '
            'is 150 ($enteredWeight + $bodyweight), the SQL CASE branched '
            'incorrectly and every weighted exercise will double-count.',
      );
      expect(
        payload['bodyweight_used'],
        isFalse,
        reason:
            'payload.bodyweight_used must be false for a non-bodyweight '
            'exercise — the audit trail must reflect the flag, not the '
            'presence of the bodyweight value.',
      );
      expect(
        (payload['volume_load'] as num).toDouble(),
        closeTo(enteredWeight * reps, 1e-9),
        reason:
            'payload.volume_load = $enteredWeight × $reps = '
            '${enteredWeight * reps} (entered-only).',
      );

      final event = XpEvent.fromJson(eventRow);
      expect(event.bodyweightUsed, isFalse);
      expect(event.effectiveLoad, closeTo(enteredWeight, 1e-9));
    });

    /// Null-bodyweight graceful fallback: the user logs a weighted pull-up
    /// (entered = 20kg, e.g. with a belt or vest) but has NOT set their
    /// profile bodyweight. The SQL CASE WHEN branch fires (flag is TRUE)
    /// but COALESCE(NULL, 0) keeps the math defined: effective_load =
    /// COALESCE(20, 0) + COALESCE(NULL, 0) = 20. Critically,
    /// bodyweight_used STAYS true — the flag was on for this exercise,
    /// the profile data was just incomplete. This audit-trail clarity is
    /// what lets the Phase 24c-8 lazy prompt distinguish "user dismissed
    /// the prompt" from "exercise didn't qualify" downstream.
    test('pull-up with bodyweight=NULL, weight=20 (graceful fallback): '
        'payload effective_load=20, bodyweight_used=true (flag stays on '
        'even when value is missing)', () async {
      const slug = 'pull_up';
      const enteredWeight = 20.0;
      const reps = 8;

      final user = await freshUser();
      final adminClient = serviceRoleClient();
      final userClient = authenticatedClient(user);

      // Explicitly DO NOT upsert the profile — leave bodyweight_kg NULL.
      // (The auth trigger created the profiles row at user creation; we
      // need to make sure no lingering bodyweight slipped in. Force-clear
      // for safety in case a future fixture or trigger seeds one.)
      await adminClient.from('profiles').upsert({
        'id': user.userId,
        'bodyweight_kg': null,
      }, onConflict: 'id');

      final seed = await seedWorkout(
        adminClient: adminClient,
        userId: user.userId,
        exerciseSlug: slug,
        weightKg: enteredWeight,
        reps: reps,
        numSets: 1,
      );
      await userClient.rpc(
        'record_set_xp',
        params: {'p_set_id': seed.setIds.first},
      );

      final events = await userClient
          .from('xp_events')
          .select()
          .eq('set_id', seed.setIds.first);
      expect(events, hasLength(1));
      final eventRow = (events as List).first as Map<String, dynamic>;
      final payload = eventRow['payload'] as Map<String, dynamic>;

      expect(
        (payload['effective_load'] as num).toDouble(),
        closeTo(enteredWeight, 1e-9),
        reason:
            'payload.effective_load must gracefully degrade to entered '
            'weight ($enteredWeight) when bodyweight_kg is NULL. The '
            'COALESCE(NULL, 0) in the CASE WHEN branch produces 0 + 20 = '
            '20, which preserves volume_load math without poisoning the '
            'multiplication chain. Got ${payload['effective_load']}.',
      );
      expect(
        payload['bodyweight_used'],
        isTrue,
        reason:
            'payload.bodyweight_used MUST stay true even when bodyweight '
            'value is NULL — the flag tracks the EXERCISE, not the '
            'profile data. Audit trails must distinguish "this exercise '
            'qualifies for bodyweight loading but the user has not set '
            'their bodyweight yet" from "this exercise does not use '
            'bodyweight loading at all". Confusing the two would let the '
            'Phase 24c-8 lazy prompt fire on bench press sets.',
      );
      expect(
        (payload['volume_load'] as num).toDouble(),
        closeTo(enteredWeight * reps, 1e-9),
        reason:
            'payload.volume_load = effective_load × reps = $enteredWeight '
            '× $reps = ${enteredWeight * reps} (graceful-fallback path).',
      );

      final event = XpEvent.fromJson(eventRow);
      expect(
        event.bodyweightUsed,
        isTrue,
        reason:
            'XpEvent.bodyweightUsed must promote to true even on the '
            'NULL-bodyweight path — the SQL emits true, the model must '
            'reflect it. The Phase 24c-8 prompt logic depends on this.',
      );
      expect(event.effectiveLoad, closeTo(enteredWeight, 1e-9));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Phase 29 v2 parity oracle: compute the same `implied_tier` the SQL
/// `record_set_xp` chain derives for a freshly-seeded integration set.
///
/// The seed helpers ([seedWorkout]) NEVER set `profiles.bodyweight_kg` or
/// `profiles.gender`, so the SQL pre-fetch reads NULL for both. The PL/pgSQL
/// `rpg_implied_tier_for_exercise` short-circuits to the
/// `kBodyweightZeroFallback` (15.0) when `p_bw IS NULL OR p_bw <= 0` —
/// regardless of weight/reps/exercise. The Dart [impliedTier] mirrors this
/// with the identical `bodyweightKg <= 0` branch, so passing
/// `bodyweightKg: 0` reproduces the SQL value exactly (no theorizing — the
/// SQL function returns 15.0 for all three parity slugs, verified against the
/// live DB).
///
/// At a fresh user with no `body_part_progress` rows, the dominant-BP
/// `current_rank` defaults to 1 in the SQL. Together these feed the same
/// `tier_diff_mult` / `abs_strength_premium` the SQL applies — without them
/// the Dart oracle left both at the neutral 1.0 default and under-computed by
/// `tier_diff_mult(15, 1) ≈ 2.94×`.
double _seededImpliedTier(String slug, double weightKg, int reps) {
  // bodyweightKg: 0 → Dart impliedTier returns kBodyweightZeroFallback (15.0),
  // matching the SQL NULL-bodyweight fallback for the seeded fresh user.
  return impliedTier(
    exercise: slug,
    weightKg: weightKg,
    reps: reps,
    bodyweightKg: 0,
  );
}

/// Current rank for a freshly-seeded user's dominant body part: the SQL
/// defaults `v_current_rank` to 1 when no `body_part_progress` row exists.
const double _seededCurrentRank = 1.0;

Future<double> _readBodyPartXp(dynamic userClient, String bodyPart) async {
  final row = await (userClient as dynamic)
      .from('body_part_progress')
      .select('total_xp')
      .eq('body_part', bodyPart)
      .maybeSingle();
  if (row == null) return 0.0;
  return ((row as Map<String, dynamic>)['total_xp'] as num).toDouble();
}

/// Absolute XP tolerance for PG/Dart parity comparisons.
const double _kTol = 0.01;
