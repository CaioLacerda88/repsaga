import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../core/utils/enum_l10n.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/exercise_image.dart';
import '../../../../shared/widgets/exercise_info_sections.dart';
import '../../../exercises/models/exercise.dart';
import '../../../personal_records/models/personal_record.dart';
import '../../../personal_records/models/record_type.dart';
import '../../../personal_records/providers/pr_providers.dart';
import '../../../personal_records/ui/widgets/pr_type_icon.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../domain/pr_row_state.dart';
import '../../models/active_workout_state.dart';
import '../../models/exercise_set.dart';
import '../../models/set_type.dart';
import '../../models/weight_unit.dart';
import '../../providers/workout_providers.dart';
import '../../utils/set_defaults.dart';
import 'exercise_picker_sheet.dart';
import 'set_row.dart';

/// Card representing one exercise inside an active workout.
///
/// Hosts the exercise header (name + reorder/swap/delete actions), the set
/// rows (via [SetRow]), and the "Add set" / "Fill remaining" buttons.
/// Tapping the name opens an [_ExerciseDetailSheet]; long-pressing swaps
/// the exercise via [ExercisePickerSheet].
///
/// Tracks recently-added set IDs locally so the corresponding [SetRow]
/// captures the `isNew` flag in its `initState` (the flag is cleared after
/// one frame so subsequent rebuilds don't re-flash the row).
class ExerciseCard extends ConsumerStatefulWidget {
  const ExerciseCard({
    required this.activeExercise,
    required this.reorderMode,
    required this.isFirst,
    required this.isLast,
    super.key,
  });

  final ActiveWorkoutExercise activeExercise;
  final bool reorderMode;
  final bool isFirst;
  final bool isLast;

