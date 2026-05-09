import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../features/analytics/data/models/analytics_event.dart';
import '../../features/analytics/providers/analytics_providers.dart';
import '../../features/exercises/providers/exercise_progress_provider.dart';
import '../../features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import '../../features/rpg/providers/character_sheet_provider.dart';
import '../../features/rpg/providers/earned_titles_provider.dart';
import '../../features/rpg/providers/rpg_progress_provider.dart';
import '../../features/weekly_plan/providers/weekly_plan_provider.dart';
import '../../features/workouts/providers/workout_history_providers.dart';
import '../connectivity/connectivity_provider.dart';
import '../connectivity/connectivity_recovery_provider.dart';
import '../observability/sentry_report.dart';
import 'health_check_provider.dart';
import 'offline_queue_service.dart';
import 'pending_action.dart';
import 'pending_sync_provider.dart';
import 'sync_error_classifier.dart';

/// Maximum number of retries before a queued action is considered terminal.
const kMaxSyncRetries = 6;

/// Watches connectivity and drains the offline queue FIFO on connectivity
/// transitions AND on cold launch when already-online with pre-existing
/// queue items.
///
/// The drain is transparent to the user. [PendingSyncNotifier]'s badge count
/// decrements as items are dequeued. Only terminal failures (items that
/// exhausted [kMaxSyncRetries]) are surfaced via [SyncState.terminalFailureCount].
class SyncService extends Notifier<SyncState> {
  /// Tracks the last-known online status to detect offline-to-online
  /// transitions. Defaults to `true` so the initial `true` emission from
  /// [onlineStatusProvider] does NOT trigger a drain via the listener path —
  /// the cold-launch-online case is handled by [_coldLaunchDrain] below
  /// instead, which awaits the StreamProvider's first REAL emission directly
  /// (independent of [isOnlineProvider]'s synthetic optimistic default).
  bool _lastOnline = true;

  /// Guards against concurrent drain invocations.
  bool _draining = false;

  /// Flips to `true` once the Notifier is disposed so the unawaited
  /// [_coldLaunchDrain] future doesn't call into a destroyed [ref].
  bool _disposed = false;

  /// Periodic health-check timer. Lives only while the queue contains at
  /// least one transient (retryable) item. Cancelled when the queue becomes
  /// empty or all-terminal so an idle queue produces zero background traffic.
  Timer? _healthCheckTimer;

  @override
  SyncState build() {
    // Synchronize _lastOnline with the current connectivity state so that
    // the first listener callback can correctly detect a transition.
    _lastOnline = ref.read(isOnlineProvider);

    ref.onDispose(() {
      _disposed = true;
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;
    });

    ref.listen<bool>(isOnlineProvider, (previous, next) {
      final wasOffline = !_lastOnline;
      _lastOnline = next;
      if (wasOffline && next) {
        _drain();
      }
    });

    // AW-EX-E-US1-01: third drain trigger. The OS-level adapter event
    // (above) misses captive portal recovery / same-SSID reconnect / silent
    // backend outages. The recovery notifier ticks whenever a successful
    // repository call follows a recent network-class failure — that's the
    // user's effective recovery signal regardless of what the OS reports.
    //
    // The notifier owns its own 5s cooldown and 5min failure window, so the
    // listener body just kicks `_drain()` on every state change. The
    // existing `_draining` guard inside `_drain` collapses concurrent ticks
    // (e.g. tick + tick + tick during a long drain → only the first wins).
    ref.listen<int>(connectivityRecoveryProvider, (previous, next) {
      if (previous == next) return;
      _drain();
    });

    // Health-check lifecycle. The queue size is reactive (pendingSyncProvider
    // exposes the int count), so listening to it gives an event-driven
    // start/stop without polling. Initial check covers the case where the
    // service was built with pre-existing queue items.
    _evaluateHealthCheckTimer();
    // Double-wildcard parameters (`(_, _)`) require Dart >= 3.0; the project's
    // pubspec SDK constraint (^3.11.4) is well past that. If the SDK lower
    // bound is ever reduced, this site would need named placeholders.
    ref.listen<int>(pendingSyncProvider, (_, _) {
      _evaluateHealthCheckTimer();
    });

    // Cold-launch drain. The listener above does NOT fire on cold launch
    // when the app boots already-online: [isOnlineProvider]'s optimistic
    // default is `true`, the StreamProvider's first real emission is also
    // `true`, and Riverpod's listener path skips the no-change callback.
    // Pre-existing queue items from a previous offline session would
    // therefore sit forever until a connectivity flap (or app relaunch
    // following one) triggered the listener.
    //
    // [onlineStatusProvider.future] resolves with the StreamProvider's
    // FIRST data emission — independent of [isOnlineProvider]'s synthetic
    // optimistic value — so awaiting it gives us the real cold-launch
    // online status. If it's `true`, kick off the drain. The [_draining]
    // reentrancy guard inside [_drain] keeps this path mutually exclusive
    // with the listener path on subsequent online→offline→online flaps.
    unawaited(_coldLaunchDrain());

    return const SyncState();
  }

