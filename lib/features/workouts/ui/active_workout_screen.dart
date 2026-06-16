import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar_tap_out_dismiss_scope.dart';
import '../models/active_workout_state.dart';
import '../providers/workout_providers.dart';
import 'coordinators/bodyweight_prompt_coordinator.dart';
import 'coordinators/discard_workout_coordinator.dart';
import 'coordinators/finish_workout_coordinator.dart';
import 'widgets/active_workout_app_bar_title.dart';
import 'widgets/active_workout_loading_overlay.dart';
import 'widgets/add_exercise_fab.dart';
import 'widgets/empty_workout_body.dart';
import 'widgets/exercise_list.dart';
import 'widgets/exercise_picker_sheet.dart';
import 'widgets/finish_bottom_bar.dart';
import 'widgets/rest_timer_overlay.dart';

/// Full-screen active workout experience.
///
/// Displayed outside the shell route (no bottom nav). Watches
/// [activeWorkoutProvider] and renders exercise cards with sets.
/// Overlays the [RestTimerOverlay] when a rest timer is running.
///
/// **Architecture (BUG-036, BUG-041):** the screen is a thin orchestration
/// shell. The State (`_ActiveWorkoutScreenState`) owns the
/// [DiscardWorkoutCoordinator] and [FinishWorkoutCoordinator] instances —
/// previously these guards lived as file-level mutable globals
/// (`_isShowingDiscardDialog`, `_isFinishHandled`). Hoisting them to a
/// per-screen owner removes the implicit lifetime coupling: the flags
/// now live exactly as long as the screen is on-screen.
///
/// The State is created when the route activates `/workout/active` and
/// disposed when the route is replaced (post-finish or discard). That
/// matches the load-bearing invariant: only one active workout screen
/// exists at a time.
class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  late final DiscardWorkoutCoordinator _discardCoordinator;
  late final FinishWorkoutCoordinator _finishCoordinator;
  late final BodyweightPromptCoordinator _bodyweightPromptCoordinator;

  @override
  void initState() {
    super.initState();
    _discardCoordinator = DiscardWorkoutCoordinator();
    _finishCoordinator = FinishWorkoutCoordinator();
    // Phase 24c-8 — owned at the screen-state level so its session-shot
    // flag (at most one bodyweight prompt per active-workout screen
    // lifetime) is reset implicitly on every fresh workout. Disposed
    // alongside the screen state below.
    _bodyweightPromptCoordinator = BodyweightPromptCoordinator();
  }

  @override
  void dispose() {
    _bodyweightPromptCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PR-3 S1 — feed every active-workout state transition into the discard
    // coordinator so it can drop its re-entrance guard the moment
    // `cancelLoading` restores state mid-discard. Without this listener,
    // the coordinator's flag stays `true` until the held network call
    // completes (sometimes unbounded), silently no-op'ing every subsequent
    // discard tap. The listener fires synchronously on every Riverpod
    // state notification, which is exactly the window we need.
    //
    // The discard coordinator does NOT need the SnackBarTapOutDismissScope —
    // it shows a Material dialog, not a snack — so its listener stays at the
    // screen level above the scope. The bodyweight-prompt coordinator's
    // listener lives INSIDE `_ActiveWorkoutBody` instead (it must show a
    // countdown SnackBar via `SnackBarTapOutDismissScope.maybeOf(context)`,
    // which requires a context that is a DESCENDANT of the scope).
    // See cluster `cluster_inherited_widget_context_above_scope` —
    // resolving an InheritedWidget from above-the-scope returns null
    // because `dependOnInheritedWidgetOfExactType` only walks UP. The
    // coordinator's `if (scope == null) return;` defensive branch then
    // silently ate every prompt fire (Phase 24c bug fix #2 / 2026-05-15).
    ref.listen<AsyncValue<ActiveWorkoutState?>>(activeWorkoutProvider, (
      previous,
      next,
    ) {
      _discardCoordinator.notifyStateChanged(next);
    });

    final asyncState = ref.watch(activeWorkoutProvider);
    final timerState = ref.watch(restTimerProvider);

    // .value returns null during AsyncLoading, retaining previous data on reload.
    final displayState = asyncState.value;

    if (displayState == null && !asyncState.isLoading) {
      // Workout was finished or discarded -- navigate home.
      // Guard: _finishCoordinator owns navigation during post-save celebration
      // playback. Yielding here prevents the postFrameCallback from dismissing
      // dialogs shown by CelebrationPlayer via GoRouter's full-stack
      // replacement.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && !_finishCoordinator.isFinishHandled) {
          context.go('/home');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (displayState == null) {
      // Still loading initial state — wrap with PopScope so Android back
      // does not close the app.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && context.mounted) context.go('/home');
        },
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // PR-2 C3 — overlays are pushed INTO the Scaffold body slot (see
    // `_ActiveWorkoutBody.build`) instead of being painted as siblings of
    // the Scaffold. This is the load-bearing structural change for the
    // undo-snackbar reachability fix: `Scaffold._ScaffoldSlot.snackBar`
    // paints AFTER `body`, so a SnackBar shown via
    // `ScaffoldMessenger.of(context)` automatically renders above any
    // widget that lives inside the body. With the overlays inside the
    // body, the swipe-to-delete undo SnackBar paints — AND hit-tests —
    // above the rest-timer scrim, no extra messenger hoisting required.
    // The previous outer-Stack ordering rendered the rest-timer overlay
    // above the inner Scaffold's snackbar slot, hiding the undo affordance
    // and consuming taps in its region (the overlay's full-screen
    // `HitTestBehavior.opaque` GestureDetector ate the Undo tap before it
    // could reach the SnackBarAction).
    //
    // Phase 23 D1 — body-slot coverage extended to FAB + FinishBottomBar.
    // PR #198 left those Scaffold slots painting ON TOP of the rest scrim
    // (acceptable per Strong/Hevy reference). User on-device feedback
    // 2026-05-12 flagged the chrome leak as visual noise — `+ Adicionar
    // exercício` FAB and `FINALIZAR` bottom button rendered above the
    // scrim during rest. Conditionally hiding both while
    // `showRestTimerOverlay` is true completes the "overlay over
    // everything" contract WITHOUT moving the overlay back to a Stack
    // root (which would re-break the snackbar slot ordering above). The
    // AppBar stays — its X is the in-rest discard affordance and the
    // `active_workout_appbar_discard_during_rest_test.dart` contract
    // remains pinned.
    //
    // PR-3 (review fix) — wrap the body in a route-scoped `ScaffoldMessenger`.
    // Without this, in-screen snackbars (H5 add-exercise undo, swipe-to-delete
    // set undo, etc.) attach to the app-level messenger that MaterialApp
    // installs at the root. Their queue then survives `context.go('/home')`
    // — which has the user-visible regression of the H5 "Bench Press added"
    // snackbar still being on-screen when the user navigates Home → Profile
    // → Manage Data, blocking the manage-data success snackbar from
    // appearing (MD-006/007/010/011 all failed for this reason).
    //
    // A route-scoped messenger is bounded by the screen's lifetime: when
    // the route is replaced post-finish/discard, the messenger disposes
    // and its queue dies cleanly. Snackbars that MUST outlive the screen
    // (offline-saved confirmation, failed-to-save error from the finish
    // coordinator) explicitly use the root messenger via `rootContext`.
    //
    // Snackbar-over-rest-timer ordering (PR-2 C3 contract) is preserved —
    // the local messenger sits ABOVE the Scaffold, but `Scaffold._ScaffoldSlot`
    // still paints its snackbar slot AFTER the body within that Scaffold,
    // so the snackbar still renders above the body's rest-timer overlay.
    // Phase 23 D2/D3 — back-press priority chain:
    //   1. Rest timer active AND loading overlay NOT active → dismiss rest.
    //      Rest is the dominant on-screen affordance; the user's mental
    //      model says "back closes the thing on top." Discard is reached
    //      via the AppBar X (still painted above the scrim).
    //   2. Loading overlay active → fall through to discard coordinator.
    //      The loading overlay carries its own Stop CTA (PR-1 Q1); back
    //      is a reasonable escape, and routing to the coordinator keeps
    //      the discard re-entrance guard (PR-3 S1) authoritative for the
    //      whole "exit a workout" surface.
    //   3. Else → discard coordinator (the historical contract).
    //
    // `_cancelRequested` flag on the notifier remains untouched — the
    // loading overlay's Stop button owns that path.
    final bool restActive = timerState != null;
    final bool loadingActive = asyncState.isLoading;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (restActive && !loadingActive) {
          ref.read(restTimerProvider.notifier).stop();
          return;
        }
        _discardCoordinator.show(context, ref, displayState);
      },
      child: ScaffoldMessenger(
        // SnackBarTapOutDismissScope sits INSIDE the route-scoped
        // ScaffoldMessenger so the scope's `showCountdownSnackBar`
        // factory resolves to the same messenger as direct
        // `ScaffoldMessenger.of(context).showSnackBar(...)` calls (e.g.
        // `SetRow`'s swipe-to-delete undo). The scope hosts the
        // tap-out `Listener` covering the entire body, and provides
        // the `showCountdownSnackBar` factory to descendants that
        // need a countdown-bar undo snack. See class doc for the
        // bounding-box hit-test contract (it prevents stepper / "+
        // Add set" taps above the snack from silently dismissing
        // the undo affordance).
        child: SnackBarTapOutDismissScope(
          child: _ActiveWorkoutBody(
            state: displayState,
            discardCoordinator: _discardCoordinator,
            finishCoordinator: _finishCoordinator,
            bodyweightPromptCoordinator: _bodyweightPromptCoordinator,
            showLoadingOverlay: loadingActive,
            showRestTimerOverlay: restActive,
          ),
        ),
      ),
    );
  }
}

