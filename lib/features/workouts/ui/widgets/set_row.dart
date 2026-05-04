import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/enum_l10n.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reps_stepper.dart';
import '../../../../shared/widgets/weight_stepper.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../models/exercise_set.dart';
import '../../models/set_type.dart';
import '../../providers/notifiers/active_workout_notifier.dart';

/// Displays a single set within an exercise card during an active workout.
///
/// Phase 20 commit 2 (Direction B): tactile data-table row composed of four
/// fixed-shape columns — set-number, weight stepper, reps stepper, done-mark.
/// Layout mirrors `docs/design/2026-05-01-active-workout-redesign/
/// direction-b-pr-refined.html`:
///
///   * `Row` with `crossAxisAlignment: stretch`, `minHeight: 56` so every
///     state (pending / pending-active / completed / superseded-PR /
///     standing-PR) has the same vertical rhythm and identical baselines.
///   * Left 3dp rune-stripe (`--pv` violet on pending, `--success` green on
///     completed) painted via a `Stack` overlay so it never displaces cell
///     content. Commit 4 widens it to 4dp `--gold` for standing-PR rows.
///   * Set-number cell: 44dp wide visual, ≥48dp tap target (BUG-018 floor).
///     Tap copies the previous set; long-press cycles set type. The
///     set-type abbreviation badge ("W"/"WU"/"D"/"F") was removed from this
///     cell — set type is communicated by the left rune-stripe color.
///   * Weight column flex-3, reps column flex-2, both with 1dp hairline
///     borders. The refactored [WeightStepper] / [RepsStepper] flex-fill
///     their tap zones (BUG-019 fix from commit 1).
///   * Done-col: 52dp wide with a 4dp transparent right-border reservation
///     so commit 4's gold bracket on PR rows lands without shifting layout.
///
/// PR-specific styling (gold edge frame, supersession ghost-tint, predicted
/// PR ◆ done-mark) is intentionally absent — commit 4 wires that on top of
/// this layout.
class SetRow extends ConsumerStatefulWidget {
  const SetRow({
    required this.set,
    required this.workoutExerciseId,
    this.onCompleted,
    this.lastSet,
    this.isNew = false,
    super.key,
  });

  final ExerciseSet set;
  final String workoutExerciseId;

  /// Called after the set completion is toggled (for rest timer integration).
  final VoidCallback? onCompleted;

  /// The matching set from the previous workout session, used to show a hint.
  final ExerciseSet? lastSet;

  /// Whether this set was just added. When true, the completion checkbox
  /// is locked for 600ms to prevent accidental taps from thumb drift.
  final bool isNew;

