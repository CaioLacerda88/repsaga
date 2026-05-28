import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';

import '../../../../core/device/platform_info.dart';
import '../../../../core/local_storage/hive_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../analytics/data/analytics_repository.dart';
import '../../../analytics/data/models/analytics_event.dart';
import '../../../analytics/providers/analytics_providers.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../personal_records/providers/pr_providers.dart';
import '../../../routines/providers/notifiers/routine_list_notifier.dart';
import '../../../rpg/domain/celebration_queue.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/celebration_event.dart';
import '../../../rpg/providers/rpg_progress_provider.dart';
import '../../models/active_workout_state.dart';
import '../post_session/post_session_controller.dart';
import '../../providers/workout_history_providers.dart';
import '../../providers/workout_providers.dart';
import '../widgets/empty_session_guard_sheet.dart';
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

      // Phase 30 PR 30a — empty-session guard (mockup §5 State 11).
      // BEFORE the finish dialog runs. When the user taps "Finish" with
      // zero sets logged, show a disambiguation sheet instead of pushing
      // through to the post-session screen. Playing a celebration for
      // zero work would train users that the RPG layer is fake.
      if (notifier.totalSetsCount == 0) {
        // Phase 32 PR 32d — fire `session_zero_xp` BEFORE showing the
        // guard sheet so the funnel signal lands regardless of which
        // branch the user picks (discard / continue / dismiss). The
        // event captures intent-to-finish-blocked-by-guard; the
        // subsequent `workoutDiscarded` (if the user discards) is a
        // separate signal and is wired independently inside the notifier.
        notifier.recordZeroXpSession();
        final l10n = AppLocalizations.of(context);
        final guard = await EmptySessionGuardSheet.show(
          context,
          title: l10n.emptyGuardTitle,
          body: l10n.emptyGuardBody,
          discardLabel: l10n.emptyGuardDiscard,
          continueLabel: l10n.emptyGuardContinue,
        );
        if (!context.mounted) return;
        switch (guard) {
          case EmptySessionGuardResult.discarded:
            await notifier.discardWorkout();
            if (!context.mounted) return;
            context.go('/home');
            return;
          case EmptySessionGuardResult.continueTraining:
          case EmptySessionGuardResult.cancelled:
            // Stay on the active workout screen.
            return;
        }
      }

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
      //
      // Cluster: `async-caller-broke-snackbar` / `async-caller-broke-nav`.
      final shouldPrompt = postWorkoutNavigator.shouldShowPlanPrompt(
        ref,
        routineId,
      );

      // Phase 30 PR 30a — same `ref`-lifetime contract as `shouldPrompt`
      // above. The post-session push branch needs the workout count from
      // BEFORE this finish to render the saga number ("Saga {n+1}"). Reading
      // `workoutCountProvider` AFTER `await notifier.finishWorkout()` throws
      // `Bad state: Using "ref" when a widget is about to or has been
      // unmounted is unsafe` because the active-workout State has been
      // disposed by then. Capture the value synchronously here; the value
      // is exactly "prior count" by definition (the just-finished workout
      // has not yet been counted), so no subtraction is needed downstream.
      //
      // This was the PR 30a regression that surfaced under QA — the URL
      // stayed on `/workout/active` because the exception fired before the
      // `addPostFrameCallback` that schedules `rootContext.go(...)`. See the
      // `finish_workout_coordinator_post_session_navigation_test.dart`
      // regression test that pins the contract.
      final priorWorkoutCount = ref.read(workoutCountProvider).value ?? 0;

      // Phase 30 PR 30a Bug C v2 (2026-05-23) — same lifecycle contract as
      // priorWorkoutCount above. `notifier.totalSetsCount` reads from
      // `state.value`, which is AsyncData(null) AFTER finishWorkout()
      // transitions the notifier state. The post-session-push predicate
      // below (`shouldPushPostSession`) needs the pre-finish set count to
      // evaluate correctly — reading totalSetsCount post-await returns 0
      // for every session, dropping every finish onto the legacy /home
      // navigator and skipping the cinematic entirely.
      //
      // Cluster: `async-caller-broke-snackbar` / `async-caller-broke-nav`.
      // Third occurrence of this lifecycle pattern in this file — same
      // class as the 271c20d priorWorkoutCount fix. If you're adding
      // ANOTHER provider/notifier read to this method whose return value
      // depends on `state.value`, capture it BEFORE the
      // `await notifier.finishWorkout()` at line ~202.
      final preFinishSetsCount = notifier.totalSetsCount;

      // Phase 31 Blocker 1 — capture pre-finish ranks per body part so the
      // Mission Debrief can render accurate `Rank N → M` arrows even when
      // a single session jumps multiple ranks (e.g. 5 → 8). MUST be read
      // BEFORE `notifier.finishWorkout()` mutates the RPG progress
      // snapshot. Same `ref`-lifetime contract as the captures above —
      // reading rpgProgressProvider AFTER the await throws because the
      // active-workout State is disposed and the ref invalidated.
      //
      // Defensive empty-map fallback so legacy callers (none in prod, but
      // any test fixture / pass-through path) still construct a valid
      // PostSessionParams; the controller's `_buildInitial` re-derives a
      // sane default per BP when entries are missing.
      final preFinishProgress = ref.read(rpgProgressProvider).value;
      final bpRankBefore = <BodyPart, int>{};
      if (preFinishProgress != null) {
        preFinishProgress.byBodyPart.forEach((bp, row) {
          bpRankBefore[bp] = row.rank;
        });
      }

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
        // PR-3 (review fix) — use the ROOT messenger here, not the route-scoped
        // one installed by `ActiveWorkoutScreen`. The error path stays on the
        // active-workout screen (we early-return below), so technically the
        // local messenger would also work; using `rootContext` keeps all
        // finish-coordinator snackbars on a single, predictable messenger
        // (the offline-saved snackbar a few lines below MUST be on the root
        // because it's shown immediately before navigating away from the
        // screen, which would otherwise destroy a local messenger's queue).
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(rootContext).failedToSaveWorkout),
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
        // PR-3 (review fix) — must use the ROOT messenger. Local messengers
        // installed by `ActiveWorkoutScreen` for in-screen undo affordances
        // (H5 add-exercise, swipe-to-delete set, etc.) get torn down with
        // the route the moment `navigateAfterFinish` runs below. A snackbar
        // posted to a local messenger immediately before navigation would
        // never display on the destination screen — exactly the behavior we
        // want for in-screen undos but exactly what we DON'T want for
        // "Saved offline" / "Saved (server retry)" confirmations that need
        // to follow the user to /home or /workout/finish/:workoutId.
        final colorScheme = Theme.of(rootContext).colorScheme;
        final l10n = AppLocalizations.of(rootContext);
        final message = wasServerErrorQueued
            ? l10n.workoutSavedServerError
            : l10n.workoutSavedOffline;
        ScaffoldMessenger.of(rootContext).showSnackBar(
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
      // [outcome.userTappedOverflow] — pre-PR-30a this came from the
      // mid-workout overflow card. Post-PR-30a (Path A), the overflow
      // card lives on the post-session summary panel and the screen
      // navigates to /profile internally via its onContinue callback —
      // so this field is dead code for online-with-reward finishes
      // (the post-session route owns nav). Kept for backward compat with
      // offline branches + Phase 29.5's pass-through orchestrator.
      var userTappedOverflow = false;
      final celebration = notifier.consumeLastCelebration();
      if (!wasSavedOffline && context.mounted) {
        if (celebration != null) {
          // Phase 32 PR 32d — emit `first_rank_up` per body-part rank-up
          // delta the user has never produced before. Gated by a Hive
          // cache (per-user list of fired body-part slugs) so the event
          // fires at most once per (user, body_part) lifetime.
          //
          // Fires BEFORE the celebration orchestrator plays so the event
          // ordering reflects "rank-up detected → may animate" — even if
          // the orchestrator's playback is interrupted (e.g. user
          // backgrounds the app), the analytics signal lands.
          //
          // Tradeoff: the Hive cache is device-local. A user installing
          // on a new device will re-fire `first_rank_up` for body parts
          // they already crossed previously. Acceptable because the event
          // is informational (not used for billing/gating); avoiding the
          // per-finish Supabase query for "have I ever fired this?" is
          // worth the occasional re-fire on new-device installs.
          await FirstRankUpEmitter.emitForCelebration(
            ref: ref,
            celebration: celebration,
          );
          // Re-check after the analytics await: a process tear-down
          // between the Hive write and the orchestrator hand-off would
          // otherwise pass a stale rootContext to `play`.
          if (!rootContext.mounted) return;
          final outcome = await celebrationOrchestrator.play(
            rootContext: rootContext,
            ref: ref,
            celebration: celebration,
          );
          userTappedOverflow = outcome.userTappedOverflow;
        }
      }

      if (!rootContext.mounted) {
        // Process is being torn down; the finally block will clear
        // `_isFinishing`. `_isFinishHandled` stays `true` for the screen's
        // remaining lifetime, which is harmless — the screen is already
        // unmounting along with the rest of the route.
        return;
      }

      // Post-PR-30c — the legacy `/pr-celebration` route is gone and the
      // post-session cinematic owns PR confirmation. The `prResult` value
      // flows into the post-session route's `PostSessionParams` for the B3
      // PR cut + summary panel detail row; offline finishes intentionally
      // suppress that branch (the workout hasn't committed server-side so
      // we don't surface a "NEW PR" until the queue drains).
      //
      // The pre-30c contract pinned by OFFLINE-001/002/005/007 — offline
      // finish always lands on /home — is preserved: the offline path
      // skips `shouldPushPostSession` below and falls through to
      // `postWorkoutNavigator.navigateAfterFinish`, whose default branch
      // is `rootContext.go('/home')`. The PR cache invalidations above
      // still happen — those are about cache reconciliation (the PR
      // upsert may have committed independently of the workout), not
      // navigation.
      final navigationPrResult = wasSavedOffline ? null : prResult;

      // Phase 30 PR 30a (Bug C, 2026-05-23) — every online finish with at
      // least one logged set routes through the post-session cinematic.
      //
      // The original cut gated on `hasRewardEvent || hasNewRecords`, which
      // dropped baseline XP-only sessions (mockup §5 State 2 — the most
      // common state) onto the legacy /home navigator and skipped the
      // cinematic entirely. The notifier author already documented the
      // intent at active_workout_notifier.dart:1825 — "the screen renders
      // a baseline cinematic for empty queues too (the B1 XP slam is the
      // user's primary feedback even on a session with no rank-up / no
      // PR)". The empty-session guard at line 95 above already returns
      // early for zero-set finishes, so the `totalSetsCount > 0` clause
      // is redundant-safe defense in depth (kept for clarity at this
      // call site — future readers shouldn't have to chase the guard up
      // the method to know the contract).
      //
      // Path A confirmed by user 2026-05-23: PR-bearing online sessions
      // also route through the new post-session route. /pr-celebration
      // becomes dead-on-online; final retire stays in PR 30c.
      //
      // Cluster: `spec-caption-vs-implementation-drift` — predicate
      // mirrored the legacy "show only if PR" rule from /pr-celebration
      // and missed the mockup §5 State 2 baseline cinematic intent.
      final shouldPushPostSession = !wasSavedOffline && preFinishSetsCount > 0;

      if (shouldPushPostSession) {
        final l10n = AppLocalizations.of(rootContext);
        final totalXpDelta = notifier.consumeLastSessionTotalXpDelta();
        final bpDeltasNum = notifier.consumeLastSessionBpDeltas();
        final bpDeltas = <BodyPart, int>{
          for (final entry in bpDeltasNum.entries)
            entry.key: entry.value.round(),
        };
        // Normalize the empty-queue case: baseline XP-only sessions have
        // `consumeLastCelebration() == null` (the notifier short-circuits
        // when `events.isEmpty` at active_workout_notifier.dart:1843).
        // The post-session route always needs a valid queueResult — the
        // choreographer's S2 path renders cuts based on tier + deltas
        // even when the queue is empty. The screen layer never sees null;
        // the coordinator normalizes here.
        final queueResultForRoute =
            celebration ??
            const CelebrationQueueResult(queue: <CelebrationEvent>[]);
        final params = PostSessionParams(
          queueResult: queueResultForRoute,
          prResult: navigationPrResult,
          exerciseNames: exerciseNames,
          totalXpEarned: (totalXpDelta ?? 0).round(),
          bpXpDeltas: bpDeltas,
          // TODO(30b): populate from the pre-finish snapshot so Beat 2 bars
          // animate from the true pre-session rank progress instead of 0%.
          // The empty default makes the Beat 2 tally cut visually consistent
          // today (every bar starts empty + fills to the post-finish value)
          // but loses the "watch your prior progress get added to" beat the
          // mockup §3 Variant A storyboard intends. See WIP.md PR 30a
          // "Known limitations carried forward" + PR 30b plan.
          bpProgressFractionPre: _emptyBpFractions(),
          // Phase 31 Blocker 1 — pre-finish per-BP rank snapshot captured
          // above. Plumbed to PostSessionState.bpRankBefore so the Mission
          // Debrief renders correct `Rank N → M` arrows on multi-rank-jump
          // sessions.
          bpRankBefore: bpRankBefore,
          bpFirstAwakening: queueResultForRoute.queue
              .whereType<FirstAwakeningEvent>()
              .map((e) => e.bodyPart)
              .toSet(),
          // Captured BEFORE `await notifier.finishWorkout()` — see the
          // `priorWorkoutCount` capture above. Reading `ref` here would
          // throw because the active-workout State is disposed by now.
          priorFinishedWorkoutCount: priorWorkoutCount,
          // PR 32g (Bug 1) — read the duration the notifier computed in
          // UTC. Pre-fix this branch called `_computeDurationMinutes` which
          // read `currentState.workout.finishedAt` (always null pre-await),
          // so the fallback `?? DateTime.now()` (LOCAL) was the only branch
          // taken — disagreeing with the notifier's persisted
          // `DateTime.now().toUtc()` by the device UTC offset every finish.
          // The notifier is authoritative for the workout timeline; we
          // consume the single source of truth via `finishResult`.
          // Cluster: `async-caller-broke-snackbar` (extended).
          durationMinutes: (finishResult?.durationSeconds ?? 0) ~/ 60,
          setsCount: _computeSetsCount(currentState),
          tonnageTons: _computeTonnage(currentState),
          // Phase 31 Pass 1 — carry the per-exercise + per-set snapshot so
          // the controller can project `topLifts` for the S2 Mission Debrief
          // table. Same lifecycle as the rest of this builder: read from
          // [currentState] which was captured BEFORE finishWorkout
          // disposed the active workout. Falls back to an empty list when
          // the snapshot is missing (defensive — the post-session push
          // only fires when [preFinishSetsCount > 0] which implies a
          // non-null [currentState]).
          exercises: currentState?.exercises ?? const [],
          l10n: l10n,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!rootContext.mounted) return;
          // The workoutId is the just-finished workout's id, captured from
          // the snapshot taken before finishWorkout disposed the state.
          final workoutId = currentState?.workout.id ?? 'unknown';
          rootContext.go('/workout/finish/$workoutId', extra: params);
        });
        // Defer the navigation-ownership release for two frames so the
        // active-workout screen's postFrame doesn't clobber our go().
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _isFinishHandled = false;
          });
        });
        return;
      }

      // PR-celebration branch retired in PR 30c — `navigationPrResult` is
      // only consumed by the post-session route above. Offline / pass-through
      // finishes go through the navigator's slimmed three-way switch
      // (overflow → /profile, plan-prompt → showPlanPromptAndGoHome, else
      // → /home).
      postWorkoutNavigator.navigateAfterFinish(
        rootContext: rootContext,
        userTappedOverflow: userTappedOverflow,
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
      // the single owner of the lifecycle. The `finally` only resets
      // `_isFinishing`. `_isFinishHandled` is NOT reset in `finally` —
      // on exception paths (e.g. `navigateAfterFinish` throws synchronously,
      // which it shouldn't in production) the flag stays `true` for the
      // screen's lifetime. That's harmless because `_isFinishing` is
      // cleared and the next retry call re-arms the flag normally at
      // line 146.
      //
      // The secondary safety net for late rebuilds is `context.mounted` at
      // the call site in `active_workout_screen.dart:75`: once the route
      // has changed, the screen's context is no longer mounted and any
      // late postFrameCallback (e.g. one Riverpod schedules after the
      // deferred release fires) returns immediately without calling
      // `context.go('/home')`.
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

  // ─── Post-session helpers (Phase 30 PR 30a) ────────────────────────────

  Map<BodyPart, double> _emptyBpFractions() {
    return <BodyPart, double>{};
  }

  int _computeSetsCount(ActiveWorkoutState? state) {
    if (state == null) return 0;
    var n = 0;
    for (final ex in state.exercises) {
      for (final s in ex.sets) {
        if (s.isCompleted) n += 1;
      }
    }
    return n;
  }

  double _computeTonnage(ActiveWorkoutState? state) {
    if (state == null) return 0;
    var kg = 0.0;
    for (final ex in state.exercises) {
      for (final s in ex.sets) {
        if (!s.isCompleted) continue;
        final w = s.weight ?? 0;
        final r = s.reps ?? 0;
        kg += w * r;
      }
    }
    return kg / 1000.0;
  }
}

