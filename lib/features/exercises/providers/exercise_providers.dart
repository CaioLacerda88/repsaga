import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/local_storage/cache_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/exercise_repository.dart';
import '../models/exercise.dart';

/// Provides the [ExerciseRepository] singleton.
final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepository(
    Supabase.instance.client,
    ref.watch(cacheServiceProvider),
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Filter state for the exercise list.
class ExerciseFilter {
  const ExerciseFilter({
    this.muscleGroup,
    this.equipmentType,
    this.searchQuery = '',
  });

  final MuscleGroup? muscleGroup;
  final EquipmentType? equipmentType;
  final String searchQuery;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExerciseFilter &&
          muscleGroup == other.muscleGroup &&
          equipmentType == other.equipmentType &&
          searchQuery == other.searchQuery;

  @override
  int get hashCode => Object.hash(muscleGroup, equipmentType, searchQuery);
}

/// Selected muscle group filter.
///
/// `autoDispose` so the filter resets when no UI is listening (i.e. the
/// [ExerciseListScreen] is unmounted). Without it, navigating away from the
/// list and back leaves stale filter state behind while the screen's local
/// `TextEditingController` is recreated empty — producing a "stuck filter
/// with empty search box" that the user cannot clear (F4).
final selectedMuscleGroupProvider = StateProvider.autoDispose<MuscleGroup?>(
  (ref) => null,
);

/// Selected equipment type filter. See [selectedMuscleGroupProvider] for the
/// autoDispose rationale (F4).
final selectedEquipmentTypeProvider = StateProvider.autoDispose<EquipmentType?>(
  (ref) => null,
);

/// Search query for exercises. See [selectedMuscleGroupProvider] for the
/// autoDispose rationale (F4).
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Fetches exercises based on an [ExerciseFilter].
///
/// Uses `autoDispose` so cache entries are freed when no UI is listening
/// (e.g. after a filter change creates a new entry and the old one loses
/// its last subscriber). Without autoDispose every distinct filter
/// combination lives forever — see F1 in the filter-performance fix.
///
/// **Locale-reactive:** watches [localeProvider] so a locale switch causes
/// every active list provider to refetch with the new locale. The Hive
/// cache is also keyed by locale (see `ExerciseRepository._cacheKey`).
final exerciseListProvider = FutureProvider.autoDispose
    .family<List<Exercise>, ExerciseFilter>((ref, filter) {
      final repo = ref.watch(exerciseRepositoryProvider);
      final locale = ref.watch(localeProvider).languageCode;
      final userId = ref.watch(currentUserIdProvider);
      // No authenticated user => no exercises (RPC requires non-null
      // p_user_id; UI should never reach here without auth, but guard so a
      // logged-out edge case returns empty rather than crashing).
      if (userId == null) return Future.value(<Exercise>[]);

      if (filter.searchQuery.isNotEmpty) {
        return repo.searchExercises(
          locale: locale,
          userId: userId,
          query: filter.searchQuery,
          muscleGroup: filter.muscleGroup,
          equipmentType: filter.equipmentType,
        );
      }
      return repo.getExercises(
        locale: locale,
        userId: userId,
        muscleGroup: filter.muscleGroup,
        equipmentType: filter.equipmentType,
      );
    });

/// Fetches a single exercise by ID. Auto-disposes when detail screen is popped.
///
/// Locale-reactive (see [exerciseListProvider]).
final exerciseByIdProvider = FutureProvider.autoDispose
    .family<Exercise, String>((ref, exerciseId) {
      final repo = ref.watch(exerciseRepositoryProvider);
      final locale = ref.watch(localeProvider).languageCode;
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) {
        throw StateError('exerciseByIdProvider requires an authenticated user');
      }
      return repo.getExerciseById(
        locale: locale,
        userId: userId,
        id: exerciseId,
      );
    });

/// Deletes an exercise (soft-delete) and invalidates dependent providers.
///
/// Accepts [WidgetRef] so it can be called from UI code without the widget
/// touching the repository directly.
Future<void> deleteExercise(
  WidgetRef ref,
  String exerciseId, {
  required String userId,
}) async {
  final repo = ref.read(exerciseRepositoryProvider);
  await repo.softDeleteExercise(exerciseId, userId: userId);
  // Invalidate the detail cache for this exercise.
  ref.invalidate(exerciseByIdProvider(exerciseId));
  // Invalidate all filtered list caches so the deleted exercise disappears.
  ref.invalidate(exerciseListProvider);
}

/// Combines filter state providers and watches [exerciseListProvider].
///
/// `autoDispose` so the entire filter chain
/// (`searchQueryProvider`, `selectedMuscleGroupProvider`,
/// `selectedEquipmentTypeProvider`) tears down once the
/// [ExerciseListScreen] unmounts (F4). A non-autoDispose Provider here
/// would keep its `ref.watch` subscriptions to the filter providers alive
/// forever, defeating their `.autoDispose` and causing the
/// "stuck filter / empty search box" navigation bug.
final filteredExerciseListProvider =
    Provider.autoDispose<AsyncValue<List<Exercise>>>((ref) {
      final filter = ExerciseFilter(
        muscleGroup: ref.watch(selectedMuscleGroupProvider),
        equipmentType: ref.watch(selectedEquipmentTypeProvider),
        searchQuery: ref.watch(searchQueryProvider),
      );
      return ref.watch(exerciseListProvider(filter));
    });
