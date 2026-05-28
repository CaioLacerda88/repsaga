import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/personal_records/models/personal_record.dart';
import '../../features/personal_records/providers/pr_providers.dart';
import '../../features/workouts/models/exercise_set.dart';
import '../../features/workouts/models/workout.dart';
import '../../features/workouts/models/workout_exercise.dart';
import '../../features/workouts/providers/workout_providers.dart';
import 'offline_queue_service.dart';
import 'pending_action.dart';
import 'sync_error_mapper.dart';

/// Exposes the pending-sync queue count as reactive state.
///
/// UI widgets (badge, sheet) watch this provider to react to queue changes.
/// Mutations go through the notifier methods so the count auto-updates.
class PendingSyncNotifier extends Notifier<int> {
  late OfflineQueueService _queue;
  final _inFlight = <String>{};

  @override
  int build() {
    _queue = ref.watch(offlineQueueServiceProvider);
    _inFlight.clear();
    return _queue.pendingCount;
  }

  /// Whether the given action ID is currently being retried.
  bool isInFlight(String id) => _inFlight.contains(id);

  /// Re-read the queue count and push it to listeners.
  ///
  /// Useful when an external caller (e.g. SyncService) mutates the queue
  /// and needs the badge count to update without going through [enqueue].
  void refreshCount() {
    state = _queue.pendingCount;
  }

  /// Add an action to the offline queue and update the badge count.
  Future<void> enqueue(PendingAction action) async {
    await _queue.enqueue(action);
    state = _queue.pendingCount;
  }

  /// List all pending actions (sorted by queuedAt).
  List<PendingAction> getAll() => _queue.getAll();

  /// Retry a single queued item by executing the appropriate repo call.
  ///
  /// On success: dequeues the item and decrements the count.
  /// On failure: increments retryCount, stores the error, and rethrows.
  ///
  /// If the item is already being retried (e.g. by SyncService while the user
  /// taps "Retry" in PendingSyncSheet), the call returns immediately to
  /// prevent duplicate server requests.
  Future<void> retryItem(String id) async {
    if (_inFlight.contains(id)) return;

    final actions = _queue.getAll();
    final action = actions.where((a) => a.id == id).firstOrNull;
    if (action == null) return;

    _inFlight.add(id);
    try {
      await _executeAction(action);
      await _queue.dequeue(id);
      state = _queue.pendingCount;
    } catch (e) {
      log(
        'Retry failed for action $id: $e',
        name: 'PendingSyncNotifier',
        level: 900,
      );
      // BUG-008: classify the error so the pending-sync sheet can pick the
      // right CTA (retry vs dismiss) without re-classifying. Stored on the
      // action and persisted alongside `lastError`.
      final category = SyncErrorMapper.classifyCategory(e);
      final updated = _withRetry(action, e.toString(), category);
      await _queue.updateAction(updated);
      state = _queue.pendingCount;
      rethrow;
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Dismiss a single queued item without retrying — used by the
  /// pending-sync sheet (BUG-008) when the error category is structural and
  /// retry won't help. Removes the item from the queue and updates the count.
  Future<void> dismissItem(String id) async {
    await _queue.dequeue(id);
    state = _queue.pendingCount;
  }

  /// Execute a pending action against the appropriate repository.
  Future<void> _executeAction(PendingAction action) async {
    switch (action) {
      case PendingSaveWorkout(
        :final workoutJson,
        :final exercisesJson,
        :final setsJson,
      ):
        final repo = ref.read(workoutRepositoryProvider);
        // Extract routine_id from the persisted workout JSON so the 26e
        // bucket find-or-create in `save_workout` (migration 00063) gets
        // the same payload as the online path. The key is written into
        // workoutJson by the repository at enqueue time; absent for
        // pre-26e queued workouts (graceful fallback to null = free
        // workout / spontaneous append).
        final routineId = workoutJson['routine_id'] as String?;
        await repo.saveWorkout(
          workout: Workout.fromJson(workoutJson),
          exercises: exercisesJson.map(WorkoutExercise.fromJson).toList(),
          sets: setsJson.map(ExerciseSet.fromJson).toList(),
          routineId: routineId,
        );

      case PendingUpsertRecords(:final recordsJson):
        final repo = ref.read(prRepositoryProvider);
        await repo.upsertRecords(
          recordsJson.map(PersonalRecord.fromJson).toList(),
        );

      case PendingMarkRoutineComplete(:final planId, :final routineId):
        // 26e: client-side `markRoutineComplete` is gone — the 00063
        // `save_workout` RPC owns the bucket update server-side in the
        // same transaction as the workout insert. Any `PendingSaveWorkout`
        // sitting next to this action in the queue carries `routine_id`
        // in its JSON payload, so the sibling drain re-applies the bucket
        // update. This branch exists only to gracefully drain legacy
        // queue entries from a pre-26e build that may still be in a
        // user's Hive box across an upgrade — without this case the
        // switch becomes non-exhaustive and the drain throws on the
        // legacy row, blocking the rest of the FIFO.
        log(
          '26e: PendingMarkRoutineComplete is a no-op — bucket update '
          'now in 00063 RPC; legacy queue entry skipped (plan=$planId '
          'routine=$routineId)',
          name: 'PendingSyncNotifier',
        );
    }
  }

  /// Create an updated copy of [action] with incremented retryCount, error,
  /// and the classified [errorCategory] so the UI can pick the right CTA.
  PendingAction _withRetry(
    PendingAction action,
    String error,
    SyncErrorCategory category,
  ) {
    return switch (action) {
      PendingSaveWorkout() => action.copyWith(
        retryCount: action.retryCount + 1,
        lastError: error,
        errorCategory: category,
      ),
      PendingUpsertRecords() => action.copyWith(
        retryCount: action.retryCount + 1,
        lastError: error,
        errorCategory: category,
      ),
      PendingMarkRoutineComplete() => action.copyWith(
        retryCount: action.retryCount + 1,
        lastError: error,
        errorCategory: category,
      ),
    };
  }
}

/// Provides the pending-sync queue count (int) as reactive state.
final pendingSyncProvider = NotifierProvider<PendingSyncNotifier, int>(
  PendingSyncNotifier.new,
);
