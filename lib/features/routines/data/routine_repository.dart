import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import '../../../core/local_storage/cache_service.dart';
import '../../../core/local_storage/hive_service.dart';
import '../../exercises/data/exercise_repository.dart';
import '../../exercises/models/exercise.dart';
import '../models/routine.dart';
import 'workout_template_translation_resolver.dart';

/// Repository for routine reads and writes.
///
/// **Phase 15f Stage 6 contract:**
/// All read methods take a required `locale` parameter. Routine rows in
/// `workout_templates` reference exercises by `exercise_id` only — the
/// localized `(name, description, form_tips)` for each referenced exercise is
/// resolved via a single batch RPC through
/// `ExerciseRepository.getExercisesByIds(locale, userId, ids)`. Two queries
/// per call (templates + batch exercises) — N+1 safe.
///
/// Cache layout: keys are `'<userId>:<locale>'` so en/pt entries coexist.
/// `LocaleNotifier.setLocale` clears `HiveService.routineCache` on locale
/// switch — that's the safety net; this repository's keys merely make sure
/// stale-locale data can't leak in if the switch eviction misses.
///
/// Mutations (create / update / delete) clear the entire `routineCache` box
/// since per-user delete with locale-prefixed keys would require iterating all
/// keys to find this user's entries.
class RoutineRepository extends BaseRepository {
  RoutineRepository(
    this._client,
    this._cache,
    this._exerciseRepo,
    this._templateTranslations, {
    super.recoveryRecorder,
  });

  final supabase.SupabaseClient _client;
  final CacheService _cache;
  final ExerciseRepository _exerciseRepo;
  final WorkoutTemplateTranslationResolver _templateTranslations;

  supabase.SupabaseQueryBuilder get _templates =>
      _client.from('workout_templates');

  /// Builds the cache key for a user's routines in [locale].
  static String _cacheKey(String userId, String locale) => '$userId:$locale';