  @override
  ConsumerState<SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<SetRow> {
  bool _locked = false;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _locked = true;
      _lockTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _locked = false);
      });
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  void _cycleSetType() {
    const types = SetType.values;
    final nextIndex = (types.indexOf(widget.set.setType) + 1) % types.length;
    ref
        .read(activeWorkoutProvider.notifier)
        .updateSet(
          widget.workoutExerciseId,
          widget.set.id,
          setType: types[nextIndex],
        );
  }

  void _copyLastSet() {
    ref
        .read(activeWorkoutProvider.notifier)
        .copyLastSet(widget.workoutExerciseId, widget.set.id);
  }

  void _onComplete() {
    if (_locked) return;
    final wasCompleted = widget.set.isCompleted;
    ref
        .read(activeWorkoutProvider.notifier)
        .completeSet(widget.workoutExerciseId, widget.set.id);
    if (!wasCompleted) {
      HapticFeedback.mediumImpact();
      widget.onCompleted?.call();
    }
  }

  /// Whether the previous-session hint line should be shown.
  ///
  /// Suppress the hint when pre-filled values match the last session exactly
  /// and the set is not yet completed (the hint is redundant in that case).
  bool _shouldShowHint() {
    final lastSet = widget.lastSet;
    if (lastSet == null) return false;
    if (widget.set.isCompleted) return false;

    final currentWeight = widget.set.weight ?? 0;
    final currentReps = widget.set.reps ?? 0;
    final lastWeight = lastSet.weight ?? 0;
    final lastReps = lastSet.reps ?? 0;

    if (currentWeight == lastWeight.toDouble() && currentReps == lastReps) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = widget.set;
    final weightUnit = ref.watch(profileProvider).value?.weightUnit ?? 'kg';

    return Dismissible(
      key: ValueKey(set.id),
      direction: DismissDirection.endToStart,
      background: _DismissBackground(theme: theme),
      confirmDismiss: (_) async {
        // Guard against concurrent swipes removing the same set twice.
        final current = ref.read(activeWorkoutProvider).value;
        if (current == null) return false;
        final exercise = current.exercises
            .where((e) => e.workoutExercise.id == widget.workoutExerciseId)
            .firstOrNull;
        if (exercise == null) return false;
        return exercise.sets.any((s) => s.id == set.id);
      },
      onDismissed: (_) {
        HapticFeedback.lightImpact();
        final notifier = ref.read(activeWorkoutProvider.notifier);
        final deletedSet = set;
        notifier.deleteSet(widget.workoutExerciseId, set.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).setDeleted(deletedSet.setNumber),
              ),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: AppLocalizations.of(context).undo,
                onPressed: () {
                  notifier.restoreSet(widget.workoutExerciseId, deletedSet);
                },
              ),
            ),
          );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_shouldShowHint())
            Padding(
              padding: const EdgeInsets.only(left: 56, bottom: 4, top: 2),
              child: Text(
                AppLocalizations.of(context).previousSet(
                  AppNumberFormat.weight(
                    (widget.lastSet!.weight ?? 0).toDouble(),
                    locale: Localizations.localeOf(context).languageCode,
                  ),
                  weightUnit,
                  widget.lastSet!.reps ?? 0,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          _SetRowFrame(
            isCompleted: set.isCompleted,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SetNumberCell(
                  set: set,
                  onTap: set.setNumber > 1 ? _copyLastSet : null,
                  onLongPress: _cycleSetType,
                ),
                Expanded(
                  flex: 3,
                  child: _StepperColumn(
                    // No left border: the 3dp left rune-stripe + 48dp set-num
                    // cell already provide visual separation. A second 1dp
                    // hairline immediately to the right of the cell would
                    // double-line the gutter and consume horizontal slack
                    // we cannot afford on 360dp Brazilian-mid-market screens.
                    child: _WeightStepperCell(
                      set: set,
                      weightUnit: weightUnit,
                      workoutExerciseId: widget.workoutExerciseId,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _StepperColumn(
                    showLeftBorder: true,
                    child: _RepsStepperCell(
                      set: set,
                      workoutExerciseId: widget.workoutExerciseId,
                    ),
                  ),
                ),
                _DoneCell(
                  isCompleted: set.isCompleted,
                  locked: _locked,
                  onChanged: _onComplete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Outer frame: enforces 56dp uniform row height across all states and paints
/// the 3dp left rune-stripe (violet for pending, green for completed) plus
/// the 1dp hairline bottom divider.
///
/// The stripe is a fixed-width sibling rather than a CSS-style absolute
/// overlay because Flutter's `Stack` plus `Row(crossAxisAlignment: stretch)`
/// fights itself into an infinite-height layout loop. A 3dp leading
/// `SizedBox` is structurally simpler, costs the same 3dp horizontally as
/// the mockup, and survives commit 4's 3dp→4dp gold widening with a
/// single-pixel shift on PR rows that's well below perceptual threshold.
///
/// PR-state composition (commit 4): the stripe color/width swap to
/// `AppColors.heroGold` / 4dp on standing-PR rows, paired with a 4dp gold
/// right-border on [_DoneCell] (whose 4dp transparent reservation already
/// holds the layout slot today).
class _SetRowFrame extends StatelessWidget {
  const _SetRowFrame({required this.child, required this.isCompleted});

  final Widget child;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final stripeColor = isCompleted ? AppColors.success : AppColors.hotViolet;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair, width: 1)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: stripeColor),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Set-number cell. Visually 44dp wide per the mockup, but the tap target
/// constraints stay at the Material 48dp floor (BUG-018) so the cell is
/// reliably hittable mid-workout.
///
/// The set-type abbreviation badge ("W"/"WU"/"D"/"F") was intentionally
/// removed from this cell — the set type is now signaled by the left
/// rune-stripe color, freeing the number cell to be a single, large,
/// scannable digit.
class _SetNumberCell extends StatelessWidget {
  const _SetNumberCell({
    required this.set,
    required this.onTap,
    required this.onLongPress,
  });

  final ExerciseSet set;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isCopyable = set.setNumber > 1;
    final color = set.isCompleted
        ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
        : (isCopyable
              ? AppColors.hotViolet.withValues(alpha: 0.9)
              : AppColors.textCream);

    return Semantics(
      label: isCopyable
          ? l10n.setNumberCopySemantics(
              set.setNumber,
              set.setType.localizedName(l10n),
            )
          : l10n.setNumberSemantics(
              set.setNumber,
              set.setType.localizedName(l10n),
            ),
      child: Tooltip(
        message: isCopyable
            ? l10n.tooltipCopyLastSetAndChangeType
            : l10n.tooltipChangeType,
        preferBelow: true,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            // BUG-018: tap-target floor is Material's 48x48 minimum. The
            // visual cell width target from the mockup is 44dp, but giving
            // up 4dp of horizontal real-estate to honor the tap-target
            // contract is the correct trade-off — the row no longer
            // mis-fires the copy-last-set / cycle-set-type interactions
            // under sweaty thumbs.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            alignment: Alignment.center,
            child: Text(
              '${set.setNumber}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                // Underline hint for tap-to-copy on sets > 1.
                decoration: isCopyable ? TextDecoration.underline : null,
                decorationColor: isCopyable
                    ? AppColors.hotViolet.withValues(alpha: 0.4)
                    : null,
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical separator wrapper around a stepper. The mockup's stepper columns
/// use 1dp hairline borders to read as discrete data-table cells without
/// going full Excel-grid. We render only the LEFT hairline on the reps
/// column — the weight column relies on the 3dp left rune-stripe + 48dp
/// set-num cell for separation, and the done-col tints itself green when
/// completed (or pulls a 4dp gold bracket on standing-PR rows in commit 4),
/// either of which serves as the trailing separator.
class _StepperColumn extends StatelessWidget {
  const _StepperColumn({required this.child, this.showLeftBorder = false});

  final Widget child;
  final bool showLeftBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: showLeftBorder
              ? const BorderSide(color: AppColors.hair, width: 1)
              : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

/// Weight column inner: stepper + tiny "kg" label aligned to the right.
class _WeightStepperCell extends ConsumerWidget {
  const _WeightStepperCell({
    required this.set,
    required this.weightUnit,
    required this.workoutExerciseId,
  });

  final ExerciseSet set;
  final String weightUnit;
  final String workoutExerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final dim = set.isCompleted ? 0.6 : 1.0;
    final unitColor = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Opacity(
      opacity: dim,
      child: Row(
        children: [
          Expanded(
            child: WeightStepper(
              value: set.weight ?? 0,
              unit: weightUnit,
              onChanged: (v) =>
                  notifier.updateSet(workoutExerciseId, set.id, weight: v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              weightUnit,
              style: theme.textTheme.labelSmall?.copyWith(
                color: unitColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reps column inner: stepper, no unit suffix (the column header carries
/// "REPS"; cluttering each row with the literal would dilute the data).
class _RepsStepperCell extends ConsumerWidget {
  const _RepsStepperCell({required this.set, required this.workoutExerciseId});

  final ExerciseSet set;
  final String workoutExerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final dim = set.isCompleted ? 0.6 : 1.0;

    return Opacity(
      opacity: dim,
      child: RepsStepper(
        value: set.reps ?? 0,
        onChanged: (v) =>
            notifier.updateSet(workoutExerciseId, set.id, reps: v),
      ),
    );
  }
}

/// 52dp done-col with the completion checkbox. Commit 4 will add a 4dp
/// `AppColors.heroGold` right-border on standing-PR rows. The 4dp shift
/// only affects the trailing edge of the row and does not displace any
/// data-baseline content, so reserving the slot pre-emptively today would
/// only steal horizontal slack we cannot afford on 360dp screens.
class _DoneCell extends StatelessWidget {
  const _DoneCell({
    required this.isCompleted,
    required this.locked,
    required this.onChanged,
  });

  final bool isCompleted;
  final bool locked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: isCompleted ? 'workout-set-completed' : 'workout-set-done',
      label: isCompleted ? l10n.setCompleted : l10n.markSetAsDone,
      child: Container(
        width: 52,
        // Faint green tint behind a completed row's done-mark — mirrors the
        // mockup's `.done-col.completed { background: rgba(98,196,109,0.08) }`.
        // Commit 4 will conditionally add a 4dp heroGold right-border for
        // standing-PR rows; the 4dp shift sits at the trailing row edge and
        // does not displace any data-baseline content.
        decoration: BoxDecoration(
          color: isCompleted ? AppColors.success.withValues(alpha: 0.08) : null,
        ),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              value: isCompleted,
              onChanged: locked ? null : (_) => onChanged(),
              activeColor: AppColors.success,
              checkColor: AppColors.textCream,
              side: BorderSide(
                color: AppColors.hotViolet.withValues(alpha: 0.4),
                width: 1.5,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 16),
      color: theme.colorScheme.error.withValues(alpha: 0.3),
      child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
    );
  }
}
