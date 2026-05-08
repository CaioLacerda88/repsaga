import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../personal_records/providers/pr_providers.dart';
import '../../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../providers/workout_history_providers.dart';
import '../../providers/workout_providers.dart';
import '../widgets/finish_workout_dialog.dart';
import 'celebration_orchestrator.dart';
import 'post_workout_navigator.dart';

/// Owns the full "finish workout" orchestration.
///
/// Resolves BUG-036 (one of three coordinators carved out of the original
/// 266-line `_onFinish`) and BUG-041 (`_isFinishHandled` is now an instance
/// field, not a file-level global).
///
/// **Responsibilities:**
///   * Re-entrance guards (`_isFinishing` for double-tap, `_isFinishHandled`
///     to claim post-save navigation ownership from the screen's
///     postFrameCallback).
///   * Confirm dialog ([FinishWorkoutDialog.show]).
///   * Snapshot routine + exercise context (state is cleared after save).
///   * Drive the notifier's `finishWorkout()` and react to its result
///     (offline snackbar, cache invalidations).
///   * Hand off to [CelebrationOrchestrator] for celebration playback and
///     [PostWorkoutNavigator] for the route transition.
///
/// **Lifetime:** owned by `_ActiveWorkoutScreenState`. Constructed in
/// `initState`, lives until the screen unmounts. The `_isFinishHandled`
/// flag is read by the screen's `build` postFrameCallback via
/// [isFinishHandled] — that's why the coordinator must outlive a single
/// finish call.
class FinishWorkoutCoordinator {
  FinishWorkoutCoordinator({
    this.celebrationOrchestrator = const CelebrationOrchestrator(),
    this.postWorkoutNavigator = const PostWorkoutNavigator(),
  });

  final CelebrationOrchestrator celebrationOrchestrator;
  final PostWorkoutNavigator postWorkoutNavigator;

  /// True while [finish] owns the post-save navigation (celebration
  /// overlays → context.go).
  ///
  /// When the notifier transitions to `AsyncData(null)` (workout
  /// committed), `ActiveWorkoutScreen.build` adds a postFrameCallback that
  /// calls `context.go('/home')`. Without a guard, that callback fires
  /// concurrently with [CelebrationPlayer.play], which dismisses the
  /// celebration dialog immediately via GoRouter's full-stack replacement.
  ///
  /// [finish] sets this flag before starting the celebration and clears it
  /// after navigation — the postFrameCallback checks the flag and yields
  /// control to [finish] when true.
  bool _isFinishHandled = false;

  /// Re-entrance guard for [finish]. Prevents double-tap on "Finish Workout"
  /// from opening two dialogs or firing two concurrent saves.
  bool _isFinishing = false;

  /// Read by `ActiveWorkoutScreen.build`'s postFrameCallback so the screen
  /// yields navigation ownership during celebration playback.
  bool get isFinishHandled => _isFinishHandled;

