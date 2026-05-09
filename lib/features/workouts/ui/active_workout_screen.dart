import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../models/active_workout_state.dart';
import '../providers/workout_providers.dart';
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

  @override
  void initState() {
    super.initState();
    _discardCoordinator = DiscardWorkoutCoordinator();
    _finishCoordinator = FinishWorkoutCoordinator();
  }

  @override
  Widget build(BuildContext context) {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _discardCoordinator.show(context, ref, displayState);
        }
      },
      child: Stack(
        children: [
          _ActiveWorkoutBody(
            state: displayState,
            discardCoordinator: _discardCoordinator,
            finishCoordinator: _finishCoordinator,
          ),
          if (asyncState.isLoading)
            ActiveWorkoutLoadingOverlay(hasRestorable: asyncState.hasValue),
          if (timerState != null) const RestTimerOverlay(),
        ],
      ),
    );
  }
}

class _ActiveWorkoutBody extends ConsumerStatefulWidget {
  const _ActiveWorkoutBody({
    required this.state,
    required this.discardCoordinator,
    required this.finishCoordinator,
  });

  final ActiveWorkoutState state;
  final DiscardWorkoutCoordinator discardCoordinator;
  final FinishWorkoutCoordinator finishCoordinator;

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

  bool get _hasCompletedSet =>
      widget.state.exercises.any((e) => e.sets.any((s) => s.isCompleted));

  Future<void> _onBackPressed() {
    return widget.discardCoordinator.show(context, ref, widget.state);
  }

  Future<void> _onFinish() {
    return widget.finishCoordinator.finish(context: context, ref: ref);
  }

  Future<void> _onAddExercise() async {
    final exercise = await ExercisePickerSheet.show(context);
    if (exercise != null) {
      ref.read(activeWorkoutProvider.notifier).addExercise(exercise);
    }
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
          icon: Icon(_reorderMode ? Icons.done : Icons.swap_vert),
          tooltip: _reorderMode
              ? l10n.exitReorderModeTooltip
              : l10n.reorderExercisesTooltip,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasExercises = widget.state.exercises.isNotEmpty;

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
        actions: _buildAppBarActions(l10n),
      ),
      body: hasExercises
          ? ExerciseList(
              exercises: widget.state.exercises,
              reorderMode: _reorderMode,
            )
          : EmptyWorkoutBody(onAddExercise: _onAddExercise),
      // BUG-020: Finish bar is hidden on the empty body — EmptyWorkoutBody
      // owns its own CTA and a Finish bar with no logged sets is dead chrome.
      // Full BUG-020 narrative on FinishBottomBar's class doc.
      bottomNavigationBar: hasExercises
          ? FinishBottomBar(enabled: _hasCompletedSet, onPressed: _onFinish)
          : null,
      floatingActionButton: hasExercises
          ? AddExerciseFab(onPressed: _onAddExercise)
          : null,
    );
  }
}