  /// Idempotent: starts the health-check timer when the queue gains a
  /// transient item, stops it when the queue is empty or all-terminal.
  /// Safe to call from listeners on every queue-count change — the timer
  /// is only (re)created on a state transition.
  void _evaluateHealthCheckTimer() {
    if (_disposed) return;
    final hasTransient = _hasTransientItems();
    if (hasTransient) {
      // Already running? Nothing to do — `Timer.periodic` doesn't restart
      // on every queue change, which preserves the configured cadence.
      if (_healthCheckTimer?.isActive == true) return;
      final interval = ref.read(healthCheckIntervalProvider);
      _healthCheckTimer = Timer.periodic(interval, (_) {
        unawaited(_runHealthCheck());
      });
    } else {
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;
    }
  }

  /// Are there any non-terminal items in the queue? Terminal items
  /// (retryCount >= kMaxSyncRetries) require a manual user action to
  /// re-arm via [retryTerminalItems], so they don't justify keeping the
  /// background probe alive.
  ///
  /// Defensive against a closed/missing Hive box: if the underlying queue
  /// read throws (e.g. widget tests that exercise [SyncService] without
  /// initialising the `offline_queue` box), treat it as "no transient items"
  /// so no health-check timer starts. The semantic is correct — no readable
  /// queue means no items to probe for.
  ///
  /// **Catch shape.** Hive raises [HiveError] (which `extends Error`, NOT
  /// `Exception`) when a box isn't open / has been closed — the production
  /// failure mode this guard exists to absorb. We catch that explicitly
  /// alongside the generic `Exception` case (network/serialization shapes
  /// that could surface through a custom queue impl). Programming errors
  /// — `TypeError`, `RangeError`, `NoSuchMethodError`, plain `StateError`
  /// — must still surface so test/build regressions are loud, not silent.
  bool _hasTransientItems() {
    try {
      final actions = ref.read(offlineQueueServiceProvider).getAll();
      return actions.any((a) => a.retryCount < kMaxSyncRetries);
    } on HiveError catch (_) {
      return false;
    } on Exception catch (_) {
      return false;
    }
  }

  /// One health-check probe. Funnels result through the recovery notifier
  /// — a success after a recorded failure ticks the recovery state, which
  /// the listener above turns into a drain. Failures arm the recovery
  /// window for the next probe / next real call.
  ///
  /// The probe runs through [healthCheckProvider] so tests can stub it.
  /// Errors thrown by the probe itself are caught and recorded as failures
  /// — the timer must never be torn down by an exception.
  Future<void> _runHealthCheck() async {
    if (_disposed) return;
    if (!_hasTransientItems()) {
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;
      return;
    }
    final probe = ref.read(healthCheckProvider);
    final recorder = ref.read(connectivityRecoveryProvider.notifier);
    try {
      final ok = await probe();
      if (_disposed) return;
      if (ok) {
        recorder.recordSuccess();
      } else {
        // Pass a minimal network-class shape so the classifier records the
        // failure. The exact instance doesn't matter — only its type.
        recorder.recordFailure(TimeoutException('health-check failed'));
      }
    } catch (e) {
      if (_disposed) return;
      recorder.recordFailure(e);
    }
  }

