import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../../../core/exceptions/app_exception.dart' as app;
import '../../../core/local_storage/cache_service.dart';
import '../../../core/local_storage/hive_service.dart';
import '../../exercises/data/exercise_repository.dart';
import '../../exercises/models/exercise.dart';
import '../models/exercise_set.dart';
import '../models/workout.dart';
import '../models/workout_exercise.dart';

/// Parsed workout detail with exercises and sets.
typedef WorkoutDetail = ({
  Workout workout,
  List<WorkoutExercise> exercises,
  Map<String, List<ExerciseSet>> setsByExercise,
});

/// Workout reads + saves.
///
/// **Phase 15f Stage 6 contract:**
/// History/detail queries no longer embed `exercise:exercises(name)` /
/// `exercise:exercises(*)` — those columns were dropped in migration 00034.
/// Instead, the repo fetches workout shape (with `workout_exercises.exercise_id`
/// only) and resolves localized exercise data via [ExerciseRepository.getExercisesByIds]
/// in a single follow-up RPC. This is a two-query merge, not N+1: one workouts
/// query + one batch RPC per `getWorkoutHistory` / `getWorkoutDetail` call.
///
/// Cache keys for history are now `'<userId>:<locale>'` so en and pt entries
/// coexist; [LocaleNotifier.setLocale] also clears the box on switch.
class WorkoutRepository extends BaseRepository {
  WorkoutRepository(
    this._client,
    this._cache,
    this._exerciseRepo, {
    super.recoveryRecorder,
  });

  final supabase.SupabaseClient _client;
  final CacheService _cache;
  final ExerciseRepository _exerciseRepo;

  supabase.SupabaseQueryBuilder get _workouts => _client.from('workouts');

  /// Explicit timeout on the `save_workout` RPC.
  ///
  /// Without this, a hung connection would sit on whatever HTTP default
  /// the supabase client carries (effectively unbounded for connect-stalled
  /// requests on some platforms), and the user would stare at the loading
  /// overlay forever — only the overlay's 10s Cancel button gives a way out
  /// (AW-EX-D-US1-04). 30s is the upper bound we accept; beyond that the
  /// `TimeoutException` is classified as transient by [SyncErrorClassifier]
  /// and the notifier's catch site enqueues the workout for offline sync.
  static const _saveWorkoutTimeout = Duration(seconds: 30);

  /// Atomically save a finished workout via the save_workout RPC.
  ///
  /// Supabase wraps each RPC call in a transaction, so all inserts/updates
  /// are atomic — a constraint violation rolls back the entire operation.
  ///
  /// Throws [TimeoutException] after [_saveWorkoutTimeout] to compose with
  /// the active-workout notifier's catch-site classifier — see AW-EX-D-US1-04.
  Future<Workout> saveWorkout({
    required Workout workout,
    required List<WorkoutExercise> exercises,
    required List<ExerciseSet> sets,
    String? routineId,
  }) {
    return mapException(() async {
      final result = await _client
          .rpc(
            'save_workout',
            params: {
              'p_workout': {
                'id': workout.id,
                'user_id': workout.userId,
                'name': workout.name,
                'finished_at': workout.finishedAt?.toIso8601String(),
                'duration_seconds': workout.durationSeconds,
                'notes': workout.notes,
                // 26e: drives bucket find-or-create in 00063 save_workout RPC.
                // Null for free workouts (no source routine) → RPC treats
                // as spontaneous-append candidate; NULLIF on the SQL side
                // handles missing key + empty string + valid uuid.
                'routine_id': routineId,
              },
              'p_exercises': exercises
                  .map(
                    (e) => {
                      'id': e.id,
                      'workout_id': e.workoutId,
                      'exercise_id': e.exerciseId,
                      'order': e.order,
                      'rest_seconds': e.restSeconds,
                    },
                  )
                  .toList(),
              'p_sets': sets.map((s) => s.toRpcJson()).toList(),
            },
          )
          .timeout(_saveWorkoutTimeout);
      // Defensive null-guard (BUG-004): Postgrest can return `null` for RPCs
      // that hit a `RAISE EXCEPTION` inside a `DO` block or partial-commit
      // error paths. Without this check the cast throws the cryptic
      // "type 'Null' is not a subtype of type 'String' in type cast" error
      // that surfaced on a Galaxy S25 Ultra. We translate to a typed
      // domain exception so the offline-queue retry loop and the UI's
      // sync-error mapper can classify it.
      if (result is! Map<String, dynamic>) {
        // RPC name kept in message for diagnostic logs/Sentry; never reaches
        // UI (sanitized by SyncErrorMapper to a generic localized retry).
        throw const app.DatabaseException(
          'save_workout RPC returned null',
          code: 'rpc_null_result',
        );
      }
      final saved = Workout.fromJson(result);
      // History cache is locale-prefixed (`'<userId>:<locale>'`); after a
      // save we evict every locale entry — the heavy hand is fine here
      // (rare event, single-user devices in practice). Same applies to
      // last-sets which doesn't carry locale.
      _cache.clearBox(HiveService.workoutHistoryCache);
      _cache.clearBox(HiveService.lastSetsCache);
      return saved;
    });
  }

