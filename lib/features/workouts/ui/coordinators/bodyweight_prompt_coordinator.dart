import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/snackbar_tap_out_dismiss_scope.dart';
import '../../../profile/models/profile.dart';
import '../../../profile/providers/bodyweight_prompt_dismissal_provider.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../../profile/ui/widgets/bodyweight_row.dart';
import '../../models/active_workout_state.dart';

/// Owns the lazy "set your body weight" prompt shown the first time a user
/// completes a set on a `uses_bodyweight_load = true` exercise during a
/// session, when their profile has no bodyweight on file and they haven't
/// dismissed the prompt forever.
///
/// **Why a coordinator (not in `ActiveWorkoutNotifier.completeSet`):**
/// keeps the data-mutation method (`completeSet`) free of cross-cutting
/// concerns. The notifier's job is "toggle a set's `isCompleted`"; it
/// has no business reading Hive prefs, profile state, or UI plumbing
/// (showing snackbars, opening bottom sheets). Mirrors the existing
/// [DiscardWorkoutCoordinator] / [FinishWorkoutCoordinator] pattern —
/// the screen state owns the coordinator instance and feeds it state
/// transitions via `ref.listen`.
///
/// **Lifetime:** matches the `_ActiveWorkoutScreenState`'s lifetime.
/// The screen owns this coordinator; tearing down the screen tears
/// down the coordinator (and its session-shot flag), which is the
/// correct semantic — "session" = "active workout screen mounted".
///
/// **Trigger contract:** [maybeShow] is called from a `ref.listen` on
/// `activeWorkoutProvider`. The coordinator diffs `previous` vs `next`
/// state to detect a SET that newly transitioned `isCompleted: false → true`
/// on an exercise whose [Exercise.usesBodyweightLoad] is `true`. All four
/// gates must hold:
///
///   1. The set just transitioned to completed (not deleted, not weight-
///      edited, not a different set).
///   2. The hosting exercise has `usesBodyweightLoad == true`.
///   3. The current profile has `bodyweightKg == null`.
///   4. The Hive prompt-dismissed flag is `false`.
///   5. The in-memory session-shot flag [_shownThisSession] is `false`.
///
/// Once shown, [_shownThisSession] flips so subsequent qualifying set-
/// completions in the same screen-instance no-op. Lifecycle-ends
/// (screen disposed → fresh coordinator on next workout) reset that
/// flag naturally.
class BodyweightPromptCoordinator {
  /// In-memory one-shot guard: at most one prompt per active-workout
  /// screen lifetime, regardless of how many qualifying sets the user
  /// completes. Reset implicitly by recreating the coordinator (which
  /// happens when a new active-workout screen mounts).
  ///
  /// **Why session-scoped instead of permanent:** the user might
  /// genuinely change their mind mid-workout (closes the snackbar
  /// without tapping anything, then realises later that pull-up XP is
  /// going to undercount). A fresh workout = a fresh chance. The
  /// permanent "never again" lock is the Hive flag set by Skip.
  bool _shownThisSession = false;

  @visibleForTesting
  bool get debugShownThisSession => _shownThisSession;

  /// Diff [previous] against [next]; if a set newly became completed on
  /// a `usesBodyweightLoad` exercise AND all gating conditions hold,
  /// show the prompt SnackBar.
  ///
  /// Reads from `ref` for the Hive-flag and profile providers — these
  /// are sync notifiers (the flag) or `AsyncNotifier`s where we already
  /// have the value cached (`profileProvider`); we read `.value` rather
  /// than awaiting, accepting that an early-load profile state means
  /// the prompt waits for the next qualifying set after the profile
  /// resolves. That's fine — the prompt is non-blocking and the user
  /// always has the profile-settings entry point.
  ///
  /// **No-op when [context] is unmounted.** The coordinator is owned by
  /// the screen, but `ref.listen` callbacks can fire across a tear-down
  /// boundary; the explicit `context.mounted` guard prevents
  /// `ScaffoldMessenger.of(context)` from throwing on a stale context.
  void maybeShow({
    required BuildContext context,
    required WidgetRef ref,
    required ActiveWorkoutState? previous,
    required ActiveWorkoutState? next,
  }) {
    if (_shownThisSession) return;
    if (next == null) return;
    if (!context.mounted) return;

    // Detect a fresh isCompleted: false → true transition on a uses-
    // bodyweight-load exercise. We compare per-exercise so a state
    // change that only touched a non-bodyweight exercise (e.g. weight
    // edit elsewhere) cannot trigger.
    final triggered = _findNewlyCompletedBodyweightSet(previous, next);
    if (!triggered) return;

    // Profile gate: skip when bodyweight is already set, or when the
    // profile isn't loaded yet (we'll catch the next qualifying set).
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    if (profile.bodyweightKg != null) return;

    // Permanent dismissal gate.
    final dismissed = ref.read(bodyweightPromptDismissalProvider);
    if (dismissed) return;

    // Flip the session-shot flag BEFORE showing so a re-entrant call
    // from a coalesced state notification can't double-fire. Defensive
    // — Riverpod's `ref.listen` callbacks are single-threaded, but
    // pinning the flag here removes a class of potential race.
    _shownThisSession = true;
    _showPromptSnackBar(context, ref, profile);
  }