  /// Awaits the StreamProvider's first real emission and drains the queue
  /// when online. Errors are swallowed — the listener path will still
  /// catch subsequent connectivity changes, so a stream error here is
  /// recoverable rather than fatal.
  Future<void> _coldLaunchDrain() async {
    try {
      final firstReal = await ref.read(onlineStatusProvider.future);
      if (_disposed) return;
      if (firstReal) {
        await _drain();
      }
    } catch (_) {
      // Stream errored — the listener path picks up subsequent emissions.
    }
  }

  /// Drain the offline queue in FIFO order.
  ///
  /// For each action:
  /// 1. Stop if connectivity drops mid-drain.
  /// 2. Skip if already being retried (in-flight guard).
  /// 3. Skip if retryCount >= [kMaxSyncRetries] (terminal).
  /// 4. Skip if any [PendingAction.dependsOn] parent is still in the queue
  ///    AND not terminal — the parent must commit first or the child's FK
  ///    will fail (BUG-002, BUG-003).
  /// 5. Delegate to [PendingSyncNotifier.retryItem].
  /// 6. On success: emit [AnalyticsEvent.workoutSyncSucceeded].
  /// 7. On failure: classify error, maybe backoff, maybe emit failed event.
  ///
  /// **Post-loop side effects (BUG-005):** when at least one
  /// [PendingSaveWorkout] drained successfully, invalidates the RPG/PR/
  /// progress provider tree so the UI rebuilds against the new server state
  /// without requiring an app relaunch. Without this, the user trains hard
  /// offline, syncs, opens the character sheet — and sees no rank progress
  /// until they kill the app.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;

    // Suppress the recovery recorder for the duration of the drain. The
    // drain's own repository calls would otherwise feed back into
    // recordSuccess/recordFailure, ticking the recovery counter and either
    // starting a phantom drain (re-entry caught by the `_draining` guard,
    // but the cooldown still consumes a slot) or triggering an immediate
    // re-drain after this one finishes. Plan §330 — explicitly spec'd
    // option 2 (suppression) over option 1 (rely on guard side-effects).
    final recoveryNotifier = ref.read(connectivityRecoveryProvider.notifier);
    recoveryNotifier.setRecordingSuppressed(true);

