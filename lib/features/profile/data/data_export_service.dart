import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/exceptions/app_exception.dart';

/// Generates the LGPD Art. 18 V / GDPR Art. 20 portability JSON export for
/// a single user.
///
/// **Cluster: `data-protection-compliance`.** This service is the in-app
/// implementation of the Privacy Policy §6 Portability row — every
/// user-owned table that contains the user's personal or fitness data is
/// queried, denormalized, and emitted as a single pretty-printed JSON
/// document the user receives via the native share sheet.
///
/// **Tables included** (driven by the migration audit at PR #305 +
/// `supabase/migrations/*`):
///   * `profiles` (full row except deprecated columns — see §2 below)
///   * `workouts` (+ embedded `workout_exercises[]` + `sets[]`,
///     denormalized so the export is self-contained)
///   * `personal_records`
///   * `weekly_plans`
///   * `xp_events`
///   * `body_part_progress`
///   * `exercise_peak_loads`
///   * `exercise_peak_loads_by_rep_range`
///   * `earned_titles`
///   * `backfill_progress` (0-or-1 row)
///   * `vitality_runs`
///   * `analytics_events`
///   * `exercises` — slugs ONLY for exercises referenced by the user's
///     workouts (NOT the full default library — see §3 below)
///
/// **Tables intentionally excluded** (documented for future auditors):
///   1. `auth.users` raw row → only `id` + `email` surfaced at the top of
///      the JSON. The rest of `auth.users` is internal auth state (refresh
///      token, encrypted password, MFA factors, OAuth identity blobs) —
///      shipping it would leak credentials.
///   2. `account_deletion_events` → schema is deliberately untied to
///      `user_id` (anonymized aggregate post-delete row). No user-owned
///      data to export.
///   3. `subscriptions` + `subscription_events` → Launch Phase paywall
///      tables. No rows for any user yet. Include when paywall ships.
///   4. Deprecated `profiles` columns dropped by prior migrations (none
///      currently — placeholder for future cleanups).
///
/// **Exercise library scoping (§3 above).** The `exercises` table holds
/// the default library (~80 rows shipped with the migration cascade) plus
/// any user-created custom exercises. Exporting the full default library
/// would balloon the JSON with content the user did not generate. The
/// service instead collects the distinct `exercise_id` set from the user's
/// `workout_exercises` rows, fetches matching `exercises` rows scoped
/// to that ID list, and emits `{slug, userCreated}` per match. Restoring
/// the export elsewhere requires the operator to look up the slug in their
/// own copy of the exercise library — which is the intended semantic for
/// portability (the user's DATA, not the app's content).
class DataExportService {
  DataExportService(this._client, {Clock? clock})
    : _clock = clock ?? const Clock();

  final supabase.SupabaseClient _client;

  /// Injectable clock so unit tests can pin `exportedAt` deterministically.
  /// Production callers omit and get the default wall clock.
  final Clock _clock;

  /// Pinned to the schema-version contract baked into the JSON envelope.
  /// Bump when the export shape changes in a non-backwards-compatible way
  /// (new top-level keys are NOT a breaking change; renaming or removing
  /// keys is). External tools parsing the export branch on this field.
  static const int schemaVersion = 1;

