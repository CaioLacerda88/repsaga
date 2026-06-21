import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../../../core/data/json_helpers.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../rpg/models/body_part.dart';
import '../domain/weekly_engagement.dart';

/// Reads the per-body-part "done" set counts for the current week's
/// Engajamento view.
///
/// cluster: jsonb-payload-vs-typed-dart
///
/// **Why this repository exists.** The done-count query used to live inline in
/// `weeklyEngagementProvider` as a raw `Supabase.instance.client.from('sets')`
/// call followed by throwing `as Map<String, dynamic>` walks of the nested
/// JSONB join result — a true layering leak (`from()` outside a repository)
/// AND a latent crash: a single drifted/null nested object threw a raw
/// `_TypeError` that the provider had no `mapException` boundary to catch. The
/// `_TypeError` (a Dart `Error`, wrapped by `ErrorMapper` into a
/// `NetworkException` pre-fix) then defeated Riverpod's retry guard and the
/// provider stormed the default backoff. Routing through [mapException] +
/// [requireField]/[optionalField] turns any shape drift into a typed
/// [DatabaseException] with a field-bearing message, and the
/// `code: 'deserialization'` reclassification (see `app_retry.dart`) means the
/// failure surfaces immediately instead of retrying.
class WeeklyEngagementRepository extends BaseRepository {
  WeeklyEngagementRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  /// Per-body-part count of completed working sets for the week starting
  /// [mondayStr] (a `YYYY-MM-DD` date string), scoped to [userId].
  ///
  /// One round-trip: pulls every completed working set plus its exercise's
  /// `xp_attribution` / `muscle_group` for the week. Warm-up sets and
  /// zero-rep rows are skipped. Each surviving set credits one count to each
  /// body part returned by [primaryBodyPartsForSet].
  ///
  /// Rows whose nested join objects are absent are skipped (a set with no
  /// reachable exercise contributes nothing) — but a present-with-wrong-type
  /// field fails loudly via the json_helpers as a [DatabaseException], because
  /// that signals genuine schema drift, not "no data".
  Future<Map<BodyPart, int>> getDoneCounts({
    required String userId,
    required String mondayStr,
  }) {
    return mapException(() async {
      final doneRows = await _client
          .from('sets')
          .select('''
            is_completed,
            set_type,
            reps,
            workout_exercises!inner(
              workout_id,
              exercise:exercises!inner(xp_attribution, muscle_group),
              workouts!inner(user_id, finished_at)
            )
          ''')
          .eq('workout_exercises.workouts.user_id', userId)
          .gte('workout_exercises.workouts.finished_at', mondayStr)
          .eq('is_completed', true);

      final doneCounts = <BodyPart, int>{};
      for (final row in doneRows) {
        final r = _asRow(row);

        final setType = optionalField<String>(r, 'set_type') ?? 'working';
        if (setType != 'working') continue;
        final reps = optionalField<int>(r, 'reps');
        if (reps == null || reps < 1) continue;

        final we = optionalField<Map<String, dynamic>>(r, 'workout_exercises');
        if (we == null) continue;
        final ex = optionalField<Map<String, dynamic>>(we, 'exercise');
        if (ex == null) continue;

        final attrJson = optionalField<Map<String, dynamic>>(
          ex,
          'xp_attribution',
        );
        final primaryMuscle = optionalField<String>(ex, 'muscle_group');

        final Map<String, num> attrMap;
        if (attrJson != null && attrJson.isNotEmpty) {
          attrMap = _coerceAttribution(attrJson);
        } else if (primaryMuscle != null) {
          // `MuscleGroup.name` matches `BodyPart.dbValue` token-for-token;
          // fall back to a 100% primary-muscle attribution when the exercise
          // carries no xp_attribution JSON yet.
          attrMap = <String, num>{primaryMuscle: 1.0};
        } else {
          continue; // No attribution, no muscle_group — nothing to credit.
        }

        final winners = primaryBodyPartsForSet(attrMap);
        for (final bp in winners) {
          doneCounts[bp] = (doneCounts[bp] ?? 0) + 1;
        }
      }

      return doneCounts;
    });
  }

  /// Narrows a raw Supabase row to a typed JSON map, throwing a typed
  /// [DatabaseException] (not a raw `_TypeError`) if PostgREST ever returns a
  /// non-object row shape.
  static Map<String, dynamic> _asRow(Object? row) {
    if (row is Map<String, dynamic>) return row;
    throw DatabaseException(
      'Expected a JSON object row, got ${row.runtimeType}',
      code: 'deserialization',
    );
  }

  /// Coerces an `xp_attribution` JSONB map into `Map<String, num>`, failing
  /// loudly on a non-numeric share rather than throwing a raw cast error.
  static Map<String, num> _coerceAttribution(Map<String, dynamic> attrJson) {
    final out = <String, num>{};
    attrJson.forEach((key, value) {
      if (value is! num) {
        throw DatabaseException(
          "xp_attribution['$key'] has wrong type: expected num, "
          'got ${value.runtimeType}',
          code: 'deserialization',
        );
      }
      out[key] = value;
    });
    return out;
  }
}