class _ActiveWorkoutBody extends ConsumerStatefulWidget {
  const _ActiveWorkoutBody({
    required this.state,
    required this.discardCoordinator,
    required this.finishCoordinator,
    required this.bodyweightPromptCoordinator,
    required this.showLoadingOverlay,
    required this.showRestTimerOverlay,
  });

  final ActiveWorkoutState state;
  final DiscardWorkoutCoordinator discardCoordinator;
  final FinishWorkoutCoordinator finishCoordinator;
  final BodyweightPromptCoordinator bodyweightPromptCoordinator;

  /// PR-2 C3 — overlays are now passed in as flags so they can be stacked
  /// INSIDE this Scaffold's `body` slot. See the comment on the parent
  /// build above for the load-bearing reason: `Scaffold._ScaffoldSlot`
  /// paints the snackbar slot AFTER the body, so a SnackBar shown via
  /// `ScaffoldMessenger.of(context)` from a SetRow lands above any
  /// overlay rendered as part of the body.
  final bool showLoadingOverlay;
  final bool showRestTimerOverlay;

  @override
  ConsumerState<_ActiveWorkoutBody> createState() => _ActiveWorkoutBodyState();
}

class _ActiveWorkoutBodyState extends ConsumerState<_ActiveWorkoutBody> {
  bool _reorderMode = false;
  bool _isEditingName = false;

  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.workout.name);
    // Keep the screen on while the user is actively logging sets. Errors
    // are swallowed so unsupported platforms (e.g. some web browsers or
    // test environments without a platform handler) don't break logging.
    unawaited(WakelockPlus.enable().catchError((_) {}));
  }

  @override
  void didUpdateWidget(_ActiveWorkoutBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingName &&
        oldWidget.state.workout.name != widget.state.workout.name) {
      _nameController.text = widget.state.workout.name;
    }
  }

  @override
  void dispose() {
    // Release the wakelock before tearing down so the phone can sleep
    // again once the user leaves the logging view. Fire-and-forget with
    // error swallowing to stay consistent with the enable path.
    unawaited(WakelockPlus.disable().catchError((_) {}));
    _nameController.dispose();
    super.dispose();
  }

  void _submitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty) {
      ref.read(activeWorkoutProvider.notifier).renameWorkout(trimmed);
    } else {
      _nameController.text = widget.state.workout.name;
    }
    setState(() => _isEditingName = false);
  }

  void _onTapToEditName() {
    _nameController.text = widget.state.workout.name;
    setState(() => _isEditingName = true);
  }

  /// True iff the session has any committable work — a completed strength set
  /// OR a completed cardio entry. This is the FINISH enable-gate and MUST stay
  /// in lock-step with `ActiveWorkoutNotifier.totalSetsCount` (the
  /// empty-session finish guard). Phase 38b: a cardio-only entry carries
  /// `sets: const []` and stores completion in `cardioSession.isCompleted`, so
  /// a strength-only check (`e.sets.any(...)`) reported false for a finished
  /// cardio session and left FINISH dead — a cardio-only workout could never be
  /// finished. Counting cardio here restores the two sources of truth to one
  /// definition of "did the user do anything worth saving".
  bool get _hasProgress => widget.state.exercises.any(
    (e) =>
        e.sets.any((s) => s.isCompleted) ||
        (e.cardioSession?.isCompleted ?? false),
  );

  Future<void> _onBackPressed() {
    return widget.discardCoordinator.show(context, ref, widget.state);
  }

  Future<void> _onFinish() {
    return widget.finishCoordinator.finish(context: context, ref: ref);
  }

  Future<void> _onAddExercise() async {
    final exercise = await ExercisePickerSheet.show(context);
    if (exercise == null) return;
    if (!mounted) return;

    // Snapshot the WE id set BEFORE the add so we can isolate the new id
    // even if state mutates between addExercise and the snackbar wiring.
    // Reading the notifier's state directly is safer than diffing the FAB
    // build closure — the notifier is the source of truth.
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final beforeExercises =
        ref.read(activeWorkoutProvider).value?.exercises ?? const [];
    final beforeIds = beforeExercises.map((e) => e.workoutExercise.id).toSet();

    // Phase 23 D6: `addExercise` is now async — it awaits
    // `_seedFirstSetForAddedExercise` which itself awaits
    // `WorkoutRepository.getLastWorkoutSets` to derive the pre-filled
    // weight/reps for the seeded set. We MUST await here. Pre-Phase-23
    // this was fire-and-forget because `addExercise` mutated state
    // synchronously and the diff below could read the new id immediately.
    // Without the `await`, the diff reads the OLD exercise list, finds no
    // newly-added id, hits `if (added == null) return;` and the H5
    // undo SnackBar is never shown — breaking
    // `workouts.spec.ts:1764 / :1786`. See PR-3 review W1 comment below
    // for the original async-defence reasoning.
    await notifier.addExercise(exercise);
    if (!mounted) return;

    // PR-3 (H5): identify the just-added workoutExercise id by diffing the
    // pre/post id sets. `addExercise` has already awaited the seed-fetch
    // and the Hive persist; the new id is in state by the time we read
    // it here.
    //
    // PR-3 review W1 — use `firstWhereOrNull` and bail when the diff yields
    // nothing instead of falling back to `after.last`. The previous
    // `orElse: () => after.last` silently passed the WRONG id (the last
    // entry in the list, which is unrelated to what was just added) under
    // any concurrent mutation — and the snackbar's Undo would then
    // silently delete an exercise the user never added. Bailing early
    // keeps the contract explicit: no diff entry → no undo affordance,
    // fail closed instead of fail open.
    final after = ref.read(activeWorkoutProvider).value?.exercises;
    if (after == null || after.isEmpty) return;
    final added = after.firstWhereOrNull(
      (e) => !beforeIds.contains(e.workoutExercise.id),
    );
    if (added == null) return;
    final addedId = added.workoutExercise.id;

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // 3500 ms duration tuned 2026-05-13 (down from the original 4 s) —
    // user feedback was that the previous window felt long when waiting
    // passively. The countdown bar at the bottom of the snack visualises
    // the remaining time so the duration reads as definite, not vague.
    //
    // `SnackBarTapOutDismissScope.showCountdownSnackBar`:
    //   * wraps the message in a `_SnackBarCountdown` widget (3 dp
    //     progress bar that drains over the SnackBar's duration);
    //   * pins `persist: false` (Flutter defaults to `true` when an
    //     `action:` is set — that broke 4 s auto-dismiss on Android
    //     release builds before this fix wave);
    //   * registers the snack with the scope's tap-out listener so
    //     pointer-down events OUTSIDE the snack's content rect dismiss
    //     it, while taps INSIDE the snack (Undo, or anywhere on the
    //     content row) AND taps on unrelated widgets above the snack
    //     (steppers, "+ Add set") continue to function normally. See
    //     the scope's class doc for the bounding-box hit-test contract.
    SnackBarTapOutDismissScope.of(context).showCountdownSnackBar(
      context: context,
      message: l10n.addExerciseUndo(exercise.name),
      duration: const Duration(milliseconds: 3500),
      action: SnackBarAction(
        label: l10n.undo,
        onPressed: () {
          // Read the notifier fresh — `ref` is still valid even after
          // an await gap because this State outlives the snackbar.
          ref.read(activeWorkoutProvider.notifier).restoreExercise(addedId);
        },
      ),
    );
  }

  void _toggleReorderMode() {
    setState(() => _reorderMode = !_reorderMode);
  }

  /// AppBar leading "discard workout" button. Wrapped in
  /// `Semantics(identifier: 'workout-discard-btn')` — E2E selector contract.
  ///
  /// `container: true` + `explicitChildNodes: true` is the pair-rule for
  /// every Semantics(identifier:) we expose for e2e: the first creates the
  /// boundary so the identifier is addressable in isolation, the second
  /// keeps the IconButton's own role=button semantics from being absorbed
  /// up or merging with sibling AppBar action Semantics (see PR #152
  /// lessons.md entry).
  Widget _buildDiscardLeading(AppLocalizations l10n) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'workout-discard-btn',
      label: l10n.discardWorkout,
      child: IconButton(
        onPressed: _onBackPressed,
        icon: AppIcons.render(AppIcons.close, size: 24),
        tooltip: l10n.discardWorkout,
      ),
    );
  }

  /// Reorder-mode toggle in AppBar.actions; only shown when there are
  /// multiple exercises (single exercise can't be reordered).
  ///
  /// **Family 3 (AW-EX-C-BR1-01) — Semantics identifier wrap.** The IconButton
  /// is wrapped in `Semantics(container: true, explicitChildNodes: true,
  /// identifier: 'workout-reorder-toggle')` so Playwright can target it via
  /// `flt-semantics-identifier` instead of the locale-dependent tooltip
  /// text. The pair-rule (`container` + `explicitChildNodes`) is mandatory
  /// per lessons.md PR #152 — a bare identifier merges silently into
  /// ancestor Semantics and breaks both the e2e selector and the row's
  /// internal AOM structure.
  List<Widget> _buildAppBarActions(AppLocalizations l10n) {
    if (widget.state.exercises.length <= 1) return const [];
    return [
      Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'workout-reorder-toggle',
        label: _reorderMode
            ? l10n.exitReorderModeTooltip
            : l10n.reorderExercisesTooltip,
        child: IconButton(
          onPressed: _toggleReorderMode,
          // PR-7 generic-icon swap: `Icons.swap_vert` reads as "swap two
          // entries" rather than "reorder a list". `Icons.reorder` is the
          // 3-line drag-handle convention (Material spec for reorderable
          // lists) — less ambiguous and matches what users see in every
          // mainstream gym app's exercise reorder mode.
          icon: Icon(_reorderMode ? Icons.done : Icons.reorder),
          tooltip: _reorderMode
              ? l10n.exitReorderModeTooltip
              : l10n.reorderExercisesTooltip,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Phase 24c-8 — bodyweight-prompt listener lives HERE (inside the body,
    // a descendant of `SnackBarTapOutDismissScope`) rather than at the
    // screen level. The coordinator's `_showPromptSnackBar` calls
    // `SnackBarTapOutDismissScope.maybeOf(context)`; `dependOnInheritedWidgetOfExactType`
    // only walks UP the tree, so passing the screen-State's context
    // (which is ABOVE the scope) resolves to `null` and the coordinator's
    // defensive branch silently swallows every fire. Wiring the listener
    // here gives the coordinator a context that is BELOW the scope.
    //
    // Cluster: `cluster_inherited_widget_context_above_scope`. The pre-fix
    // widget tests pinned the coordinator's behaviour via a synthetic
    // in-scope context — they passed even while production was broken.
    // See `should fire the bodyweight prompt via the production ref.listen
    // wiring` test for the regression guard that pins THIS wiring.
    ref.listen<AsyncValue<ActiveWorkoutState?>>(activeWorkoutProvider, (
      previous,
      next,
    ) {
      widget.bodyweightPromptCoordinator.maybeShow(
        context: context,
        ref: ref,
        previous: previous?.value,
        next: next.value,
      );
    });

    final l10n = AppLocalizations.of(context);
    final hasExercises = widget.state.exercises.isNotEmpty;

    final Widget bodyContent = hasExercises
        ? ExerciseList(
            exercises: widget.state.exercises,
            reorderMode: _reorderMode,
            routineNotes: widget.state.routineNotes,
          )
        : EmptyWorkoutBody(onAddExercise: _onAddExercise);

    // PR-2 C3 — body slot wraps the actual body content + overlays in a
    // Stack so SnackBars (rendered in the Scaffold's snackbar slot, which
    // paints AFTER the body slot) appear ABOVE the rest-timer scrim.
    //
    // Loading overlay sits above the rest-timer overlay so a cancel during
    // a slow finish/discard shows its Cancel CTA on top of the dim scrim
    // — preserves PR-1 Q1's always-visible-Cancel contract.
    final Widget body = Stack(
      children: [
        bodyContent,
        if (widget.showRestTimerOverlay) const RestTimerOverlay(),
        if (widget.showLoadingOverlay) const ActiveWorkoutLoadingOverlay(),
      ],
    );

    // Phase 23 D1 — hide FAB + FinishBottomBar while rest is active so
    // the rest-overlay's "cover everything" contract holds visually
    // without moving the overlay back to a Stack root (which would
    // re-break the PR-2 C3 snackbar slot ordering preserved above).
    // AppBar untouched: its discard-X is the in-rest exit affordance and
    // `active_workout_appbar_discard_during_rest_test.dart` keeps that
    // reachability contract pinned.
    final bool chromeVisible = hasExercises && !widget.showRestTimerOverlay;

    return Scaffold(
      appBar: AppBar(
        leading: _buildDiscardLeading(l10n),
        title: ActiveWorkoutAppBarTitle(
          name: widget.state.workout.name,
          isEditing: _isEditingName,
          nameController: _nameController,
          onSubmitName: _submitName,
          onTapToEdit: _onTapToEditName,
          startedAt: widget.state.workout.startedAt,
        ),
        centerTitle: true,
        // Phase 23 UI/UX REV-2 (2026-05-12) — when the rest overlay is
        // active, merge the AppBar into the abyss scrim. At theme default
        // (transparent) the AppBar plane competed with the 72px countdown
        // for visual hierarchy. Painting at `AppColors.abyss` (opaque)
        // matches the scrim's near-black floor so the bar reads as
        // "quieted chrome" — the discard X stays semantically reachable
        // but recedes from same-plane competition with the countdown.
        backgroundColor: widget.showRestTimerOverlay ? AppColors.abyss : null,
        actions: _buildAppBarActions(l10n),
      ),
      body: body,
      // BUG-020: Finish bar is hidden on the empty body — EmptyWorkoutBody
      // owns its own CTA and a Finish bar with no logged sets is dead chrome.
      // Full BUG-020 narrative on FinishBottomBar's class doc.
      bottomNavigationBar: chromeVisible
          ? FinishBottomBar(enabled: _hasProgress, onPressed: _onFinish)
          : null,
      floatingActionButton: chromeVisible
          ? AddExerciseFab(onPressed: _onAddExercise)
          : null,
    );
  }
}