  @override
  ConsumerState<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<ExerciseCard> {
  /// IDs of sets that were just added and should receive the isNew flag.
  final Set<String> _newSetIds = {};

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.removeExerciseTitle),
          content: Text(
            l10n.removeExerciseContent(
              widget.activeExercise.workoutExercise.exercise?.name ?? '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: dialogTextButtonStyle,
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              // Compose the destructive foreground on the shared dialog
              // 48dp floor — single source of truth for the tap-target
              // size lives in `dialogTextButtonStyle`.
              style: dialogTextButtonStyle.copyWith(
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      ref
          .read(activeWorkoutProvider.notifier)
          .removeExercise(widget.activeExercise.workoutExercise.id);
    }
  }

  Future<void> _swapExercise(BuildContext context) async {
    final exercise = await ExercisePickerSheet.show(context);
    if (exercise != null) {
      ref
          .read(activeWorkoutProvider.notifier)
          .swapExercise(widget.activeExercise.workoutExercise.id, exercise);
    }
  }

  void _onSetCompleted() {
    final restSeconds = widget.activeExercise.workoutExercise.restSeconds ?? 90;
    final exerciseName = widget.activeExercise.workoutExercise.exercise?.name;
    ref
        .read(restTimerProvider.notifier)
        .start(restSeconds, exerciseName: exerciseName);
  }

  void _fillRemaining(BuildContext context) {
    ref
        .read(activeWorkoutProvider.notifier)
        .fillRemainingSets(widget.activeExercise.workoutExercise.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).filledRemainingSets),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Returns true when there are incomplete sets after the last completed set.
  /// The fill-remaining action only affects those sets, so the button should
  /// be hidden when there is nothing to fill.
  bool _hasFillableSets(List<ExerciseSet> sets) {
    final lastCompletedNumber = sets
        .where((s) => s.isCompleted)
        .fold<int>(0, (max, s) => s.setNumber > max ? s.setNumber : max);
    if (lastCompletedNumber == 0) return false;
    return sets.any((s) => !s.isCompleted && s.setNumber > lastCompletedNumber);
  }

  void _showExerciseDetail(BuildContext context, Exercise exercise) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseDetailSheet(exercise: exercise),
    );
  }

  /// Compute defaults for a brand-new set on this exercise.
  ///
  /// Priority chain:
  ///   1. Previous session set at the matching position (`lastSets[index]`).
  ///   2. Last set in current session (skip warmup→working — never carry
  ///      warmup weight forward into a working set).
  ///   3. Equipment-type defaults from [defaultSetValues].
  ///   4. Bare 0/0 fallback (when none of the above produce a value).
  ({double? weight, int? reps}) _computeNewSetDefaults({
    required List<ExerciseSet> currentSets,
    required List<ExerciseSet> lastSets,
    required Exercise? exercise,
    required WeightUnit weightUnit,
  }) {
    final newSetIndex = currentSets.length;
    double? defaultWeight;
    int? defaultReps;

    // Priority 1: previous session at matching position
    final lastSetForNewRow = newSetIndex < lastSets.length
        ? lastSets[newSetIndex]
        : null;

    if (lastSetForNewRow != null) {
      defaultWeight = lastSetForNewRow.weight ?? 0;
      defaultReps = lastSetForNewRow.reps ?? 0;
    } else if (currentSets.isNotEmpty) {
      // Priority 2: last set in current session (not just last completed —
      // always copy from the most recent set so weight is never lost).
      final prevSet = currentSets.last;
      // Skip if previous set is warmup (new set defaults to working, so
      // don't carry warmup weights forward).
      if (prevSet.setType != SetType.warmup) {
        defaultWeight = prevSet.weight ?? 0;
        defaultReps = prevSet.reps ?? 0;
      } else {
        // Warmup -> working: use equipment defaults
        final equipType = exercise?.equipmentType;
        if (equipType != null) {
          final defaults = defaultSetValues(equipType, weightUnit);
          defaultWeight = defaults.weight;
          defaultReps = defaults.reps;
        }
      }
    } else {
      // Priority 3: equipment-type defaults for first-ever set
      final equipType = exercise?.equipmentType;
      if (equipType != null) {
        final defaults = defaultSetValues(equipType, weightUnit);
        defaultWeight = defaults.weight;
        defaultReps = defaults.reps;
      }
    }
    return (weight: defaultWeight, reps: defaultReps);
  }

  void _onAddSet({
    required List<ExerciseSet> lastSets,
    required Exercise? exercise,
    required WeightUnit weightUnit,
  }) {
    final activeExercise = widget.activeExercise;
    final weId = activeExercise.workoutExercise.id;

    final defaults = _computeNewSetDefaults(
      currentSets: activeExercise.sets,
      lastSets: lastSets,
      exercise: exercise,
      weightUnit: weightUnit,
    );

    // Record the current set count before adding.
    final setCountBefore = activeExercise.sets.length;
    ref
        .read(activeWorkoutProvider.notifier)
        .addSet(
          weId,
          defaultWeight: defaults.weight,
          defaultReps: defaults.reps,
        );

    // Mark the newly added set as new after state updates. The notifier
    // adds the set synchronously, so we can read back the updated state to
    // find the new set ID.
    final updated = ref.read(activeWorkoutProvider).value;
    if (updated != null) {
      final updatedExercise = updated.exercises
          .where((e) => e.workoutExercise.id == weId)
          .firstOrNull;
      if (updatedExercise != null &&
          updatedExercise.sets.length > setCountBefore) {
        setState(() {
          _newSetIds.add(updatedExercise.sets.last.id);
        });
        // Clear after the frame so SetRow.initState captures isNew
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _newSetIds.remove(updatedExercise.sets.last.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeExercise = widget.activeExercise;
    final exercise = activeExercise.workoutExercise.exercise;
    final exerciseId = activeExercise.workoutExercise.exerciseId;

    // Fetch previous session sets for this exercise; default weight unit
    // for equipment-type defaults if no profile has loaded yet.
    final lastSets =
        ref.watch(lastWorkoutSetsProvider(exerciseId)).value?[exerciseId] ??
        const <ExerciseSet>[];
    final weightUnit = WeightUnit.fromString(
      ref.watch(profileProvider).value?.weightUnit ?? 'kg',
    );
    // Bodyweight chrome predicate (PLAN.md backlog 20-P-2). Computed once
    // at build-time so the column header and the per-row build both read
    // from the same source of truth — no risk of drift if the underlying
    // rule ever grows (e.g. a future equipment type that also hides
    // weight).
    final bool isBodyweight =
        exercise?.equipmentType == EquipmentType.bodyweight;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // Phase 20 commit 2: card chrome trimmed to give the SetRow data
      // table breathing room on 360dp Brazilian-mid-market screens.
      // Vertical padding stays at 16dp (rhythm above/below the set table);
      // horizontal padding drops to 10dp so the flex-2 reps column has
      // enough slack for two 40dp +/- buttons + a non-zero value zone
      // without spawning a `RenderFlex overflowed` warning.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ExerciseCardHeader(
              exercise: exercise,
              workoutExerciseId: activeExercise.workoutExercise.id,
              reorderMode: widget.reorderMode,
              isFirst: widget.isFirst,
              isLast: widget.isLast,
              onShowDetail: _showExerciseDetail,
              onSwap: _swapExercise,
              onConfirmRemove: _confirmRemove,
            ),
            if (activeExercise.sets.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SetColumnHeaders(
                theme: Theme.of(context),
                isBodyweight: isBodyweight,
              ),
              const Divider(height: 1),
              ..._buildSetRows(activeExercise, lastSets, isBodyweight),
            ],
            const SizedBox(height: 8),
            _AddSetButton(
              onPressed: () => _onAddSet(
                lastSets: lastSets,
                exercise: exercise,
                weightUnit: weightUnit,
              ),
              onLongPress: () => _fillRemaining(context),
            ),
            if (_hasFillableSets(activeExercise.sets))
              _FillRemainingButton(onPressed: () => _fillRemaining(context)),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _buildSetRows(
    ActiveWorkoutExercise activeExercise,
    List<ExerciseSet> lastSets,
    bool isBodyweight,
  ) {
    final weId = activeExercise.workoutExercise.id;
    final exerciseId = activeExercise.workoutExercise.exerciseId;
    // Phase 20 commit 4: the per-row PR display state (5-state matrix +
    // accent record types) comes from the pure resolver via
    // [activeWorkoutRowDisplaysProvider]. The provider watches the active
    // workout state AND the exercise's historical PRs; SetRow consumes the
    // resolved display via constructor — it does not recompute. Unidirectional
    // data flow: state in → display projection → row render.
    final rowDisplays = ref.watch(
      activeWorkoutRowDisplaysProvider((
        workoutExerciseId: weId,
        exerciseId: exerciseId,
      )),
    );
    return activeExercise.sets.indexed.map((entry) {
      final (index, s) = entry;
      // Match by position: set 1 maps to lastSets[0], etc.
      final lastSet = index < lastSets.length ? lastSets[index] : null;
      // Fix 2 — discoverability hint requires the previous in-session set
      // (set at index N-1) so the cell can compare weights and decide
      // whether to surface the copy-icon affordance. Null on set #1.
      final previousSet = index > 0 ? activeExercise.sets[index - 1] : null;
      final isNew = _newSetIds.contains(s.id);
      // Resolve the matching display for this row. If the resolver has not
      // yet produced an entry (race during a transient empty state) fall
      // back to the no-accent default so the row still renders cleanly.
      final display = index < rowDisplays.length
          ? rowDisplays[index]
          : const PrRowDisplay.plain(PrRowState.none);
      return SetRow(
        key: ValueKey(s.id),
        set: s,
        workoutExerciseId: weId,
        display: display,
        onCompleted: _onSetCompleted,
        lastSet: lastSet,
        previousSet: previousSet,
        isNew: isNew,
        isBodyweight: isBodyweight,
      );
    });
  }
}

/// Row at the top of each [ExerciseCard] — name + info icon + reorder /
/// swap / delete affordances.
///
/// Extracted so [ExerciseCard.build] stays under the 50-line cap. Owns no
/// state — every interaction is forwarded to a callback supplied by the
/// parent.
class _ExerciseCardHeader extends ConsumerWidget {
  const _ExerciseCardHeader({
    required this.exercise,
    required this.workoutExerciseId,
    required this.reorderMode,
    required this.isFirst,
    required this.isLast,
    required this.onShowDetail,
    required this.onSwap,
    required this.onConfirmRemove,
  });

  final Exercise? exercise;
  final String workoutExerciseId;
  final bool reorderMode;
  final bool isFirst;
  final bool isLast;
  final void Function(BuildContext context, Exercise exercise) onShowDetail;
  final Future<void> Function(BuildContext context) onSwap;
  final Future<void> Function(BuildContext context) onConfirmRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          // `container: true` + `explicitChildNodes: true` is load-bearing:
          // without them the InkWell's tap action + the inner Text + every
          // sibling Semantics in the surrounding Column (column headers
          // SET/WEIGHT/REPS, set-row identifiers, stepper buttons) collapse
          // into ONE merged `flt-tappable role="group"` that intercepts every
          // pointer event on the card. PR #152's third fix attempt traced this
          // back to the header InkWell — a tap meant for "open detail sheet"
          // would land on the weight value zone and open the "Enter weight"
          // dialog instead. The two flags create a hard semantic boundary so
          // the header is its OWN tappable region, distinct from siblings.
          //
          // See `tasks/lessons.md` "Semantics container/explicitChildNodes is
          // needed at EVERY tap-merging boundary".
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: l10n.exerciseSemanticsLabel(
              exercise?.name ?? l10n.exerciseGeneric,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: exercise != null
                  ? () => onShowDetail(context, exercise!)
                  : null,
              onLongPress: () => onSwap(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Inner visual content is decorative — the parent Semantics
                  // label already describes the affordance ("Exercise: …. Tap
                  // for details. Long press to swap."). ExcludeSemantics here
                  // prevents the inner Text + Icon from emitting their own
                  // semantic nodes that the AOM would merge upward into a
                  // sibling group, which is exactly the bug we just fixed.
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            exercise?.name ?? l10n.exerciseGeneric,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (reorderMode) ...[
          Semantics(
            label: l10n.moveUp,
            child: IconButton(
              onPressed: isFirst
                  ? null
                  : () => ref
                        .read(activeWorkoutProvider.notifier)
                        .reorderExercise(workoutExerciseId, -1),
              icon: const Icon(Icons.arrow_upward),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.moveUp,
            ),
          ),
          Semantics(
            label: l10n.moveDown,
            child: IconButton(
              onPressed: isLast
                  ? null
                  : () => ref
                        .read(activeWorkoutProvider.notifier)
                        .reorderExercise(workoutExerciseId, 1),
              icon: const Icon(Icons.arrow_downward),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.moveDown,
            ),
          ),
        ] else ...[
          // Family 3 (AW-EX-C-BR1-02) — pair-rule Semantics with stable
          // identifiers so Playwright can target swap / remove without
          // tooltip-text fallback. `container: true, explicitChildNodes:
          // true` is mandatory per lessons.md PR #152.
          Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: 'workout-swap-exercise',
            label: l10n.swapExercise,
            child: IconButton(
              onPressed: () => onSwap(context),
              icon: Icon(
                Icons.swap_horiz,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              tooltip: l10n.swapExercise,
            ),
          ),
          Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: 'workout-remove-exercise',
            label: l10n.removeExercise,
            child: IconButton(
              onPressed: () => onConfirmRemove(context),
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error.withValues(alpha: 0.7),
              ),
              tooltip: l10n.removeExercise,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Add set" OutlinedButton — wrapped in `Semantics(identifier: 'workout-add-set')`
/// (E2E selector contract; see `WORKOUT.addSetButton` in selectors.ts).
class _AddSetButton extends StatelessWidget {
  const _AddSetButton({required this.onPressed, required this.onLongPress});

  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // `explicitChildNodes: true` keeps the OutlinedButton's own Semantics
      // (button role + tap action) addressable as the canonical tap target
      // under this identifier — without it descendants can be merged up and
      // siblings can be merged in, which is the failure mode PR #152 hit on
      // the row-level Semantics. Pair-rule: every Semantics(identifier:) we
      // expose to e2e MUST set BOTH container AND explicitChildNodes.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'workout-add-set',
        child: OutlinedButton.icon(
          onPressed: onPressed,
          onLongPress: onLongPress,
          icon: const Icon(Icons.add, size: 20),
          label: Text(AppLocalizations.of(context).addSet),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Fill remaining" TextButton shown only when there are incomplete sets
/// after the last completed set (BUG-3).
class _FillRemainingButton extends StatelessWidget {
  const _FillRemainingButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      // container + explicitChildNodes establishes the boundary so the
      // TextButton stays its own discrete tappable node — see the same
      // rule applied to _AddSetButton above and the lessons.md entry on
      // Semantics(identifier:) flag pairing.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.fillRemainingSetsSemantics,
        child: TextButton(
          onPressed: onPressed,
          child: Text(
            l10n.fillRemaining,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SetColumnHeaders extends StatelessWidget {
  const _SetColumnHeaders({required this.theme, this.isBodyweight = false});

  final ThemeData theme;

  /// Hide the WEIGHT column header for bodyweight exercises. Mirrors the
  /// `SetRow.isBodyweight` chrome change (PLAN.md backlog 20-P-2).
  final bool isBodyweight;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    // Phase 20 commit 2: column widths mirror the new SetRow geometry —
    //   set-num cell  : 48dp (BUG-018 tap-target floor; visual is 44dp but
    //                   the Container constraint takes 48dp horizontal)
    //   weight col    : flex 3
    //   reps col      : flex 2
    //   done-col      : 52dp
    //
    // ExcludeSemantics wraps the entire table header: the SET/WEIGHT/REPS
    // letters are PURELY visual (each set row already exposes per-cell labels
    // like "Weight value: 20 kg"). Without this exclusion the Text widgets
    // emitted free-floating semantic nodes that the AOM merged UP into the
    // exercise card header's `flt-tappable` region — producing the giant
    // merged group that intercepted every tap. See PR #152 fix #3.
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                AppLocalizations.of(context).setColumnSet,
                style: style,
                textAlign: TextAlign.center,
              ),
            ),
            // Bodyweight mode hides the WEIGHT column; reps absorbs the
            // freed space via `flex: 1` instead of `flex: 2` (mirroring the
            // SetRow geometry change in `set_row.dart`).
            if (!isBodyweight)
              Expanded(
                flex: 3,
                child: Text(
                  AppLocalizations.of(context).setColumnWeight,
                  style: style,
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              flex: isBodyweight ? 1 : 2,
              child: Text(
                AppLocalizations.of(context).setColumnReps,
                style: style,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 52),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that shows exercise details (name, muscle group, equipment,
/// images, PRs) without navigating away from the active workout screen.
class _ExerciseDetailSheet extends ConsumerWidget {
  const _ExerciseDetailSheet({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final asyncRecords = ref.watch(exercisePRsProvider(exercise.id));
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  // Exercise name
                  Text(exercise.name, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  // Muscle group + equipment chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SheetChip(
                        svgIcon: exercise.muscleGroup.svgIcon,
                        label: exercise.muscleGroup.localizedName(l10n),
                      ),
                      _SheetChip(
                        svgIcon: exercise.equipmentType.svgIcon,
                        label: exercise.equipmentType.localizedName(l10n),
                      ),
                    ],
                  ),
                  // Images
                  if (exercise.imageStartUrl != null ||
                      exercise.imageEndUrl != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 160,
                      child: Row(
                        children: [
                          if (exercise.imageStartUrl != null)
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ExerciseImage(
                                      imageUrl: exercise.imageStartUrl,
                                      fallbackIcon: Icons.fitness_center,
                                      height: 136,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.imageStart,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (exercise.imageStartUrl != null &&
                              exercise.imageEndUrl != null)
                            const SizedBox(width: 8),
                          if (exercise.imageEndUrl != null)
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ExerciseImage(
                                      imageUrl: exercise.imageEndUrl,
                                      fallbackIcon: Icons.fitness_center,
                                      height: 136,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.imageEnd,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  ExerciseDescriptionSection(description: exercise.description),
                  ExerciseFormTipsSection(formTips: exercise.formTips),
                  const SizedBox(height: 24),
                  // Personal records
                  _SheetPRSection(
                    asyncRecords: asyncRecords,
                    equipmentType: exercise.equipmentType,
                    weightUnit: weightUnit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  const _SheetChip({required this.svgIcon, required this.label});

  /// Inline-SVG glyph string from [AppMuscleIcons] / [AppEquipmentIcons] (or
  /// the reused [AppIcons.lift] for barbell).
  final String svgIcon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcons.render(
            svgIcon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetPRSection extends StatelessWidget {
  const _SheetPRSection({
    required this.asyncRecords,
    required this.equipmentType,
    required this.weightUnit,
  });

  final AsyncValue<List<PersonalRecord>> asyncRecords;
  final EquipmentType equipmentType;
  final String weightUnit;

  String _formatValue(RecordType type, double value, AppLocalizations l10n) {
    return switch (type) {
      RecordType.maxWeight => '$value $weightUnit',
      RecordType.maxReps => l10n.repsUnit(value.toInt()),
      RecordType.maxVolume => '$value $weightUnit',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return asyncRecords.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, _) => _emptyRow(theme, l10n),
      data: (records) {
        if (records.isEmpty) return _emptyRow(theme, l10n);

        // For bodyweight exercises, skip maxWeight and maxVolume.
        final filtered = equipmentType == EquipmentType.bodyweight
            ? records.where((r) => r.recordType == RecordType.maxReps).toList()
            : records;

        if (filtered.isEmpty) return _emptyRow(theme, l10n);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.personalRecords, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...filtered.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    PRTypeIcon(
                      type: r.recordType,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.recordType.localizedName(l10n),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    Text(
                      _formatValue(r.recordType, r.value, l10n),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyRow(ThemeData theme, AppLocalizations l10n) {
    return Row(
      children: [
        Icon(
          Icons.emoji_events_rounded,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 4),
        Text(
          l10n.noRecordsYet,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}
