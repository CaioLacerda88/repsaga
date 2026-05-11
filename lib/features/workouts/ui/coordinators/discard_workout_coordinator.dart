import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../models/active_workout_state.dart';
import '../../providers/workout_providers.dart';
import '../widgets/discard_workout_dialog.dart';

/// Owns the "discard workout" lifecycle.
///
/// Resolves BUG-041: previously `_isShowingDiscardDialog` was a file-level
/// `bool` shared between the outer screen's PopScope handler and the inner
/// body's AppBar close button. Hoisting it to a per-screen instance field
/// (this coordinator, owned by `_ActiveWorkoutScreenState`) eliminates the
/// global without losing the "single dialog at a time across both call
/// sites" guarantee — both call sites share the same coordinator instance.
///
/// **Lifetime:** as long as the active-workout screen's State. The screen
/// owns this coordinator and disposes it implicitly when its State is torn
/// down (no resources to release; the field is just a flag).
class DiscardWorkoutCoordinator {
  /// Re-entrance guard for [show]. Prevents stacked discard dialogs when the
  /// user taps the AppBar close button while a PopScope-triggered dialog is
  /// already open (or vice-versa).
  bool _isShowingDialog = false;

  /// Per-call generation counter. Incremented at the top of each [show]
  /// invocation that passes the re-entrance guard, and captured into a
  /// local `myGeneration`. The cleanup `finally` only clears
  /// [_isShowingDialog] when the finishing call's `myGeneration` still
  /// matches [_dialogGeneration] — i.e. when the finishing call still owns
  /// the latest dialog lifecycle.
  ///
  /// **Why this is required (PR-3 review C1).** Pre-fix, the outer `finally`
  /// unconditionally cleared the flag. The race:
  ///   1. First show() awaits `discardWorkout()` and stalls.
  ///   2. [notifyStateChanged] clears [_isShowingDialog] mid-stall (S1 path).
  ///   3. Second show() runs, sets [_isShowingDialog] back to true,
  ///      opens dialog #2.
  ///   4. First call's stalled completer resolves. Its `finally` fires AND
  ///      sets [_isShowingDialog] = false — **even though dialog #2 is
  ///      still open.**
  ///   5. A third tap during that window now passes the guard and stacks
  ///      a third dialog.
  ///
  /// With the generation counter, step 4's finally observes
  /// `myGeneration != _dialogGeneration` (the second call already
  /// incremented past it) and bails out without touching the flag. The
  /// second call's own finally is the only one that can release the guard,
  /// which is exactly the structural guarantee we want.
  int _dialogGeneration = 0;

  /// True while a `discardWorkout()` future is in-flight inside [show]. The
  /// distinction matters for the PR-3 S1 fix: when `cancelLoading` restores
  /// state mid-discard, we want to clear [_isShowingDialog] WITHOUT having
  /// to wait for the held network. The cleared flag lets the user re-open
  /// the discard dialog immediately; the still-in-flight original call
  /// finishes silently in the background (its post-await state poll bails
  /// out cleanly when it sees state has been restored).
  bool _awaitingDiscardResult = false;

  /// Show the discard confirmation dialog and, on confirm, run the discard
  /// notifier action and navigate home.
  ///
  /// Idempotent within a single dialog lifecycle — concurrent invocations
  /// while a dialog is already up are no-ops.
  ///
  /// **PR-3 (S1) — re-entrance window after cancel-mid-discard.** When
  /// `cancelLoading` fires while `discardWorkout()` is still awaiting a
  /// stalled DELETE, the notifier restores the active-workout state
  /// immediately (`AsyncData(non-null)`) so the user sees their workout
  /// re-appear. The await on `discardWorkout()` here, however, stays
  /// suspended until the held network call eventually resolves — and
  /// without the fix `_isShowingDialog` would stay `true` for the
  /// duration of the held call. Any subsequent discard tap during that
  /// window would silently no-op on the re-entrance guard, even though
  /// the screen is back to a fully interactive state.
  ///
  /// Fix shape (Option B in `BUGS.md` PR-3 / S1): the screen calls
  /// [notifyStateChanged] from a `ref.listen` on `activeWorkoutProvider`.
  /// Whenever state transitions back to `AsyncData(non-null)` while a
  /// discard call is in flight, the coordinator clears [_isShowingDialog]
  /// even though the `await` is still parked. The still-in-flight call
  /// observes the cleared flag via [_awaitingDiscardResult] and skips the
  /// success-path navigation; its `finally` re-clears the (already-false)
  /// flag harmlessly.
  ///
  /// Option A (state-poll post-await) was rejected because the post-await
  /// runs AFTER the held network completes, which means a re-entrance
  /// during the stall would still see `_isShowingDialog == true`. Option
  /// B fires from the state-listener's synchronous notification path,
  /// which IS observable during the stall.
  Future<void> show(
    BuildContext context,
    WidgetRef ref,
    ActiveWorkoutState state,
  ) async {
    if (_isShowingDialog) return;
    _isShowingDialog = true;
    final myGeneration = ++_dialogGeneration;
    try {
      final elapsed = DateTime.now().toUtc().difference(
        state.workout.startedAt,
      );
      final shouldDiscard = await DiscardWorkoutDialog.show(
        context,
        elapsedDuration: elapsed,
      );
      if (shouldDiscard == true && context.mounted) {
        _awaitingDiscardResult = true;
        try {
          await ref.read(activeWorkoutProvider.notifier).discardWorkout();
        } finally {
          _awaitingDiscardResult = false;
        }

        // PR-3 S1 — if [notifyStateChanged] cleared the guard while we
        // were awaiting (cancel-mid-discard restored state), the second
        // call's dialog has already opened on top of this stale call's
        // suspended state. Either way, the right action here is to bail
        // out of the success path: a non-null state means the workout
        // is back, so we must not navigate home.
        if (!context.mounted) return;
        final restored = ref.read(activeWorkoutProvider).value != null;
        if (restored) return;

        final result = ref.read(activeWorkoutProvider);
        if (result.hasError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).failedToDiscardWorkout,
              ),
            ),
          );
          return;
        }
        context.go('/home');
      }
    } finally {
      // C1 (PR-3 review) — only release the guard when this call still owns
      // the latest dialog lifecycle. If a second show() ran while we were
      // stalled and bumped [_dialogGeneration], that second call now owns
      // the open dialog and our cleanup MUST be a no-op — otherwise we
      // would clear the flag while dialog #2 is still up and a third tap
      // would stack on top.
      if (_dialogGeneration == myGeneration) {
        _isShowingDialog = false;
      }
    }
  }

  /// Hook called by the hosting screen when [activeWorkoutProvider] emits
  /// a new state. When a discard call is in flight AND the new state is
  /// `AsyncData(non-null)`, that means `cancelLoading` restored the
  /// workout — clear the re-entrance guard so the user can re-discard
  /// without waiting on the held network.
  ///
  /// Safe to call on every state change; it only mutates the flag inside
  /// the narrow window. Idempotent.
  void notifyStateChanged(AsyncValue<ActiveWorkoutState?> newState) {
    if (!_awaitingDiscardResult) return;
    if (newState.value != null) {
      // State restored mid-discard — the user can retry. Drop the guard.
      _isShowingDialog = false;
    }
  }
}