/// Phase 32 PR 32d — Hive-cached emitter for the `first_rank_up` analytics
/// event.
///
/// **Why this lives in the coordinator file (no new file):** the WIP plan
/// for this PR scopes "no new files except tests". The class is small +
/// focused enough to colocate; tests reach it via the public API
/// ([writeFiredSlugs], [readFiredSlugs], [emitForCelebration]).
///
/// **Idempotency contract:** at most one `first_rank_up` event fires per
/// (user_id, body_part) lifetime, gated by a Hive list at key
/// `firstRankUpEmittedBPs:<user_id>` in the [HiveService.userPrefs] box.
/// The cache is device-local — re-installing on a new device produces a
/// fresh slate (acceptable for an informational event; saves a per-finish
/// Supabase round-trip).
///
/// **No-ops cleanly:**
///   * Missing user id (logged-out edge) → silent no-op.
///   * Celebration with no [RankUpEvent] → silent no-op.
///   * Hive box missing (test harness without init) → caught + treated as
///     "no slugs fired yet" so a test environment doesn't crash production
///     code paths.
class FirstRankUpEmitter {
  FirstRankUpEmitter._();

  /// Hive key prefix for the fired-body-part list. Composed with the user
  /// id so multiple accounts on one device stay isolated.
  @visibleForTesting
  static const String hiveKeyPrefix = 'firstRankUpEmittedBPs:';