  /// True iff [next] contains a set whose `isCompleted == true` on a
  /// [Exercise.usesBodyweightLoad] == true exercise AND that same set
  /// id was either absent or `isCompleted == false` in [previous].
  ///
  /// Detecting via id-keyed lookup (rather than count comparison) is
  /// load-bearing: the user could complete one set on exercise A and
  /// uncomplete one on exercise B in the same notification — a count
  /// diff would miss the transition. Set ids are stable UUIDs across
  /// `copyWith`, so the lookup is O(total sets) but reliable.
  bool _findNewlyCompletedBodyweightSet(
    ActiveWorkoutState? previous,
    ActiveWorkoutState? next,
  ) {
    if (next == null) return false;

    // Build a quick lookup of previous set completion state by set id.
    // Empty when previous is null (very first state emission) — every
    // currently-completed set is then treated as a potential trigger.
    final previousCompletion = <String, bool>{};
    if (previous != null) {
      for (final ex in previous.exercises) {
        for (final s in ex.sets) {
          previousCompletion[s.id] = s.isCompleted;
        }
      }
    }

    for (final ex in next.exercises) {
      final exerciseModel = ex.workoutExercise.exercise;
      if (exerciseModel == null) continue;
      if (!exerciseModel.usesBodyweightLoad) continue;

      for (final s in ex.sets) {
        if (!s.isCompleted) continue;
        final wasCompleted = previousCompletion[s.id] ?? false;
        if (!wasCompleted) {
          return true;
        }
      }
    }
    return false;
  }

  /// Render the prompt as a countdown SnackBar. Reuses the
  /// [SnackBarTapOutDismissScope.showCountdownSnackBar] factory the
  /// rest of the screen uses (add-exercise undo, swipe-to-delete undo)
  /// so visual treatment stays consistent.
  ///
  /// Two actions in the snack interior, mutually exclusive:
  ///   * **Set now** — opens [showBodyweightEditorSheet] (the same sheet
  ///     the profile-settings row uses, deep-linked here per the 24c-7
  ///     reuse contract). On successful save the profile invalidates and
  ///     subsequent set completions read the fresh value.
  ///   * **Skip** — calls
  ///     [BodyweightPromptDismissalNotifier.markDismissed] so the prompt
  ///     never re-appears across sessions / app launches.
  ///
  /// Auto-dismiss after the SnackBar's duration without an action tap
  /// counts as "not now, ask again next workout" — the session-shot
  /// flag stays true for the rest of this screen's life, but the Hive
  /// flag is NOT set, so a fresh workout will prompt again.
  void _showPromptSnackBar(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) {
    final l10n = AppLocalizations.of(context);
    final scope = SnackBarTapOutDismissScope.maybeOf(context);
    if (scope == null) {
      // Defensive — production wires the scope around the active-workout
      // body. A widget test that omits the scope simply observes no
      // snack rather than crashing.
      return;
    }

    scope.showCountdownSnackBar(
      context: context,
      message: l10n.bodyweightPromptTitle,
      duration: const Duration(seconds: 6),
      // 6s is longer than the 3.5s used for add-exercise undo because
      // the user has TWO decisions to make (Set now vs Skip vs ignore)
      // and "Set now" opens a sheet — they need the snack visible long
      // enough to read + decide + tap. 6s matches the longer-form
      // celebration overlay timing already in the app.
      //
      // Auto-dismiss WITHOUT the user tapping Skip is semantically
      // "not now — ask again next workout": the in-memory
      // [_shownThisSession] flag stays true for the rest of this
      // screen's life, but the Hive dismissal flag is NOT set, so a
      // new workout (= new coordinator instance) will prompt again on
      // the next qualifying set. Only the explicit Skip tap writes the
      // forever-flag.
      action: SnackBarAction(
        label: l10n.bodyweightPromptSetNow,
        onPressed: () {
          // Re-resolve the latest profile — it may have changed between
          // the trigger (where we passed `profile`) and the user tap if
          // some other surface updated it concurrently. Use the live
          // value if available, else fall back to the captured one.
          final live = ref.read(profileProvider).value ?? profile;
          showBodyweightEditorSheet(context, profile: live);
        },
      ),
      secondaryAction: SnackBarAction(
        label: l10n.bodyweightPromptSkip,
        onPressed: () {
          // Fire-and-forget: the Hive write is fast, and the user-
          // visible contract ("never show this prompt again") is the
          // in-memory state flip that the dismissal notifier performs
          // synchronously after the async put completes. A failed write
          // is logged via Hive's own error path and at worst the prompt
          // re-appears once on next launch — acceptable for a non-
          // critical UX nudge.
          ref.read(bodyweightPromptDismissalProvider.notifier).markDismissed();
        },
      ),
    );
  }

  /// Called from the screen when it's about to dispose. No resources to
  /// release — the field-only state goes with the coordinator instance.
  /// Method exists for symmetry with future coordinators that DO need
  /// teardown.
  void dispose() {}
}