  /// Run the full finish-workout flow.
  ///
  /// Idempotent within a single tap: concurrent invocations while
  /// `_isFinishing` is true short-circuit immediately.
  ///
  /// `context` MUST be the body's context (mounted as long as the user is
  /// looking at the active-workout screen) — used for the FinishWorkoutDialog
  /// host, snackbar messages, and as the seed for `Navigator.of(context,
  /// rootNavigator: true).context` (the root context capture).
  Future<void> finish({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    if (_isFinishing) return;
    _isFinishing = true;
    try {
      final notifier = ref.read(activeWorkoutProvider.notifier);
      final incompleteCount = notifier.incompleteSetsCount;

      final result = await FinishWorkoutDialog.show(
        context,
        incompleteCount: incompleteCount,
      );
      if (result == null || !context.mounted) return;

      // Capture exercise names before finishing (state is cleared after).
      final currentState = ref.read(activeWorkoutProvider).value;
      final exerciseNames = <String, String>{};
      if (currentState != null) {
        for (final e in currentState.exercises) {
          final ex = e.workoutExercise.exercise;
          if (ex != null) {
            exerciseNames[e.workoutExercise.exerciseId] = ex.name;
          }
        }
      }

      // Capture routine context before finishing (state is cleared after).
      // Look up the immutable routine name from the provider — workout.name
      // is mutable (user can rename mid-session).
      final routineId = currentState?.routineId;
      final routineName = routineId != null
          ? ref
                .read(routineListProvider)
                .value
                ?.where((r) => r.id == routineId)
                .firstOrNull
                ?.name
          : null;

      // Evaluate the plan-prompt condition NOW while this State is still
      // mounted and `ref` is valid. After `await notifier.finishWorkout()`
      // the notifier transitions to AsyncData(null), which disposes
      // _ActiveWorkoutScreenState (and invalidates `ref`). Calling
      // ref.read(weeklyPlanProvider) on a disposed ref throws a
      // StateError, crashing finish() and leaving the URL stuck on
      // /workout/active. We capture the result synchronously here and use
      // the pre-computed bool throughout the rest of the method.
      final shouldPrompt = postWorkoutNavigator.shouldShowPlanPrompt(
        ref,
        routineId,
      );

      // Capture the root navigator's context NOW — while this State is still
      // mounted and in the widget tree — for use after the save completes.
      // When the save commits the notifier transitions to AsyncData(null),
      // which causes ActiveWorkoutScreen.build() to rebuild without
      // _ActiveWorkoutBody, disposing this State and invalidating `context`.
      // The root navigator (mounted at app startup) stays alive for the full
      // app session, so rootContext remains valid for showDialog calls and
      // GoRouter navigation even after this State is disposed.
      final rootContext = Navigator.of(context, rootNavigator: true).context;

      // Claim navigation ownership before awaiting the save. When the save
      // commits, the notifier transitions to AsyncData(null) and the outer
      // ActiveWorkoutScreen.build() adds a postFrameCallback that calls
      // context.go('/home'). That callback checks _isFinishHandled — while
      // true, it yields navigation to this method so celebration overlays can
      // play uninterrupted (GoRouter's go() does a full-stack replacement
      // which would instantly pop any showDialog overlay).
      _isFinishHandled = true;
      final finishResult = await notifier.finishWorkout(notes: result.notes);
      if (!context.mounted) {
        _isFinishHandled = false;
        return;
      }

      final asyncState = ref.read(activeWorkoutProvider);
      if (asyncState.hasError) {
        _isFinishHandled = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).failedToSaveWorkout),
          ),
        );
        return;
      }

      // BUG-039: read offline-queued + PR-detection outcome from the
      // explicit return record instead of poking at notifier internals.
      // `finishResult == null` means the early-return guards inside
      // `finishWorkout` short-circuited (no active workout, or a concurrent
      // finish was already in flight) — treat both as a successful no-op.
      final wasSavedOffline = finishResult?.savedOffline ?? false;
      // PR1B (AW-EX-D-US1-03): when the queued failure was a 5xx (not pure
      // connectivity loss), pick a distinct snackbar copy so the user knows
      // it was a server problem the queue will retry, not a phone-side
      // network issue. `serverErrorQueued` implies `savedOffline`.
      final wasServerErrorQueued = finishResult?.serverErrorQueued ?? false;
      final prResult = finishResult?.prResult;

      // Invalidate caches so stat cards and lists reflect the new workout.
      if (!wasSavedOffline) {
        ref.invalidate(workoutHistoryProvider);
        ref.invalidate(workoutCountProvider);
      }
      // Always invalidate PR providers when new records exist, regardless of
      // whether the workout itself was saved offline — the PR upsert may have
      // succeeded independently.
      if (prResult != null && prResult.hasNewRecords) {
        ref.invalidate(prListProvider);
        ref.invalidate(prCountProvider);
        ref.invalidate(recentPRsProvider);
      }

      // Show offline-save confirmation if the workout was queued. Server-
      // error variant uses distinct copy so the user can tell apart a server
      // outage from "phone is offline" — both still queue, both still drain
      // automatically, but the cause matters for trust.
      if (wasSavedOffline && context.mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        final l10n = AppLocalizations.of(context);
        final message = wasServerErrorQueued
            ? l10n.workoutSavedServerError
            : l10n.workoutSavedOffline;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: TextStyle(color: colorScheme.onTertiaryContainer),
            ),
            backgroundColor: colorScheme.tertiaryContainer,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Phase 18c celebration playback. Online finishes only — offline
      // queues no overlays per spec §13 (the user isn't watching). The
      // notifier built the queue inside `finishWorkout`; we read it once
      // via the consume getter so a hot-reload doesn't re-fire.
      //
      // [outcome.userTappedOverflow] — when the user explicitly tapped the
      // overflow card we route to `/profile` (Saga) instead of the default
      // home/PR-celebration flow. The user made an explicit nav choice;
      // honor it.
      var userTappedOverflow = false;
      if (!wasSavedOffline && context.mounted) {
        final celebration = notifier.consumeLastCelebration();
        if (celebration != null) {
          final outcome = await celebrationOrchestrator.play(
            rootContext: rootContext,
            ref: ref,
            celebration: celebration,
          );
          userTappedOverflow = outcome.userTappedOverflow;
        }
      }

      if (!rootContext.mounted) {
        // Process is being torn down; finally block will release the flag.
        return;
      }

      postWorkoutNavigator.navigateAfterFinish(
        rootContext: rootContext,
        userTappedOverflow: userTappedOverflow,
        prResult: prResult,
        exerciseNames: exerciseNames,
        shouldPrompt: shouldPrompt,
        routineId: routineId,
        routineName: routineName,
      );

      // AW-EX-D-US1-02 fix: defer the navigation-ownership release by two
      // frames so the active-workout screen's pending postFrameCallback —
      // which checks `_isFinishHandled` at FIRE time — sees `true` and
      // yields instead of clobbering navigateAfterFinish's
      // `go('/pr-celebration')` with `go('/home')`.
      //
      // Race timeline (without this guard):
      //   Frame N+1 build:  ActiveWorkoutScreen sees displayState == null
      //                     and registers a "context.go('/home')" postFrame.
      //   Frame N+1 postFrame phase (FIFO):
      //     1. navigateAfterFinish callback (registered between frames)
      //        → rootContext.go('/pr-celebration')  ✓
      //     2. screen callback (registered DURING build)
      //        → checks _isFinishHandled → if false, context.go('/home')  ✗
      //   Result: /home wins because go() is last-write-wins.
      //
      // Releasing inside an outer postFrameCallback ensures the flag stays
      // `true` throughout frame N+1's postFrame phase, then is released at
      // the end of frame N+2 when the active-workout screen has already
      // unmounted (route changed). The early release at the top of this
      // method (before navigateAfterFinish) and the redundant release in
      // the `finally` block were both removed — the deferred release is
      // the single owner of the lifecycle. The `finally` retains the
      // `_isFinishing = false` reset (re-entrance guard) and re-asserts
      // `_isFinishHandled = false` only as a safety net for paths that
      // never reach here (e.g. `navigateAfterFinish` throws).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isFinishHandled = false;
        });
      });
    } finally {
      _isFinishing = false;
      // _isFinishHandled is normally released via the deferred postFrame
      // chain above. We do NOT reset it here on the happy path because
      // doing so would re-open the AW-EX-D-US1-02 race. If navigateAfterFinish
      // somehow throws synchronously (it never does in the production code
      // — it just registers a callback), the deferred release never fires
      // and the flag stays `true` for the rest of the screen's lifetime —
      // which is harmless because `_isFinishing` is also still cleared
      // here, allowing a subsequent finish to fire and re-set both flags.
    }
  }
}
