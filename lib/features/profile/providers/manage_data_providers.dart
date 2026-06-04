import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../personal_records/providers/pr_providers.dart';
import '../../workouts/providers/workout_history_providers.dart';
import '../../workouts/providers/workout_providers.dart';

/// Clears all finished workout history for the current user.
///
/// Returns silently if no user is logged in.
/// Invalidates [workoutHistoryProvider] and [workoutCountProvider]
/// so caches reflect the deletion immediately.
Future<void> clearWorkoutHistory(WidgetRef ref) async {
  final userId = ref.read(authRepositoryProvider).currentUser?.id;
  if (userId == null) return;
  final repo = ref.read(workoutRepositoryProvider);
  await repo.clearHistory(userId);
  ref.invalidate(workoutHistoryProvider);
  ref.invalidate(workoutCountProvider);
}

/// Clears all workout history AND personal records for the current user.
///
/// Returns silently if no user is logged in.
/// Invalidates all relevant providers so caches reflect the deletion.
///
/// **Order matters**: personal records must be deleted first because
/// `personal_records.set_id` has a foreign key reference to `sets`.
/// Deleting workouts first would cascade-delete sets, violating that FK.
///
/// **`includeActive: true` on `clearHistory`** — cluster:
/// data-protection-compliance. The Reset All affordance promises total
/// workout-data erasure; a draft / in-progress active workout would
/// otherwise survive the reset and the next sign-in could resurrect it
/// (Supabase has the active row, Hive has been cleared on the auth
/// path, so the desktop client would reload the orphaned active row).
/// Dropping the `is_active` + `finished_at` filters here matches the
/// user-facing "ALL account data" label and recovers from stuck-active
/// edge cases.
Future<void> resetAllAccountData(WidgetRef ref) async {
  final userId = ref.read(authRepositoryProvider).currentUser?.id;
  if (userId == null) return;
  final workoutRepo = ref.read(workoutRepositoryProvider);
  final prRepo = ref.read(prRepositoryProvider);

  // Delete PRs first to clear set_id FK references before cascade-deleting sets.
  await prRepo.clearAllRecords(userId);
  await workoutRepo.clearHistory(userId, includeActive: true);

  ref.invalidate(workoutHistoryProvider);
  ref.invalidate(workoutCountProvider);
  ref.invalidate(prListProvider);
  ref.invalidate(prCountProvider);
  ref.invalidate(prListWithExercisesProvider);
  ref.invalidate(recentPRsProvider);
}
