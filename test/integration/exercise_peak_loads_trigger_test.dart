/// Integration tests for the BEFORE-INSERT trigger installed by
/// `00051_peak_loads_multi_writer_guard.sql`.
///
/// Background — production crash on Galaxy S25 Ultra (May 2026):
/// `_rpg_backfill_chunk` (called from `RpgRepository.runBackfill()`) hit
/// `exercise_peak_loads_peak_weight_check` when iterating a user's bodyweight
/// history. The 00050 fix had patched `record_session_xp_batch` only, missing
/// the other two writers (`_rpg_backfill_chunk`, `record_set_xp`).
///
/// The architectural fix shipped in 00051: a BEFORE-INSERT-OR-UPDATE trigger
/// on `exercise_peak_loads` that silently drops rows where `peak_weight <= 0`
/// or `peak_reps <= 0`. This makes the constraint un-violable regardless of
/// which function attempts the write — including any future fourth writer
/// added by a later migration.
///
/// What these tests pin:
///
/// 1. INSERT with `peak_weight = 0` succeeds with zero rows in the table.
/// 2. INSERT with `peak_weight = 10` commits the row.
/// 3. Trigger fires on UPDATE too — bumping a real row's peak_weight to 0
///    silently drops the UPDATE.
/// 4. The trigger fires BEFORE the CHECK constraint, so we never see a 23514.
///
/// Requires local Supabase running: `npx supabase start`
/// Run: flutter test --tags integration test/integration/exercise_peak_loads_trigger_test.dart
@Tags(['integration'])
library;

// Direct table writes via the service-role client. The setup helpers expose
// `dynamic` Supabase types to keep admin/user client distinctions out of the
// production type surface; we follow the same convention here.
// ignore_for_file: avoid_dynamic_calls

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'rpg_integration_setup.dart';

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;

  TestUser? currentUser;
  late supabase.SupabaseClient admin;
  late String exerciseId;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('peak-trigger-$runId-$idx@test.local');
    currentUser = u;
    return u;
  }

  setUpAll(() async {
    admin = serviceRoleClient();
    // Use a real default exercise — slug 'plank' is bodyweight-shaped, but
    // the trigger doesn't care about exercise type, only about peak_weight
    // value. Any seeded exercise works.
    exerciseId = await exerciseIdForSlug(admin, 'barbell_bench_press');
  });

  tearDown(() async {
    if (currentUser != null) {
      // Wipe peak_loads rows for this user so a re-run starts clean.
      await admin
          .from('exercise_peak_loads')
          .delete()
          .eq('user_id', currentUser!.userId);
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  test('INSERT with peak_weight = 0 is silently dropped', () async {
    final user = await freshUser();

    // The INSERT should NOT throw a CHECK violation. The trigger drops the
    // row before constraint evaluation.
    await admin.from('exercise_peak_loads').insert({
      'user_id': user.userId,
      'exercise_id': exerciseId,
      'peak_weight': 0,
      'peak_reps': 5,
      'peak_date': DateTime.now().toUtc().toIso8601String(),
    });

    // Verify the row was NOT committed.
    final rows =
        await admin
                .from('exercise_peak_loads')
                .select()
                .eq('user_id', user.userId)
            as List<dynamic>;
    expect(
      rows,
      isEmpty,
      reason: 'Trigger should have suppressed the zero-weight INSERT.',
    );
  });

  test('INSERT with peak_weight > 0 commits the row', () async {
    final user = await freshUser();

    await admin.from('exercise_peak_loads').insert({
      'user_id': user.userId,
      'exercise_id': exerciseId,
      'peak_weight': 100,
      'peak_reps': 5,
      'peak_date': DateTime.now().toUtc().toIso8601String(),
    });

    final rows =
        await admin
                .from('exercise_peak_loads')
                .select()
                .eq('user_id', user.userId)
            as List<dynamic>;
    expect(rows, hasLength(1));
    final row = rows.single as Map<String, dynamic>;
    expect((row['peak_weight'] as num).toDouble(), 100);
    expect(row['peak_reps'], 5);
  });

  test('INSERT with peak_reps = 0 is silently dropped', () async {
    final user = await freshUser();

    // Defensive: peak_reps_check (peak_reps > 0) is the same family of bug.
    // Trigger guards both columns.
    await admin.from('exercise_peak_loads').insert({
      'user_id': user.userId,
      'exercise_id': exerciseId,
      'peak_weight': 100,
      'peak_reps': 0,
      'peak_date': DateTime.now().toUtc().toIso8601String(),
    });

    final rows =
        await admin
                .from('exercise_peak_loads')
                .select()
                .eq('user_id', user.userId)
            as List<dynamic>;
    expect(rows, isEmpty);
  });

  test('UPDATE that would set peak_weight to 0 is silently dropped', () async {
    final user = await freshUser();

    // Seed a real row first.
    await admin.from('exercise_peak_loads').insert({
      'user_id': user.userId,
      'exercise_id': exerciseId,
      'peak_weight': 100,
      'peak_reps': 5,
      'peak_date': DateTime.now().toUtc().toIso8601String(),
    });

    // Now attempt an UPDATE that would violate the CHECK. Trigger should
    // suppress without raising.
    await admin
        .from('exercise_peak_loads')
        .update({'peak_weight': 0})
        .eq('user_id', user.userId);

    // The original row's peak_weight should still be 100 — UPDATE was
    // dropped, no row mutated.
    final rows =
        await admin
                .from('exercise_peak_loads')
                .select()
                .eq('user_id', user.userId)
            as List<dynamic>;
    expect(rows, hasLength(1));
    final row = rows.single as Map<String, dynamic>;
    expect(
      (row['peak_weight'] as num).toDouble(),
      100,
      reason:
          'UPDATE to peak_weight=0 should have been suppressed by the '
          'trigger; original row stays intact at 100.',
    );
  });
}