  /// Compose the per-user Hive key. Visible so tests can seed + inspect
  /// the cache directly.
  @visibleForTesting
  static String hiveKeyFor(String userId) => '$hiveKeyPrefix$userId';

  /// Read the list of body-part slugs that have already fired
  /// `first_rank_up` for [userId]. Returns an empty list when the cache
  /// is empty, the box is missing, or the stored value is the wrong shape.
  static List<String> readFiredSlugs(String userId) {
    try {
      final box = Hive.box<dynamic>(HiveService.userPrefs);
      final raw = box.get(hiveKeyFor(userId));
      if (raw is List) {
        return raw.cast<String>().toList();
      }
      return const <String>[];
    } on Object {
      // Box not open / Hive not initialised in this test harness.
      // Treat as empty — production callers always run inside HiveService.init.
      return const <String>[];
    }
  }

  /// Persist [slugs] as the fired-body-part list for [userId].
  ///
  /// Visible for tests so the idempotency assertion can be made against
  /// the canonical write path (not by bypassing into the box directly).
  @visibleForTesting
  static Future<void> writeFiredSlugs(String userId, List<String> slugs) async {
    try {
      final box = Hive.box<dynamic>(HiveService.userPrefs);
      await box.put(hiveKeyFor(userId), List<String>.unmodifiable(slugs));
    } on Object {
      // Same rationale as [readFiredSlugs]: silent no-op when Hive
      // isn't available. The analytics event is informational; losing it
      // because the cache write failed must not break the finish flow.
    }
  }