    try {
      final notifier = ref.read(pendingSyncProvider.notifier);
      final queue = ref.read(offlineQueueServiceProvider);
      final actions = queue.getAll(); // FIFO (sorted by queuedAt)

      // Collect unique userIds from successfully drained upsertRecords items
      // so we can batch reconciliation after the loop.
      final reconciledUserIds = <String>{};

      // BUG-005: track successful saveWorkout drains so we know whether to
      // invalidate the RPG/progress providers post-loop. We don't need a
      // count, only "did at least one save commit".
      var drainedSaveWorkouts = 0;

      // Snapshot the live IDs for dependency gating. ALL queued actions
      // count as live regardless of retry count; the set shrinks only when
      // an action is actually dequeued (success here, or `dismissItem` /
      // `dismissTerminalItems` in another flow).
      //
      // BUG (production crash on Galaxy S25 Ultra): previously this set was
      // built as `{ a.id : a.retryCount < kMaxSyncRetries }` so an exhausted
      // parent (e.g. a `PendingSaveWorkout` that hit a structural error like
      // BUG-A's exercise_peak_loads CHECK violation) would silently leave
      // `liveIds`. The dependency gate below would then see an "open" parent,
      // attempt the child `PendingUpsertRecords`, and crash with
      // `personal_records_set_id_fkey` because the parent's sets were never
      // persisted server-side. Net effect: a fixable upstream bug took down
      // every dependent action with an unrelated FK error, multiplying the
      // failure surface.
      //
      // The correct semantic is: a child stays gated until its parent has
      // either (a) committed (success → liveIds.remove(action.id) below) or
      // (b) been explicitly dismissed by the user via the pending-sync sheet
      // (which calls `dequeue` → next drain pass rebuilds liveIds without
      // that ID). A permanently-failed-but-still-queued parent must keep
      // blocking its children; otherwise the child runs against a server
      // that has no record of the parent's writes.
      final liveIds = <String>{for (final a in actions) a.id};

      for (final action in actions) {
        // Stop if connectivity dropped mid-drain.
        if (!ref.read(isOnlineProvider)) {
          log('Connectivity lost mid-drain, stopping', name: 'SyncService');
          break;
        }

        // Skip in-flight items (manual retry in progress).
        if (notifier.isInFlight(action.id)) continue;

        // Skip terminal items.
        if (action.retryCount >= kMaxSyncRetries) continue;

        // Skip when a dependency is still live (BUG-002). Don't increment
        // retryCount — this isn't a failure, just a "not yet". The child
        // becomes drainable in this same pass if the parent appeared
        // earlier in the FIFO slice (liveIds.remove(parentId) on success),
        // or on the next drain trigger if the parent was held this pass.
        if (action.dependsOn.any(liveIds.contains)) {
          SentryReport.addBreadcrumb(
            category: 'sync',
            message: 'Holding action ${action.id} for parent commit',
            data: {
              'action_type': _actionType(action),
              'depends_on': action.dependsOn.join(','),
            },
          );
          continue;
        }

        SentryReport.addBreadcrumb(
          category: 'sync',
          message: 'Draining action ${action.id}',
          data: {
            'action_type': _actionType(action),
            'retry_count': action.retryCount,
          },
        );

        try {
          await notifier.retryItem(action.id);

          // Success — parent committed; remove from the live set so any
          // dependent action later in the FIFO becomes drainable.
          liveIds.remove(action.id);

          // Success — emit analytics event.
          _trackSyncSucceeded(action);

          // Collect userId for batched post-drain PR cache reconciliation.
          if (action is PendingUpsertRecords && action.userId.isNotEmpty) {
            reconciledUserIds.add(action.userId);
          }

          if (action is PendingSaveWorkout) {
            drainedSaveWorkouts++;
          }
        } catch (e) {
          SentryReport.addBreadcrumb(
            category: 'sync',
            message: 'Drain failed for ${action.id}',
            data: {
              'error': e.runtimeType.toString(),
              'retry_count': action.retryCount + 1,
            },
          );

          final isTerminal = SyncErrorClassifier.isTerminal(e);
          final newRetryCount = action.retryCount + 1;

          if (isTerminal || newRetryCount >= kMaxSyncRetries) {
            _trackSyncFailed(action, e);
          } else {
            // Transient error — backoff before next item.
            await Future<void>.delayed(_backoffDuration(newRetryCount));
          }
        }
      }

      // Batch PR cache reconciliation — once per unique userId.
      await _reconcilePrCache(reconciledUserIds);

      // BUG-005: post-drain provider invalidation. Each ref.invalidate is
      // independent; one failure must not skip the rest, so they're guarded
      // individually. Invalidating these from a Notifier is the standard
      // pattern: the providers re-fetch lazily on next read.
      if (drainedSaveWorkouts > 0) {
        _invalidateAfterSaveWorkoutDrain();
      }

      // Count terminal items and update state.
      final allAfter = queue.getAll();
      final terminalCount = allAfter
          .where((a) => a.retryCount >= kMaxSyncRetries)
          .length;
      state = SyncState(terminalFailureCount: terminalCount);
    } finally {
      _draining = false;
      // Restore the recorder so subsequent (non-drain) repository calls
      // can resume feeding the recovery state machine.
      recoveryNotifier.setRecordingSuppressed(false);
    }
  }

  /// Reset terminal items' retry counts and trigger a new drain.
  Future<void> retryTerminalItems() async {
    final queue = ref.read(offlineQueueServiceProvider);
    final actions = queue.getAll();
    for (final action in actions) {
      if (action.retryCount >= kMaxSyncRetries) {
        final reset = _resetRetryCount(action);
        await queue.updateAction(reset);
      }
    }
    ref.read(pendingSyncProvider.notifier).refreshCount();
    state = const SyncState();
    await _drain();
  }

  /// Remove terminal items from queue entirely.
  Future<void> dismissTerminalItems() async {
    final queue = ref.read(offlineQueueServiceProvider);
    final actions = queue.getAll();
    for (final action in actions) {
      if (action.retryCount >= kMaxSyncRetries) {
        await queue.dequeue(action.id);
      }
    }
    ref.read(pendingSyncProvider.notifier).refreshCount();
    state = const SyncState();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped).
  static Duration _backoffDuration(int retryCount) {
    final seconds = (1 << (retryCount - 1)).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  /// Extract the Freezed union `type` discriminator for analytics.
  static String _actionType(PendingAction action) {
    return switch (action) {
      PendingSaveWorkout() => 'save_workout',
      PendingUpsertRecords() => 'upsert_records',
      PendingMarkRoutineComplete() => 'mark_routine_complete',
      PendingCreateExercise() => 'create_exercise',
    };
  }

  /// Create a copy of [action] with retryCount reset to 0 and lastError
  /// cleared.
  static PendingAction _resetRetryCount(PendingAction action) {
    return switch (action) {
      PendingSaveWorkout() => action.copyWith(
        retryCount: 0,
        lastError: null,
        errorCategory: SyncErrorCategory.none,
      ),
      PendingUpsertRecords() => action.copyWith(
        retryCount: 0,
        lastError: null,
        errorCategory: SyncErrorCategory.none,
      ),
      PendingMarkRoutineComplete() => action.copyWith(
        retryCount: 0,
        lastError: null,
        errorCategory: SyncErrorCategory.none,
      ),
      PendingCreateExercise() => action.copyWith(
        retryCount: 0,
        lastError: null,
        errorCategory: SyncErrorCategory.none,
      ),
    };
  }

  void _trackSyncSucceeded(PendingAction action) {
    try {
      final analytics = ref.read(analyticsRepositoryProvider);
      final elapsed = DateTime.now().difference(action.queuedAt).inSeconds;
      unawaited(
        analytics.insertEvent(
          userId: _userId(action),
          event: AnalyticsEvent.workoutSyncSucceeded(
            actionType: _actionType(action),
            retryCount: action.retryCount,
            elapsedSecondsInQueue: elapsed,
          ),
          platform: null,
          appVersion: null,
        ),
      );
    } catch (_) {
      // Analytics must never break the sync loop.
    }
  }

  void _trackSyncFailed(PendingAction action, Object error) {
    try {
      final analytics = ref.read(analyticsRepositoryProvider);
      final elapsed = DateTime.now().difference(action.queuedAt).inSeconds;
      unawaited(
        analytics.insertEvent(
          userId: _userId(action),
          event: AnalyticsEvent.workoutSyncFailed(
            actionType: _actionType(action),
            retryCount: action.retryCount + 1,
            errorClass: error.runtimeType.toString(),
            elapsedSecondsInQueue: elapsed,
          ),
          platform: null,
          appVersion: null,
        ),
      );
    } catch (_) {
      // Analytics must never break the sync loop.
    }
  }

  /// Best-effort userId extraction for analytics. Falls back to 'unknown'.
  static String _userId(PendingAction action) {
    return switch (action) {
      PendingSaveWorkout(:final userId) => userId,
      PendingUpsertRecords(:final userId) => userId,
      PendingMarkRoutineComplete() => 'unknown',
      PendingCreateExercise(:final userId) => userId,
    };
  }

  /// Invalidate the RPG / progress / weekly-plan provider tree so the UI
  /// reflects the new server state after a successful save_workout drain
  /// (BUG-005). Each invalidation is wrapped in try/catch — a single
  /// missing override (e.g. in a unit test that doesn't override every
  /// dependency) must NOT break the drain loop's post-success bookkeeping.
  ///
  /// Riverpod 3 does not export the `ProviderOrFamily` base type, so we
  /// can't extract a generic helper. Instead each invalidate is a closure
  /// in the list — a tiny price for type safety and clarity.
  void _invalidateAfterSaveWorkoutDrain() {
    final invalidations = <(String, void Function())>[
      ('rpgProgressProvider', () => ref.invalidate(rpgProgressProvider)),
      ('characterSheetProvider', () => ref.invalidate(characterSheetProvider)),
      ('earnedTitlesProvider', () => ref.invalidate(earnedTitlesProvider)),
      (
        'exerciseProgressProvider',
        () => ref.invalidate(exerciseProgressProvider),
      ),
      ('workoutHistoryProvider', () => ref.invalidate(workoutHistoryProvider)),
      ('weeklyPlanProvider', () => ref.invalidate(weeklyPlanProvider)),
    ];

    for (final (name, invalidate) in invalidations) {
      try {
        invalidate();
      } catch (e) {
        log('invalidate failed for $name: $e', name: 'SyncService', level: 900);
      }
    }
  }

  /// Reconcile the PR cache after a successful `upsertRecords` drain.
  ///
  /// **AW-EX-E-US1-03 fix.** Pre-fix this method called
  /// `cache.clearBox(HiveService.prCache)` to invalidate stale subset entries.
  /// That worked when the device had immediate connectivity to re-seed via
  /// `getRecordsForExercises` — but in the offline-after-drain window
  /// (drain succeeded, then connectivity dropped before the next consumer
  /// read) the empty box would falsely award PRs to every subsequent set.
  ///
  /// New contract: invalidate [prCacheBootstrapProvider]. Riverpod will
  /// re-run the bootstrap on the next read, which fetches the user's full
  /// PR list from the server and writes per-exercise entries via
  /// `seedExerciseCacheEntries`. The cache transitions from "stale" to
  /// "fresh from server truth" in a single atomic warmup, with no empty
  /// window for false positives.
  ///
  /// On warmup failure (network drop between drain and warmup), the
  /// bootstrap logs and returns — the existing per-exercise entries from
  /// the prior session remain serviceable until connectivity recovers.
  /// This is strictly more conservative than the pre-fix `clearBox`.
  ///
  /// One invalidation covers all drained userIds — the bootstrap reads the
  /// current signed-in user from `currentUserIdProvider`, so per-user
  /// looping is unnecessary.
  Future<void> _reconcilePrCache(Set<String> userIds) async {
    if (userIds.isEmpty) return;
    try {
      ref.invalidate(prCacheBootstrapProvider);
      SentryReport.addBreadcrumb(
        category: 'sync.reconcile',
        message:
            'PR cache reconciled (re-seed scheduled) for ${userIds.length} users',
      );
    } catch (e) {
      log(
        'PR cache reconciliation failed: $e',
        name: 'SyncService',
        level: 900,
      );
    }
  }
}

/// State emitted by [SyncService].
class SyncState {
  const SyncState({this.terminalFailureCount = 0});

  /// Number of queued items that have exhausted [kMaxSyncRetries].
  final int terminalFailureCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncState &&
          runtimeType == other.runtimeType &&
          terminalFailureCount == other.terminalFailureCount;

  @override
  int get hashCode => terminalFailureCount.hashCode;

  @override
  String toString() => 'SyncState(terminalFailureCount: $terminalFailureCount)';
}

/// Provides the [SyncService] as a Riverpod [Notifier].
final syncServiceProvider = NotifierProvider<SyncService, SyncState>(
  SyncService.new,
);
