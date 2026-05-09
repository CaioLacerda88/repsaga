import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/local_storage/cache_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../exercises/models/exercise.dart';
import '../../exercises/providers/exercise_providers.dart';
import '../data/pr_repository.dart';
import '../domain/pr_detection_service.dart';
import '../models/personal_record.dart';

/// A personal record enriched with exercise name and equipment type.
typedef PRWithExercise = ({
  PersonalRecord record,
  String exerciseName,
  EquipmentType equipmentType,
});

/// Provides the [PRRepository] singleton.
final prRepositoryProvider = Provider<PRRepository>((ref) {
  return PRRepository(
    Supabase.instance.client,
    ref.watch(cacheServiceProvider),
    ref.watch(exerciseRepositoryProvider),
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Provides the [PRDetectionService] singleton.
final prDetectionServiceProvider = Provider<PRDetectionService>((ref) {
  return PRDetectionService();
});

/// Fetches all personal records for the current user.
/// Used by the PR list screen.
final prListProvider = FutureProvider<List<PersonalRecord>>((ref) {
  final repo = ref.watch(prRepositoryProvider);
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return [];
  final locale = ref.watch(localeProvider).languageCode;
  return repo.getRecordsForUser(userId: user.id, locale: locale);
});

/// Total count of personal records for the current user.
///
/// Uses a server-side `COUNT(*)` query rather than the list length,
/// so it returns the real total regardless of any pagination.
final prCountProvider = FutureProvider<int>((ref) {
  final repo = ref.watch(prRepositoryProvider);
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return 0;
  return repo.getRecordCount(user.id);
});

/// Fetches PRs for a specific exercise (by exercise ID).
/// Used by exercise detail screen.
final exercisePRsProvider = FutureProvider.family<List<PersonalRecord>, String>(
  (ref, exerciseId) async {
    final repo = ref.watch(prRepositoryProvider);
    final records = await repo.getRecordsForExercises([exerciseId]);
    return records[exerciseId] ?? [];
  },
);

/// Fetches all PRs with exercise details for the PR list screen.
final prListWithExercisesProvider = FutureProvider<List<PRWithExercise>>((ref) {
  final repo = ref.watch(prRepositoryProvider);
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return [];
  final locale = ref.watch(localeProvider).languageCode;
  return repo.getRecordsWithExercises(userId: user.id, locale: locale);
});

/// Fetches the 3 most recent PRs with exercise details.
/// Used by the home screen to show recent achievements.
final recentPRsProvider = FutureProvider.autoDispose<List<PRWithExercise>>((
  ref,
) {
  final repo = ref.watch(prRepositoryProvider);
  final user = ref.watch(authRepositoryProvider).currentUser;
  if (user == null) return [];
  final locale = ref.watch(localeProvider).languageCode;
  return repo.getRecentRecordsWithExercises(
    userId: user.id,
    locale: locale,
    limit: 3,
  );
});

/// Returns the set of set IDs that are PRs within a given workout.
/// Used by the workout finish/summary screen to highlight PR sets.
final workoutPRSetIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, workoutId) async {
      final user = ref.watch(authRepositoryProvider).currentUser;
      if (user == null) return {};
      final repo = ref.watch(prRepositoryProvider);
      final prs = await repo.getPRsForWorkout(workoutId, user.id);
      return prs.map((pr) => pr.setId).whereType<String>().toSet();
    });
