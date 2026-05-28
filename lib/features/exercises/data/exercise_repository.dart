import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/local_storage/cache_service.dart';
import '../../../core/local_storage/hive_service.dart';
import '../models/exercise.dart';

/// Repository for exercise reads and user-exercise mutations.
///
/// **Phase 15f Stage 6 contract:**
/// All read methods take a required `locale` parameter and route through the
/// localized RPCs (`fn_exercises_localized`, `fn_search_exercises_localized`,
/// `fn_insert_user_exercise`). The legacy `exercises.{name, description,
/// form_tips}` columns no longer exist (dropped in migration 00034); the only
/// way to obtain those fields is through the RPC cascade
/// `requested locale → 'en' → any`.
///
/// `softDeleteExercise` still uses a direct table UPDATE because RLS handles
/// the auth check and no localized text is written. `getExercisesByIds` is the
/// batch read used by `WorkoutRepository`, `PRRepository`, and
/// `RoutineRepository` to merge exercise names into joined queries
/// (replacing the dropped `exercises(name)` embedded select).
///
/// **Cache layout:** keys are `'<locale>:<filter>'` so an `en` cache and a
/// `pt` cache coexist. `LocaleNotifier.setLocale` clears
/// `HiveService.exerciseCache` on locale switch — that's the safety net; this
/// repository's keys merely make sure stale-locale data can't leak in if the
/// switch eviction misses for any reason.
class ExerciseRepository extends BaseRepository {
  ExerciseRepository(this._client, this._cache, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;
  final CacheService _cache;

  /// Builds a deterministic cache key from locale and optional filters.
  ///
  /// Format: `'<locale>:all'`, `'<locale>:muscle=chest'`,
  /// `'<locale>:muscle=chest&equip=barbell'`, etc. The locale prefix isolates
  /// per-language entries; same filter set in `en` and `pt` resolves to two
  /// different keys.
  static String _cacheKey(
    String locale, {
    MuscleGroup? muscleGroup,
    EquipmentType? equipmentType,
  }) {
    if (muscleGroup == null && equipmentType == null) return '$locale:all';
    final parts = <String>[];
    if (muscleGroup != null) parts.add('muscle=${muscleGroup.name}');
    if (equipmentType != null) parts.add('equip=${equipmentType.name}');
    return '$locale:${parts.join('&')}';
  }

  /// Fetch exercises in the given [locale], optionally filtered by muscle and
  /// equipment.
  ///
  /// Routes to `fn_exercises_localized` (list mode, `p_ids = NULL`). Uses
  /// read-through caching: returns cached data on network failure.
  ///
  /// [userId] is required by the RPC's visibility predicate
  /// (`is_default = true OR user_id = p_user_id`); the RLS policy on
  /// `exercises` re-enforces this server-side.
  Future<List<Exercise>> getExercises({
    required String locale,
    required String userId,
    MuscleGroup? muscleGroup,
    EquipmentType? equipmentType,
  }) async {
    final key = _cacheKey(
      locale,
      muscleGroup: muscleGroup,
      equipmentType: equipmentType,
    );
    final cached = _cache.read<List<Exercise>>(
      HiveService.exerciseCache,
      key,
      (json) => (json as List)
          .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

    try {
      final fresh = await mapException(() async {
        final data = await _client.rpc(
          'fn_exercises_localized',
          params: {
            'p_locale': locale,
            'p_user_id': userId,
            'p_muscle_group': muscleGroup?.name,
            'p_equipment_type': equipmentType?.name,
            'p_ids': null,
            'p_order': 'name',
          },
        );
        final rows = (data as List).cast<Map<String, dynamic>>();
        return rows.map(Exercise.fromJson).toList();
      });

      // Fire-and-forget cache write.
      _cache.write(
        HiveService.exerciseCache,
        key,
        fresh.map((e) => e.toJson()).toList(),
      );

      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Search exercises by name (trigram similarity), in the given [locale],
  /// with optional filters.
  ///
  /// Routes to `fn_search_exercises_localized`. The RPC matches in the
  /// caller's locale OR `'en'` for cross-locale discoverability and returns
  /// the localized cascade for display.
  ///
  /// On network failure, falls back to filtering the cached `'<locale>:all'`
  /// entry in-memory by case-insensitive name substring. If no cache is
  /// available, rethrows.
  Future<List<Exercise>> searchExercises({
    required String locale,
    required String userId,
    required String query,
    MuscleGroup? muscleGroup,
    EquipmentType? equipmentType,
  }) async {
    try {
      return await mapException(() async {
        final data = await _client.rpc(
          'fn_search_exercises_localized',
          params: {
            'p_query': query,
            'p_locale': locale,
            'p_user_id': userId,
            'p_muscle_group': muscleGroup?.name,
            'p_equipment_type': equipmentType?.name,
          },
        );
        final rows = (data as List).cast<Map<String, dynamic>>();
        return rows.map(Exercise.fromJson).toList();
      });
    } catch (e) {
      // Offline fallback: filter the locale-scoped "all" cache in-memory.
      final cached = _cache.read<List<Exercise>>(
        HiveService.exerciseCache,
        '$locale:all',
        (json) => (json as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      if (cached == null) rethrow;

      final lowerQuery = query.toLowerCase();
      return cached.where((exercise) {
        if (!exercise.name.toLowerCase().contains(lowerQuery)) return false;
        if (muscleGroup != null && exercise.muscleGroup != muscleGroup) {
          return false;
        }
        if (equipmentType != null && exercise.equipmentType != equipmentType) {
          return false;
        }
        return true;
      }).toList();
    }
  }

  /// Get a single exercise by ID in the given [locale].
  ///
  /// Routes to `fn_exercises_localized` with `p_ids = ARRAY[id]`.
  /// Throws when the row is not found (RPC returns empty list →
  /// `StateError` from `.first`, mapped by the base repository).
  Future<Exercise> getExerciseById({
    required String locale,
    required String userId,
    required String id,
  }) {
    return mapException(() async {
      final data = await _client.rpc(
        'fn_exercises_localized',
        params: {
          'p_locale': locale,
          'p_user_id': userId,
          'p_muscle_group': null,
          'p_equipment_type': null,
          'p_ids': [id],
          'p_order': 'name',
        },
      );
      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        throw StateError('Exercise not found: $id');
      }
      return Exercise.fromJson(rows.first);
    });
  }

  /// Batch-fetch exercises by ID in the given [locale]. Returns a map
  /// keyed by exercise ID.
  ///
  /// Used by `WorkoutRepository`, `PRRepository`, and `RoutineRepository` to
  /// resolve exercise display fields after a join query (the embedded
  /// `exercises(name)` select no longer works post-Stage-4). One RPC call
  /// per invocation regardless of how many exercises are requested — the
  /// caller is responsible for not exceeding the 500-id cap (`p_ids` cap
  /// enforced server-side).
  ///
  /// Empty `ids` short-circuits without an RPC call and without touching the
  /// cache (still returns `{}`).
  ///
  /// **Cache key (spec §7.1):** `'<locale>:batch:<id1>,<id2>,...'` where the
  /// IDs are sorted ascending so callers passing `['B','A']` and `['A','B']`
  /// hit the same entry. Read-through pattern matches [getExercises]: cache
  /// is consulted before the RPC, fresh results are written fire-and-forget,
  /// and on network failure we fall back to the cached map.
  ///
  /// Visibility: only returns rows where `deleted_at IS NULL` and
  /// `is_default = true OR user_id = userId`. Soft-deleted or
  /// foreign-owned exercises silently drop from the result map; callers
  /// must handle missing keys (typically by leaving the joined entity's
  /// exercise reference null and letting the UI show a fallback).
  Future<Map<String, Exercise>> getExercisesByIds({
    required String locale,
    required String userId,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) return <String, Exercise>{};

    // Sort the IDs so callers passing the same set in different orders
    // hit the same cache entry. The original list is left untouched.
    final sortedIds = List<String>.from(ids)..sort();
    final key = '$locale:batch:${sortedIds.join(",")}';

    final cached = _cache.read<Map<String, Exercise>>(
      HiveService.exerciseCache,
      key,
      (json) => (json as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, Exercise.fromJson(v as Map<String, dynamic>)),
      ),
    );

    try {
      final fresh = await mapException(() async {
        final data = await _client.rpc(
          'fn_exercises_localized',
          params: {
            'p_locale': locale,
            'p_user_id': userId,
            'p_muscle_group': null,
            'p_equipment_type': null,
            'p_ids': sortedIds,
            'p_order': 'name',
          },
        );
        final rows = (data as List).cast<Map<String, dynamic>>();
        return <String, Exercise>{
          for (final row in rows) row['id'] as String: Exercise.fromJson(row),
        };
      });

      // Fire-and-forget cache write (Map<String, Map<String, dynamic>>
      // serializes cleanly through CacheService's jsonEncode pipeline).
      _cache.write(
        HiveService.exerciseCache,
        key,
        fresh.map((k, v) => MapEntry(k, v.toJson())),
      );

      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Update a user-owned exercise via `fn_update_user_exercise`.
  ///
  /// Each parameter is independently optional: `null` means "leave as-is".
  /// The RPC enforces ownership (caller's `auth.uid()` must match
  /// `exercises.user_id` AND the row must not be a default — raises 42501
  /// otherwise) and the duplicate-name invariant.
  ///
  /// The translation row's locale is preserved — editing does NOT re-tag the
  /// row to the UI's current locale (matches user mental model: "I typed
  /// this in pt; editing updates what I typed"). That's why this method
  /// does not take a `locale` parameter.
  ///
  /// Maps SQLSTATE 23505 (duplicate name) to [ValidationException].
  Future<Exercise> updateExercise({
    required String id,
    String? name,
    MuscleGroup? muscleGroup,
    EquipmentType? equipmentType,
    String? description,
    String? formTips,
  }) {
    return mapException(() async {
      try {
        final data = await _client.rpc(
          'fn_update_user_exercise',
          params: {
            'p_exercise_id': id,
            'p_name': name,
            'p_muscle_group': muscleGroup?.name,
            'p_equipment_type': equipmentType?.name,
            'p_description': description,
            'p_form_tips': formTips,
          },
        );
        final rows = (data as List).cast<Map<String, dynamic>>();
        if (rows.isEmpty) {
          throw StateError('fn_update_user_exercise returned no rows');
        }
        _cache.clearBox(HiveService.exerciseCache);
        return Exercise.fromJson(rows.first);
      } on supabase.PostgrestException catch (e) {
        if (e.code == '23505') {
          throw const ValidationException(
            'An exercise with this name already exists',
            field: 'name',
          );
        }
        rethrow;
      }
    });
  }

  /// Soft-delete an exercise by setting `deleted_at`.
  ///
  /// Uses a direct table UPDATE — RLS scopes the update to the caller's own
  /// rows (the explicit `.eq('user_id', userId)` is defence-in-depth) and no
  /// localized text is written, so this path does not need an RPC.
  Future<void> softDeleteExercise(String id, {required String userId}) {
    return mapException(() async {
      await _client
          .from('exercises')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', id)
          .eq('user_id', userId);
      _cache.clearBox(HiveService.exerciseCache);
    });
  }

  /// Get recent exercises (user-created + defaults), ordered by most recent.
  ///
  /// Routes to `fn_exercises_localized` with `p_order = 'created_at_desc'`,
  /// then trims to [limit] client-side. The RPC has no built-in `LIMIT`
  /// (caller-controlled trimming keeps the surface uniform across modes).
  Future<List<Exercise>> recentExercises({
    required String locale,
    required String userId,
    int limit = 10,
  }) {
    return mapException(() async {
      final data = await _client.rpc(
        'fn_exercises_localized',
        params: {
          'p_locale': locale,
          'p_user_id': userId,
          'p_muscle_group': null,
          'p_equipment_type': null,
          'p_ids': null,
          'p_order': 'created_at_desc',
        },
      );
      final rows = (data as List).cast<Map<String, dynamic>>();
      final exercises = rows.map(Exercise.fromJson).toList();
      return exercises.take(limit).toList();
    });
  }
}