  /// Iterate every [RankUpEvent] in [celebration]. For each body part not
  /// already in the fired-slugs cache, record a `first_rank_up` event +
  /// append the slug to the cache.
  ///
  /// All Hive + analytics IO is awaited so the cache is durable before
  /// the method returns; future test fixtures can call this directly and
  /// then assert against [readFiredSlugs].
  ///
  /// Errors at any stage are caught and swallowed — `first_rank_up` is
  /// non-critical funnel signal that must never break the finish flow.
  static Future<void> emitForCelebration({
    required WidgetRef ref,
    required CelebrationQueueResult celebration,
  }) async {
    // [analyticsRepositoryProvider] reads `Supabase.instance.client`
    // eagerly — wrap the whole emit so a Supabase-not-init failure can
    // never break the finish flow. Analytics is fire-and-forget per the
    // class doc; the coordinator must reach the celebration orchestrator
    // regardless of whether this fires.
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return;
      final analyticsRepo = ref.read(analyticsRepositoryProvider);
      await emitForRankUps(
        userId: userId,
        analyticsRepo: analyticsRepo,
        rankUps: celebration.queue.whereType<RankUpEvent>().toList(),
      );
    } catch (_) {
      // Swallowed — same rationale as [readFiredSlugs] / [writeFiredSlugs].
    }
  }

  /// Lower-level emit path that takes the rank-up list + repository
  /// explicitly. Public for unit tests that don't want to plumb a full
  /// [WidgetRef].
  @visibleForTesting
  static Future<void> emitForRankUps({
    required String userId,
    required AnalyticsRepository analyticsRepo,
    required List<RankUpEvent> rankUps,
  }) async {
    if (rankUps.isEmpty) return;
    final fired = List<String>.from(readFiredSlugs(userId));
    var dirty = false;
    for (final event in rankUps) {
      final slug = event.bodyPart.dbValue;
      if (fired.contains(slug)) continue;
      fired.add(slug);
      dirty = true;
      try {
        await analyticsRepo.insertEvent(
          userId: userId,
          event: AnalyticsEvent.firstRankUp(
            bodyPart: slug,
            newRank: event.newRank,
          ),
          platform: currentPlatform(),
          appVersion: currentAppVersion(),
        );
      } on Object {
        // `insertEvent` already swallows internally; this catch is the
        // belt for any future signature change.
      }
    }
    if (dirty) {
      await writeFiredSlugs(userId, fired);
    }
  }
}