  /// Public entry point. Returns the pretty-printed JSON string with
  /// 2-space indentation (human-readable; the user receives a file they
  /// can open in any text editor).
  ///
  /// Throws [ExportException] on any fetch / serialize failure. The
  /// underlying cause is preserved on [ExportException.cause] for dev
  /// logging while the user-facing snackbar reads
  /// [ExportException.userMessage].
  Future<String> buildJsonExport(String userId) async {
    final user = _client.auth.currentUser;
    final email = user?.email;

    // Each fetch is wrapped in its own stage so a failure points at the
    // exact table that broke. The dev log captures stage + raw cause; the
    // caller sees only ExportException.userMessage.
    final profile = await _fetch('profile', () => _fetchProfile(userId));
    final workouts = await _fetch(
      'workouts',
      () => _fetchWorkoutsWithChildren(userId),
    );
    final personalRecords = await _fetch(
      'personal_records',
      () => _fetchPersonalRecords(userId),
    );
    final weeklyPlans = await _fetch(
      'weekly_plans',
      () => _fetchWeeklyPlans(userId),
    );
    final xpEvents = await _fetch('xp_events', () => _fetchXpEvents(userId));
    final bodyPartProgress = await _fetch(
      'body_part_progress',
      () => _fetchBodyPartProgress(userId),
    );
    final exercisePeakLoads = await _fetch(
      'exercise_peak_loads',
      () => _fetchExercisePeakLoads(userId),
    );
    final exercisePeakLoadsByRepRange = await _fetch(
      'exercise_peak_loads_by_rep_range',
      () => _fetchExercisePeakLoadsByRepRange(userId),
    );
    final earnedTitles = await _fetch(
      'earned_titles',
      () => _fetchEarnedTitles(userId),
    );
    final backfillProgress = await _fetch(
      'backfill_progress',
      () => _fetchBackfillProgress(userId),
    );
    final vitalityRuns = await _fetch(
      'vitality_runs',
      () => _fetchVitalityRuns(userId),
    );
    final analyticsEvents = await _fetch(
      'analytics_events',
      () => _fetchAnalyticsEvents(userId),
    );

    // Derive the referenced exercise slug set FROM the just-fetched
    // workouts payload so we make exactly ONE more round trip regardless
    // of history depth. Distinct ids → single `inFilter` against
    // `exercises`. The result is shaped as `{slug, userCreated}` per match.
    final referencedExerciseIds = _collectExerciseIds(workouts);
    final exercises = await _fetch(
      'exercises',
      () => _fetchReferencedExercises(referencedExerciseIds),
    );

    final envelope = <String, dynamic>{
      'exportedAt': _clock.now().toUtc().toIso8601String(),
      'schemaVersion': schemaVersion,
      'user': <String, dynamic>{'id': userId, 'email': email},
      'profile': profile,
      'workouts': workouts,
      'personalRecords': personalRecords,
      'exercises': exercises,
      'weeklyPlans': weeklyPlans,
      'xpEvents': xpEvents,
      'bodyPartProgress': bodyPartProgress,
      'exercisePeakLoads': exercisePeakLoads,
      'exercisePeakLoadsByRepRange': exercisePeakLoadsByRepRange,
      'earnedTitles': earnedTitles,
      'backfillProgress': backfillProgress,
      'vitalityRuns': vitalityRuns,
      'analyticsEvents': analyticsEvents,
    };

    try {
      return const JsonEncoder.withIndent('  ').convert(envelope);
    } catch (e, st) {
      debugPrint('[DataExportService] serialize failed: $e\n$st');
      throw ExportException(
        'jsonEncode failed: $e',
        stage: 'serialize',
        cause: e,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Per-table fetchers — each returns a JSON-serializable payload (Map / List)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// Denormalize workouts → embedded `workoutExercises[]` → embedded `sets[]`.
  /// Single PostgREST select with nested embeds matches the existing
  /// `WorkoutRepository.getWorkoutDetail` shape so the JSON output mirrors
  /// what the app reads internally.
  Future<List<Map<String, dynamic>>> _fetchWorkoutsWithChildren(
    String userId,
  ) async {
    final data = await _client
        .from('workouts')
        .select('*, workout_exercises(*, sets(*))')
        .eq('user_id', userId)
        .order('started_at', ascending: true);

    return [
      for (final row in data as List)
        _renameNestedKey(
          Map<String, dynamic>.from(row as Map<String, dynamic>),
          oldKey: 'workout_exercises',
          newKey: 'workoutExercises',
        ),
    ];
  }

  Future<List<Map<String, dynamic>>> _fetchPersonalRecords(
    String userId,
  ) async {
    final data = await _client
        .from('personal_records')
        .select()
        .eq('user_id', userId)
        .order('achieved_at', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchWeeklyPlans(String userId) async {
    final data = await _client
        .from('weekly_plans')
        .select()
        .eq('user_id', userId)
        .order('week_start', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchXpEvents(String userId) async {
    final data = await _client
        .from('xp_events')
        .select()
        .eq('user_id', userId)
        .order('occurred_at', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchBodyPartProgress(
    String userId,
  ) async {
    final data = await _client
        .from('body_part_progress')
        .select()
        .eq('user_id', userId)
        .order('body_part', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchExercisePeakLoads(
    String userId,
  ) async {
    final data = await _client
        .from('exercise_peak_loads')
        .select()
        .eq('user_id', userId)
        .order('peak_date', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchExercisePeakLoadsByRepRange(
    String userId,
  ) async {
    final data = await _client
        .from('exercise_peak_loads_by_rep_range')
        .select()
        .eq('user_id', userId)
        .order('exercise_slug', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchEarnedTitles(String userId) async {
    final data = await _client
        .from('earned_titles')
        .select()
        .eq('user_id', userId)
        .order('earned_at', ascending: true);
    return _castList(data);
  }

  /// `backfill_progress` PK is `user_id` → at most one row. Returned as a
  /// list (potentially empty) so the JSON shape matches the other
  /// collections — the user can treat every top-level array uniformly.
  Future<List<Map<String, dynamic>>> _fetchBackfillProgress(
    String userId,
  ) async {
    final row = await _client
        .from('backfill_progress')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? const [] : [Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> _fetchVitalityRuns(String userId) async {
    final data = await _client
        .from('vitality_runs')
        .select()
        .eq('user_id', userId)
        .order('run_date', ascending: true);
    return _castList(data);
  }

  Future<List<Map<String, dynamic>>> _fetchAnalyticsEvents(
    String userId,
  ) async {
    final data = await _client
        .from('analytics_events')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return _castList(data);
  }

  /// Fetch the slug + `is_default` flag for exactly the exercise IDs
  /// referenced by the user's workout_exercises rows. Empty ids set
  /// short-circuits to the empty list (no round trip).
  ///
  /// Emits `{slug, userCreated}` per row where `userCreated == !is_default`.
  /// The default library is intentionally NOT exported — see class
  /// docstring §3.
  Future<List<Map<String, dynamic>>> _fetchReferencedExercises(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final data = await _client
        .from('exercises')
        .select('slug, is_default')
        .inFilter('id', ids.toList());
    return [
      for (final row in data as List)
        <String, dynamic>{
          'slug': (row as Map<String, dynamic>)['slug'],
          'userCreated': !((row['is_default'] as bool?) ?? true),
        },
    ];
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Runs [action] inside a stage-tagged try/catch. Any failure is
  /// translated to [ExportException] with the [stage] label so the dev
  /// log + Sentry breadcrumb pinpoint which table broke without leaking
  /// the raw error to the UI.
  Future<T> _fetch<T>(String stage, Future<T> Function() action) async {
    try {
      return await action();
    } on ExportException {
      // Already wrapped — rethrow without double-wrapping.
      rethrow;
    } catch (e, st) {
      debugPrint('[DataExportService] $stage failed: $e\n$st');
      throw ExportException('$stage fetch failed: $e', stage: stage, cause: e);
    }
  }

  /// Cast a Supabase `select()` response to a List of maps. Hoisted so
  /// every fetcher above gets the same cast shape and a future swap to a
  /// more strict cast (e.g. `requireField`) lands in one place.
  static List<Map<String, dynamic>> _castList(dynamic data) {
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map<String, dynamic>))
        .toList();
  }

  /// Walks the workouts list (already shaped with `workoutExercises[]`)
  /// and collects every distinct `exercise_id` referenced. Used to scope
  /// the `exercises` slug emit to ONLY the rows the user's data depends on
  /// — keeps the export from shipping the full default library.
  static Set<String> _collectExerciseIds(List<Map<String, dynamic>> workouts) {
    final ids = <String>{};
    for (final workout in workouts) {
      final wes = workout['workoutExercises'] as List<dynamic>?;
      if (wes == null) continue;
      for (final we in wes) {
        final id = (we as Map<String, dynamic>)['exercise_id'];
        if (id is String) ids.add(id);
      }
    }
    return ids;
  }

  /// PostgREST embeds nested rows under the SQL column name
  /// (`workout_exercises`). The export envelope uses camelCase top-level
  /// keys for consistency with the surrounding `exportedAt` /
  /// `schemaVersion` shape; this helper renames the nested embed key
  /// without rebuilding the whole map.
  static Map<String, dynamic> _renameNestedKey(
    Map<String, dynamic> row, {
    required String oldKey,
    required String newKey,
  }) {
    if (!row.containsKey(oldKey)) return row;
    final value = row.remove(oldKey);
    row[newKey] = value;
    return row;
  }
}
