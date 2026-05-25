import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../weekly_plan/providers/weekly_plan_provider.dart';
import '../widgets/add_to_plan_prompt.dart';

/// Stateless helper owning the post-finish navigation choreography for the
/// finishes that do NOT route through the post-session cinematic.
///
/// **Post-PR-30c surface:** the post-session screen (`/workout/finish/:id`)
/// is the canonical destination for online + non-empty finishes — the
/// finish coordinator pushes it directly. This navigator only runs for the
/// remaining shapes (notably offline finishes that route straight to
/// `/home`, optionally with the add-to-plan prompt) and exists for two
/// reasons:
///
///   1. The plan-prompt has to be evaluated synchronously BEFORE the
///      finish-save's `AsyncData(null)` transition disposes the active-
///      workout state ([shouldShowPlanPrompt] is the contract for that).
///   2. The plan-prompt dialog lives on the root overlay and outlives the
///      finish-coordinator's lifetime; pulling it behind a stateless type
///      isolates the lifetime-sensitive `ProviderScope.containerOf` read
///      from the coordinator's `ref`.
///
/// All methods take `rootContext` (the root navigator's context, which
/// stays alive for the full app session) and use it for both the
/// `mounted` guard and provider-container access.
class PostWorkoutNavigator {
  const PostWorkoutNavigator();

  /// Whether to show the "Add to plan?" prompt after finishing.
  ///
  /// True when: the workout came from a routine, a plan exists for this
  /// week, and the routine is NOT already in the plan.
  ///
  /// **Why this is evaluated synchronously inside `_FinishWorkoutCoordinator`
  /// (BEFORE the `await notifier.finishWorkout()`):** after the save commits
  /// the active-workout notifier transitions to `AsyncData(null)`, which
  /// disposes `_ActiveWorkoutScreenState` and invalidates its `ref`.
  /// Calling `ref.read(weeklyPlanProvider)` on a disposed ref throws a
  /// `StateError`. The caller captures the bool synchronously and passes
  /// it to [navigateAfterFinish].
  bool shouldShowPlanPrompt(WidgetRef ref, String? routineId) {
    if (routineId == null) return false;
    final plan = ref.read(weeklyPlanProvider).value;
    if (plan == null) return false;
    return !plan.routines.any((r) => r.routineId == routineId);
  }

  /// Shows the add-to-plan prompt, then navigates home.
  ///
  /// **Why we read providers via [ProviderScope.containerOf] instead of `ref`:**
  /// this method is invoked from a `postFrameCallback` after the finish
  /// coordinator has awaited [CelebrationPlayer.play]. By that point the
  /// workout notifier has transitioned to `AsyncData(null)`, the screen has
  /// rebuilt, and the original `_ActiveWorkoutScreenState` is disposed —
  /// touching `ref` would throw [StateError]. The root navigator context
  /// stays alive for the full app session, so its container is the safe
  /// access path. (`navContext.mounted` guards are inert here because the
  /// root navigator never unmounts; they're left in place defensively for
  /// the post-prompt step where the user may have backgrounded the app.)
  Future<void> showPlanPromptAndGoHome(
    BuildContext navContext,
    String routineId,
    String routineName,
  ) async {
    final shouldAdd = await showAddToPlanPrompt(
      navContext,
      routineName: routineName,
    );
    if (!navContext.mounted) return;
    if (shouldAdd == true) {
      final container = ProviderScope.containerOf(navContext);
      await container
          .read(weeklyPlanProvider.notifier)
          .addRoutineToPlan(routineId);
    }
    if (!navContext.mounted) return;
    navContext.go('/home');
  }

  /// Schedule the post-finish navigation transition on the next frame for
  /// the finishes that don't route through the post-session cinematic.
  ///
  /// **Branch precedence (post-PR-30c):**
  ///   1. `userTappedOverflow` → `/profile` (Saga). Honors the explicit nav
  ///      choice the user made by tapping the overflow card. Dead code on
  ///      the post-PR-30a path (the overflow card lives on the post-session
  ///      summary panel and the screen navigates internally) but kept for
  ///      the offline / legacy pass-through branches that still consult the
  ///      celebration orchestrator's outcome.
  ///   2. Plan-prompt → fire-and-forget [showPlanPromptAndGoHome] (the
  ///      dialog lives on a separate Overlay subtree; we don't await it).
  ///   3. Default → `/home`.
  ///
  /// The PR-celebration branch (formerly precedence 2) was retired in PR
  /// 30c — every online finish with at least one logged set routes through
  /// `/workout/finish/:workoutId` (the post-session cinematic), which
  /// renders the PR confirmation in the B3 PR cut + summary panel detail
  /// row. The legacy `/pr-celebration` route was deleted in the same PR.
  ///
  /// Defers the route transition by one frame: any post-await microtask
  /// (Riverpod listeners, analytics, etc.) gets a clean frame boundary
  /// before the route teardown begins.
  void navigateAfterFinish({
    required BuildContext rootContext,
    required bool userTappedOverflow,
    required bool shouldPrompt,
    required String? routineId,
    required String? routineName,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rootContext.mounted) return;
      if (userTappedOverflow) {
        rootContext.go('/profile');
      } else if (shouldPrompt) {
        // Fire-and-forget: dialog lives on a separate Overlay subtree, so
        // we don't need to await it here. The dialog handles its own
        // navigate-home on dismiss.
        unawaited(
          showPlanPromptAndGoHome(rootContext, routineId!, routineName!),
        );
      } else {
        rootContext.go('/home');
      }
    });
  }
}
