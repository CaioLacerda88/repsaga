import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../models/peak_load.dart';

/// Read gateway for `exercise_peak_loads`.
///
/// Peak loads are written exclusively by the `record_set_xp` RPC (live save
/// path) and the `_rpg_backfill_chunk` function (replay path). The repository
/// never writes — strength_mult depends on the monotonic invariant
/// (peak never decreases), and exposing a writer here would invite a UI
/// "edit your peak" flow that breaks the contract.
///
/// Used by:
///   * Future stats-deep-dive screen (Phase 18d) — list of (exercise → peak)
///     for the user's PR history.
///   * Test fixtures that need to assert peak advancement after a set.
class PeakLoadsRepository extends BaseRepository {
  PeakLoadsRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  /// All peak rows for the current user, optionally filtered to a single
  /// exercise.
  ///
  /// Returns an empty list for new users (no rows). RLS scopes to
  /// `user_id = auth.uid()`, so the caller doesn't pass the user id.
  Future<List<PeakLoad>> getPeakLoads({String? exerciseId}) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return const <PeakLoad>[];

      var query = _client.from('exercise_peak_loads').select();
      if (exerciseId != null) {
        query = query.eq('exercise_id', exerciseId);
      }
      final rows = await query.order('peak_date', ascending: false);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(PeakLoad.fromJson)
          .toList(growable: false);
    });
  }

  /// Single peak row for `(currentUser, exerciseId)`, or null if the user
  /// has never lifted that exercise.
  Future<PeakLoad?> getPeakLoad(String exerciseId) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final row = await _client
          .from('exercise_peak_loads')
          .select()
          .eq('exercise_id', exerciseId)
          .maybeSingle();

      if (row == null) return null;
      return PeakLoad.fromJson(row);
    });
  }

  /// Bulk lookup keyed by exercise id — the home screen and post-workout
  /// celebration both need to ask "is this set a PR?" against the prior
  /// peak. Single round-trip is cheaper than N maybeSingle() calls.
  Future<Map<String, PeakLoad>> getPeakLoadsByExerciseIds(
    List<String> exerciseIds,
  ) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null || exerciseIds.isEmpty) {
        return const <String, PeakLoad>{};
      }

      final rows = await _client
          .from('exercise_peak_loads')
          .select()
          .inFilter('exercise_id', exerciseIds);

      final out = <String, PeakLoad>{};
      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        final p = PeakLoad.fromJson(raw);
        out[p.exerciseId] = p;
      }
      return out;
    });
  }
}