  /// Fetch routines owned by [userId] plus all default routines, newest first.
  ///
  /// Uses read-through caching: returns cached data on network failure.
  Future<List<Routine>> getRoutines({
    required String userId,
    required String locale,
  }) async {
    final cached = _readCachedRoutines(userId, locale);

    try {
      final fresh = await mapException(() async {
        final data = await _templates
            .select()
            .or('user_id.eq.$userId,is_default.eq.true')
            .order('created_at', ascending: false);

        final routines = data.map(Routine.fromJson).toList();
        final localized = await _applyTemplateTranslations(
          routines: routines,
          locale: locale,
        );
        return _resolveExercises(
          routines: localized,
          userId: userId,
          locale: locale,
        );
      });

      // Fire-and-forget cache write.
      _writeCachedRoutines(userId, locale, fresh);

      return fresh;
    } catch (e) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Fetch a single routine by [id] with exercise details resolved for
  /// [locale]. [userId] is required so the batch RPC's visibility predicate
  /// can resolve user-owned exercises in addition to defaults.
  Future<Routine> getRoutine({
    required String id,
    required String userId,
    required String locale,
  }) {
    return mapException(() async {
      final data = await _templates.select().eq('id', id).single();
      final routine = Routine.fromJson(data);
      final localized = await _applyTemplateTranslations(
        routines: [routine],
        locale: locale,
      );
      final resolved = await _resolveExercises(
        routines: localized,
        userId: userId,
        locale: locale,
      );
      return resolved.first;
    });
  }

  /// Insert a new user-created routine and return it with exercises resolved
  /// for [locale].
  Future<Routine> createRoutine({
    required String userId,
    required String locale,
    required String name,
    required List<RoutineExercise> exercises,
  }) {
    return mapException(() async {
      final data = await _templates
          .insert({
            'user_id': userId,
            'name': name,
            'is_default': false,
            'exercises': exercises.map((e) => e.toJson()).toList(),
          })
          .select()
          .single();

      final routine = Routine.fromJson(data);
      final resolved = await _resolveExercises(
        routines: [routine],
        userId: userId,
        locale: locale,
      );
      _cache.clearBox(HiveService.routineCache);
      return resolved.first;
    });
  }

  /// Update [name] and [exercises] for the given routine (user_id must match).
  /// Returns the updated routine with exercises resolved for [locale].
  Future<Routine> updateRoutine({
    required String id,
    required String userId,
    required String locale,
    required String name,
    required List<RoutineExercise> exercises,
  }) {
    return mapException(() async {
      final data = await _templates
          .update({
            'name': name,
            'exercises': exercises.map((e) => e.toJson()).toList(),
          })
          .eq('id', id)
          .eq('user_id', userId)
          .select()
          .single();

      final routine = Routine.fromJson(data);
      final resolved = await _resolveExercises(
        routines: [routine],
        userId: userId,
        locale: locale,
      );
      _cache.clearBox(HiveService.routineCache);
      return resolved.first;
    });
  }

  /// Delete a user-created routine. Fails silently if [id] doesn't exist or
  /// belongs to a different user. Default routines are never matched because
  /// they have no user_id equal to [userId].
  Future<void> deleteRoutine(String id, {required String userId}) {
    return mapException(() async {
      await _templates
          .delete()
          .eq('id', id)
          .eq('user_id', userId)
          .eq('is_default', false);
      _cache.clearBox(HiveService.routineCache);
    });
  }

  // ---------------------------------------------------------------------------
  // Cache helpers
  // ---------------------------------------------------------------------------

  /// Writes routines to cache with a separate exercise map so that
  /// [RoutineExercise.exercise] (excluded from `toJson()`) survives roundtrip.
  /// Key is `<userId>:<locale>` so en and pt cache entries coexist.
  void _writeCachedRoutines(
    String userId,
    String locale,
    List<Routine> routines,
  ) {
    final exerciseMap = <String, Map<String, dynamic>>{};
    for (final r in routines) {
      for (final re in r.exercises) {
        if (re.exercise != null) {
          exerciseMap[re.exerciseId] = re.exercise!.toJson();
        }
      }
    }
    _cache.write(HiveService.routineCache, _cacheKey(userId, locale), {
      'routines': routines.map((r) => r.toJson()).toList(),
      'exercises': exerciseMap,
    });
  }

  /// Reads routines from cache, re-resolving exercise references from the
  /// stored exercise map. Uses the `<userId>:<locale>` key.
  List<Routine>? _readCachedRoutines(String userId, String locale) {
    return _cache.read<List<Routine>>(
      HiveService.routineCache,
      _cacheKey(userId, locale),
      (json) {
        final map = json as Map<String, dynamic>;
        final routineList = (map['routines'] as List)
            .map((e) => Routine.fromJson(e as Map<String, dynamic>))
            .toList();
        final exercises = (map['exercises'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, Exercise.fromJson(v as Map<String, dynamic>)),
        );
        return routineList.map((routine) {
          final resolved = routine.exercises.map((re) {
            final exercise = exercises[re.exerciseId];
            return exercise != null ? re.copyWith(exercise: exercise) : re;
          }).toList();
          return routine.copyWith(exercises: resolved);
        }).toList();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Rewrite [Routine.name] for default templates with their per-locale
  /// translation from `workout_template_translations`.
  ///
  /// Cascade: requested [locale] → `'en'` → original (verbatim from the DB).
  /// User-created routines (`templateSlug == null`) pass through unchanged.
  /// Empty default-routine set short-circuits without a network call.
  Future<List<Routine>> _applyTemplateTranslations({
    required List<Routine> routines,
    required String locale,
  }) async {
    final slugs = <String>{
      for (final r in routines)
        if (r.isDefault && r.templateSlug != null) r.templateSlug!,
    };
    if (slugs.isEmpty) return routines;

    final names = await _templateTranslations.resolveNames(
      slugs: slugs,
      locale: locale,
    );

    return routines.map((r) {
      final slug = r.templateSlug;
      if (slug == null) return r;
      final localized = names[slug];
      return localized != null ? r.copyWith(name: localized) : r;
    }).toList();
  }

  /// Resolve [RoutineExercise.exercise] for every exercise referenced in
  /// [routines] by batch-fetching localized rows and copying them onto each
  /// [RoutineExercise]. One batch RPC per call.
  ///
  /// Missing exercises (soft-deleted, foreign-owned) are left unresolved —
  /// the UI handles `re.exercise == null` by showing a fallback.
  Future<List<Routine>> _resolveExercises({
    required List<Routine> routines,
    required String userId,
    required String locale,
  }) async {
    final exerciseMap = await _fetchExerciseMap(
      routines: routines,
      userId: userId,
      locale: locale,
    );

    return routines.map((routine) {
      final resolved = routine.exercises.map((re) {
        final exercise = exerciseMap[re.exerciseId];
        return exercise != null ? re.copyWith(exercise: exercise) : re;
      }).toList();
      return routine.copyWith(exercises: resolved);
    }).toList();
  }

  /// Collects unique exercise IDs referenced by [routines] and delegates to
  /// `ExerciseRepository.getExercisesByIds` for a localized batch lookup.
  Future<Map<String, Exercise>> _fetchExerciseMap({
    required List<Routine> routines,
    required String userId,
    required String locale,
  }) async {
    final ids = <String>{
      for (final r in routines)
        for (final re in r.exercises) re.exerciseId,
    };

    if (ids.isEmpty) return const {};

    return _exerciseRepo.getExercisesByIds(
      locale: locale,
      userId: userId,
      ids: ids.toList(),
    );
  }
}