  /// Evict workout history and last-sets caches.
  ///
  /// Called by the notifier when a workout is saved offline — the repository's
  /// own saveWorkout() handles eviction on the online path, but when the RPC
  /// fails the notifier needs to evict manually.
  ///
  /// Clears the entire history box because keys are now `'<userId>:<locale>'`
  /// and a save invalidates every locale entry for that user (the box is
  /// scoped per device, not per user, so the heavy hand is acceptable).
  void evictHistoryCaches(String userId) {
    _cache.clearBox(HiveService.workoutHistoryCache);
    _cache.clearBox(HiveService.lastSetsCache);
  }

  /// Create a new active workout (start of a session).
  Future<Workout> createActiveWorkout({
    required String userId,
    required String name,
  }) {
    return mapException(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      final data = await _workouts
          .insert({
            'user_id': userId,
            'name': name,
            'started_at': now,
            'is_active': true,
          })
          .select()
          .single();
      return Workout.fromJson(data);
    });
  }

  /// Get the user's currently active workout, if any.
  Future<Workout?> getActiveWorkout(String userId) {
    return mapException(() async {
      final data = await _workouts
          .select()
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();
      if (data == null) return null;
      return Workout.fromJson(data);
    });
  }

  /// Get paginated workout history (finished workouts only).
  ///
  /// Two-query merge: first calls the Phase 32 PR 32f
  /// `get_workout_history_with_aggregates` RPC which returns workouts +
  /// their `workout_exercises` `(order, exercise_id)` rows + `total_xp` +
  /// `pr_count` aggregates, then batch-fetches localized exercise names
  /// via [ExerciseRepository.getExercisesByIds] and rebuilds
  /// [Workout.exerciseSummary] (e.g. "Bench Press, Squat +2") in the
  /// requested [locale].
  ///
  /// Only the first page (`offset == 0`) is cached, up to 50 workouts. The
  /// cache key is `'<userId>:<locale>'` so an `en` and `pt` cache coexist.
  Future<List<Workout>> getWorkoutHistory(
    String userId, {
    required String locale,
    int limit = 20,
    int offset = 0,
  }) async {
    // Only cache from the refresh pass (limit >= 50) to avoid a UI fetch
    // (limit 20) regressing a richer 50-item cache entry.
    final shouldCache = offset == 0 && limit >= 50;
    final cacheKey = '$userId:$locale';

    final cached = shouldCache
        ? _cache.read<List<Workout>>(
            HiveService.workoutHistoryCache,
            cacheKey,
            (json) {
              final list = json as List;
              return list.map((e) {
                final map = Map<String, dynamic>.from(
                  e as Map<String, dynamic>,
                );
                final summary = map.remove('_exercise_summary') as String?;
                final workout = Workout.fromJson(map);
                return summary != null
                    ? workout.copyWith(exerciseSummary: summary)
                    : workout;
              }).toList();
            },
          )
        : null;

    try {
      final fresh = await mapException(() async {
        // Step 1: workout shape with exercise IDs + XP/PR aggregates via
        // the Phase 32 PR 32f RPC. Single round-trip per page; LEFT JOIN
        // with COALESCE on the SQL side guarantees `total_xp` /
        // `pr_count` are non-null integers, and `workout_exercises` is
        // always at least `[]` so the existing name-resolution loop below
        // never sees a null payload.
        final result = await _client.rpc(
          'get_workout_history_with_aggregates',
          params: {'p_user_id': userId, 'p_limit': limit, 'p_offset': offset},
        );
        // Defensive type guard (mirrors saveWorkout's BUG-004 pattern at
        // L112-119): an RPC that hits an unhandled error path may return
        // null or a non-list payload. A raw `as List<dynamic>` cast would
        // surface as a native `_TypeError` and bypass `mapException`'s
        // domain-error translation, leaving the cache-fallback branch in
        // an inconsistent state. We translate to a typed
        // `DatabaseException` here so the surrounding `mapException`
        // wrapper keeps the layer contract intact. See PR #285 Important 6.
        if (result is! List) {
          throw const app.DatabaseException(
            'get_workout_history_with_aggregates RPC returned unexpected type',
            code: 'rpc_unexpected_type',
          );
        }
        final data = result.cast<Map<String, dynamic>>();

        // Step 2: collect distinct exercise IDs across all workouts in
        // the page and batch-fetch their localized names. One RPC call,
        // regardless of page size or how many distinct exercises appear.
        final ids = <String>{};
        for (final row in data) {
          final wes = (row['workout_exercises'] as List<dynamic>?) ?? const [];
          for (final we in wes) {
            final id = (we as Map<String, dynamic>)['exercise_id'] as String?;
            if (id != null) ids.add(id);
          }
        }
        final exerciseMap = await _exerciseRepo.getExercisesByIds(
          locale: locale,
          userId: userId,
          ids: ids.toList(),
        );
        final namesById = <String, String>{
          for (final entry in exerciseMap.entries) entry.key: entry.value.name,
        };

        return data
            .map((row) => _workoutFromHistoryRow(row, namesById))
            .toList();
      });

      if (shouldCache) {
        // Cache up to 50 workouts with exerciseSummary preserved.
        final toCache = fresh.take(50).toList();
        _cache.write(
          HiveService.workoutHistoryCache,
          cacheKey,
          toCache.map((w) {
            final json = w.toJson();
            if (w.exerciseSummary != null) {
              json['_exercise_summary'] = w.exerciseSummary;
            }
            return json;
          }).toList(),
        );
      }

      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Maps a history query row (with joined workout_exercises) to a [Workout]
  /// with [Workout.exerciseSummary] populated using the supplied [namesById]
  /// lookup (locale-resolved by the batch RPC).
  static Workout _workoutFromHistoryRow(
    Map<String, dynamic> row,
    Map<String, String> namesById,
  ) {
    final workout = Workout.fromJson(row);
    final summary = buildExerciseSummary(
      (row['workout_exercises'] as List<dynamic>?) ?? const [],
      namesById,
    );
    return workout.copyWith(exerciseSummary: summary.isEmpty ? null : summary);
  }

  /// Builds a summary string like "Bench Press, Squat, Deadlift +2" from
  /// a list of `workout_exercises` rows that each contain `order` and
  /// `exercise_id`. Names are resolved from the supplied [namesById] map
  /// (typically produced by [ExerciseRepository.getExercisesByIds] in the
  /// active locale).
  ///
  /// Rows with an exercise_id missing from [namesById] are skipped — that
  /// happens when the referenced exercise was soft-deleted or is foreign-
  /// owned. Exercises are sorted by their `order` field before naming.
  static String buildExerciseSummary(
    List<dynamic> workoutExercises,
    Map<String, String> namesById,
  ) {
    if (workoutExercises.isEmpty) return '';

    // Sort by `order` to list exercises in the order they were performed.
    final sorted = [...workoutExercises]
      ..sort((a, b) {
        final aOrder = (a as Map<String, dynamic>)['order'] as int? ?? 0;
        final bOrder = (b as Map<String, dynamic>)['order'] as int? ?? 0;
        return aOrder.compareTo(bOrder);
      });

    // Collect exercise names by looking up each row's exercise_id in the
    // locale-resolved map. Missing entries (soft-deleted / foreign-owned
    // exercises) are silently skipped.
    final names = <String>[];
    for (final item in sorted) {
      final exerciseId =
          (item as Map<String, dynamic>)['exercise_id'] as String?;
      if (exerciseId == null) continue;
      final name = namesById[exerciseId];
      if (name != null && name.isNotEmpty) names.add(name);
    }

    if (names.isEmpty) return '';

    const maxShown = 3;
    if (names.length <= maxShown) return names.join(', ');

    final shown = names.take(maxShown).join(', ');
    final remaining = names.length - maxShown;
    return '$shown +$remaining';
  }

  /// Get full workout detail with exercises and sets, parsed into typed data.
  ///
  /// Two-query merge: pulls workout + `workout_exercises` (with sets, no
  /// embedded exercise) in one query, then resolves localized exercise
  /// data via [ExerciseRepository.getExercisesByIds] in [locale]. The
  /// resulting [WorkoutExercise.exercise] field is populated post-hoc
  /// for each row whose `exercise_id` is present in the batch result.
  Future<WorkoutDetail> getWorkoutDetail(
    String workoutId, {
    required String userId,
    required String locale,
  }) {
    return mapException(() async {
      final data = await _workouts
          .select('*, workout_exercises(*, sets(*))')
          .eq('id', workoutId)
          .single();
      final wes = (data['workout_exercises'] as List<dynamic>?) ?? const [];
      final ids = <String>{
        for (final we in wes)
          if ((we as Map<String, dynamic>)['exercise_id'] != null)
            we['exercise_id'] as String,
      };
      final exerciseMap = await _exerciseRepo.getExercisesByIds(
        locale: locale,
        userId: userId,
        ids: ids.toList(),
      );

      // Phase 32 PR 32f: enrich the detail Workout with `totalXp` +
      // `prCount` via the `get_workout_xp` helper RPC. Powers the new 48dp
      // summary strip without forcing the detail fetch through the bulkier
      // history-aggregate RPC. LEFT JOIN + COALESCE on the SQL side
      // guarantees non-null integers; on an unexpected null we fall back
      // to 0 so the strip renders the zero-state cleanly.
      final xpResult = await _client.rpc(
        'get_workout_xp',
        params: {'p_workout_id': workoutId},
      );
      final xpRow = (xpResult is List && xpResult.isNotEmpty)
          ? xpResult.first as Map<String, dynamic>
          : const <String, dynamic>{};
      final totalXp = (xpRow['total_xp'] as int?) ?? 0;
      final prCount = (xpRow['pr_count'] as int?) ?? 0;

      final detail = parseWorkoutDetail(data, exerciseMap);
      return (
        workout: detail.workout.copyWith(totalXp: totalXp, prCount: prCount),
        exercises: detail.exercises,
        setsByExercise: detail.setsByExercise,
      );
    });
  }

  /// One row in the per-exercise progress query.
  ///
  /// Returned in `finished_at` order (ascending). The chart provider buckets
  /// these per user-local calendar date and selects the max completed
  /// working-set weight per bucket.
  ///
  /// [finishedAt] — UTC timestamp from `workouts.finished_at`.
  /// [sets] — raw sets from `workout_exercises.sets` (unfiltered; the
  /// `isCompletedWorkingSet` predicate is applied client-side so the filter
  /// logic stays co-located with PR detection).
  static List<({DateTime finishedAt, List<ExerciseSet> sets})>
  _parseExerciseHistoryRows(List<dynamic> rows) {
    final result = <({DateTime finishedAt, List<ExerciseSet> sets})>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final workout = map['workouts'] as Map<String, dynamic>?;
      final finishedAtStr = workout?['finished_at'] as String?;
      if (finishedAtStr == null) continue;
      final finishedAt = DateTime.parse(finishedAtStr);
      final setsData = map['sets'] as List<dynamic>? ?? [];
      final sets = setsData
          .map((s) => ExerciseSet.fromJson(s as Map<String, dynamic>))
          .toList();
      result.add((finishedAt: finishedAt, sets: sets));
    }
    return result;
  }

  /// Fetch finished-workout history for a single [exerciseId] belonging to
  /// [userId].
  ///
  /// Returns one entry per `workout_exercises` row (one per session that
  /// logged this exercise), sorted ascending by `workouts.finished_at`.
  /// When [since] is non-null, only sessions finished on or after [since]
  /// are returned (used for the 90-day window).
  ///
  /// RLS-scoped to the current user via `workouts.user_id = userId`. The
  /// explicit `.eq('user_id', userId)` on the inner-joined workouts table
  /// provides defence-in-depth — Supabase RLS is the hard guarantee.
  Future<List<({DateTime finishedAt, List<ExerciseSet> sets})>>
  getExerciseHistory(
    String exerciseId, {
    required String userId,
    DateTime? since,
  }) {
    return mapException(() async {
      var query = _client
          .from('workout_exercises')
          .select('sets(*), workouts!inner(finished_at, user_id, is_active)')
          .eq('exercise_id', exerciseId)
          .eq('workouts.user_id', userId)
          .eq('workouts.is_active', false)
          .not('workouts.finished_at', 'is', null);

      if (since != null) {
        query = query.gte('workouts.finished_at', since.toIso8601String());
      }

      final data = await query.order(
        'finished_at',
        referencedTable: 'workouts',
        ascending: true,
      );

      return _parseExerciseHistoryRows(data);
    });
  }

  /// Batch-fetch the most recent completed sets for given exercise IDs.
  /// Returns a map of exerciseId -> list of sets from the last workout.
  ///
  /// Note: relies on Supabase returning rows ordered by the `finished_at DESC`
  /// clause. The `seen` set deduplicates to keep only the first (most recent)
  /// entry per exercise.
  ///
  /// Uses read-through caching: returns cached data on network failure.
  Future<Map<String, List<ExerciseSet>>> getLastWorkoutSets(
    List<String> exerciseIds,
  ) async {
    if (exerciseIds.isEmpty) return {};

    final key = (List<String>.from(exerciseIds)..sort()).join(',');
    final cached = _cache.read<Map<String, List<ExerciseSet>>>(
      HiveService.lastSetsCache,
      key,
      (json) {
        final map = json as Map<String, dynamic>;
        return map.map(
          (k, v) => MapEntry(
            k,
            (v as List)
                .map((e) => ExerciseSet.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
        );
      },
    );

    try {
      final fresh = await mapException(() async {
        final data = await _client
            .from('workout_exercises')
            .select('exercise_id, sets(*), workouts!inner(finished_at)')
            .inFilter('exercise_id', exerciseIds)
            .not('workouts.finished_at', 'is', null)
            .order(
              'finished_at',
              referencedTable: 'workouts',
              ascending: false,
            );

        final result = <String, List<ExerciseSet>>{};
        final seen = <String>{};

        for (final row in data) {
          final exerciseId = row['exercise_id'] as String;
          if (seen.contains(exerciseId)) continue;
          seen.add(exerciseId);

          final setsData = row['sets'] as List<dynamic>? ?? [];
          result[exerciseId] = setsData
              .map((s) => ExerciseSet.fromJson(s as Map<String, dynamic>))
              .toList();
        }
        return result;
      });

      // Fire-and-forget cache write.
      _cache.write(
        HiveService.lastSetsCache,
        key,
        fresh.map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())),
      );

      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Get the total count of finished workouts for a user.
  ///
  /// On success the count is cached to `user_prefs` so it can be read
  /// offline via [getCachedWorkoutCount].
  Future<int> getFinishedWorkoutCount(String userId) {
    return mapException(() async {
      final result = await _workouts
          .select()
          .eq('user_id', userId)
          .eq('is_active', false)
          .not('finished_at', 'is', null)
          .count(supabase.CountOption.exact);
      final count = result.count;
      _cache.write(
        HiveService.userPrefs,
        'finished_workout_count:$userId',
        count,
      );
      return count;
    });
  }

  /// Read the last-known finished workout count from cache.
  ///
  /// Returns `null` when no cached value exists.
  int? getCachedWorkoutCount(String userId) {
    return _cache.read<int>(
      HiveService.userPrefs,
      'finished_workout_count:$userId',
      (json) => json as int,
    );
  }

  /// Increment the cached workout count by 1.
  ///
  /// Used after an offline save so the next PR detection has a reasonable
  /// `totalFinishedWorkouts` value even without network access.
  void incrementCachedWorkoutCount(String userId) {
    final current = getCachedWorkoutCount(userId) ?? 0;
    _cache.write(
      HiveService.userPrefs,
      'finished_workout_count:$userId',
      current + 1,
    );
  }

  /// Discard (delete) an active workout.
  Future<void> discardWorkout(String workoutId, {required String userId}) {
    return mapException(() async {
      await _workouts.delete().eq('id', workoutId).eq('user_id', userId);
    });
  }

  /// Delete workouts for a user.
  ///
  /// Default behaviour ([includeActive] = `false`) deletes only finished,
  /// non-active workouts — the contract the "Delete Workout History"
  /// affordance pins (active in-progress workouts must survive).
  ///
  /// When [includeActive] is `true`, the `is_active` + `finished_at`
  /// filters are dropped so EVERY workout owned by the user is removed,
  /// including draft / in-progress sessions. Used by
  /// `resetAllAccountData` to honour the "Reset ALL account data" label
  /// — cluster: data-protection-compliance. The Hive `active_workout`
  /// box is cleared separately on the auth-state-change path, so this
  /// repo-layer wipe pairs with that to leave no resurrectable session.
  ///
  /// Cascade-deletes workout_exercises and sets via FK constraints.
  Future<void> clearHistory(String userId, {bool includeActive = false}) {
    return mapException(() async {
      var query = _workouts.delete().eq('user_id', userId);
      if (!includeActive) {
        query = query.eq('is_active', false).not('finished_at', 'is', null);
      }
      await query;
      // History keys are now `'<userId>:<locale>'`; clear the entire box to
      // evict every locale entry for the user.
      _cache.clearBox(HiveService.workoutHistoryCache);
      _cache.clearBox(HiveService.lastSetsCache);
    });
  }

  /// Parse a workout detail response into structured data.
  ///
  /// Optionally resolves [WorkoutExercise.exercise] from [exerciseMap], which
  /// is the locale-resolved batch from [ExerciseRepository.getExercisesByIds].
  /// When [exerciseMap] is empty the exercise field stays null on every row —
  /// that's fine for tests that only assert workout/set shape.
  static WorkoutDetail parseWorkoutDetail(
    Map<String, dynamic> data, [
    Map<String, Exercise> exerciseMap = const {},
  ]) {
    final workout = Workout.fromJson(data);
    final exercisesData = data['workout_exercises'] as List<dynamic>? ?? [];

    final exercises = <WorkoutExercise>[];
    final setsByExercise = <String, List<ExerciseSet>>{};

    for (final weData in exercisesData) {
      final weMap = weData as Map<String, dynamic>;

      // Resolve exercise from the batch RPC result. Missing IDs (soft-
      // deleted or foreign-owned) leave `exercise: null`; the UI falls
      // back to a generic label.
      final exerciseId = weMap['exercise_id'] as String?;
      final exercise = exerciseId != null ? exerciseMap[exerciseId] : null;

      final we = WorkoutExercise.fromJson(weMap).copyWith(exercise: exercise);
      exercises.add(we);

      final setsData = weMap['sets'] as List<dynamic>? ?? [];
      setsByExercise[we.id] =
          setsData
              .map((s) => ExerciseSet.fromJson(s as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    }

    exercises.sort((a, b) => a.order.compareTo(b.order));
    return (
      workout: workout,
      exercises: exercises,
      setsByExercise: setsByExercise,
    );
  }
}
