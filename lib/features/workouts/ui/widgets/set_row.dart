import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/enum_l10n.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reps_stepper.dart';
import '../../../../shared/widgets/reward_accent.dart';
import '../../../../shared/widgets/weight_stepper.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../domain/pr_row_state.dart';
import '../../models/exercise_set.dart';
import '../../models/set_type.dart';
import '../../providers/notifiers/active_workout_notifier.dart';

/// Displays a single set within an exercise card during an active workout.
///
/// Phase 20 commit 4 (Direction B + 5-state PR matrix): tactile data-table
/// row composed of four fixed-shape columns — set-number, weight stepper,
/// reps stepper, done-mark — overlaid with the PR-state chrome (left
/// rune-stripe, background tint, value text accent, done-mark variant,
/// right bracket). Layout mirrors `docs/design/2026-05-01-active-workout-
/// redesign/direction-b-pr-refined.html`.
///
/// **5-state matrix** (driven by [display]):
///
///   * [PrRowState.none] — pending, no projected PR. 3dp violet stripe,
///     no tint, cream value, ○ violet-bordered done-mark.
///   * [PrRowState.pendingPredictedPr] — pending whose values would beat
///     the standing record. 4dp gold stripe, 4% gold tint, gold value(s)
///     (those in [PrRowDisplay.accentTypes]), gold ◆ done-mark, 4dp gold
///     right bracket.
///   * [PrRowState.completedNonPr] — completed, no PR broken. 3dp green
///     stripe, no tint, dim values (60% via Opacity), ✓ green done-mark.
///   * [PrRowState.completedSupersededPr] — completed PR superseded by a
///     later set in the same workout. 3dp green stripe, 2% gold tint,
///     cream-700 value(s) (those in [PrRowDisplay.accentTypes]), ✓ green
///     done-mark. NO right bracket — distinguishes from standing.
///   * [PrRowState.completedStandingPr] — completed PR currently the best
///     across all history. 4dp gold stripe, 4% gold tint, gold value(s),
///     ✓ green done-mark, 4dp gold right bracket.
///
/// **heroGold scarcity contract** (`scripts/check_reward_accent.sh`):
/// gold appears in EXACTLY three places per the locked spec — left stripe,
/// PR'd value text, right bracket. Plus the predicted-PR ◆ done-mark.
/// Every gold render goes through a [RewardAccent] ancestor; this widget
/// never references `AppColors.heroGold` directly.
///
/// **Unidirectional data flow:** the [PrRowState] / [PrRowDisplay] is
/// computed by the pure `resolveRowDisplays` resolver, exposed by the
/// `activeWorkoutRowDisplaysProvider` family in `workout_providers.dart`,
/// and passed in here as a constructor param. SetRow does NOT recompute —
/// it just renders.
class SetRow extends ConsumerStatefulWidget {
  const SetRow({
    required this.set,
    required this.workoutExerciseId,
    this.display = const PrRowDisplay.plain(PrRowState.none),
    this.onCompleted,
    this.lastSet,
    this.isNew = false,
    super.key,
  });

  final ExerciseSet set;
  final String workoutExerciseId;

  /// PR display state + per-cell accent record types (Phase 20 commit 4).
  ///
  /// Defaults to `none` so callers that don't yet wire the resolver (tests,
  /// migrations, etc.) get the baseline pending row. Production callers
  /// (ExerciseCard) MUST pass the resolver output — see
  /// `activeWorkoutRowDisplaysProvider`.
  final PrRowDisplay display;

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
            display: widget.display,
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
                      isAccented: widget.display.isWeightAccented,
                      isSuperseded:
                          widget.display.state ==
                          PrRowState.completedSupersededPr,
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
                      isAccented: widget.display.isRepsAccented,
                      isSuperseded:
                          widget.display.state ==
                          PrRowState.completedSupersededPr,
                    ),
                  ),
                ),
                _DoneCell(
                  display: widget.display,
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

/// Outer frame: enforces 56dp uniform row height across all states, paints
/// the left rune-stripe (3dp violet/green for non-PR, 4dp gold for PR), and
/// the 1dp hairline bottom divider. Composes the gold-tint background for
/// PR rows ON TOP of the row by stacking a [Positioned.fill] tint behind
/// the content.
///
/// The stripe is a fixed-width sibling rather than a CSS-style absolute
/// overlay because Flutter's `Stack` plus `Row(crossAxisAlignment: stretch)`
/// fights itself into an infinite-height layout loop. A leading `SizedBox`
/// is structurally simpler. The 3dp→4dp width swap on PR rows shifts row
/// content by 1dp horizontally — well below perceptual threshold and
/// absorbed by the flex columns.
///
/// **Gold render path:** PR rows wrap the entire frame in [RewardAccent].
/// IconButton's internal `IconTheme` override means the stepper +/- icons
/// keep their M3-resolved color (not gold), and the stepper value Text
/// widgets set explicit `color:` so they are never affected by
/// [RewardAccent]'s `DefaultTextStyle.merge`. The gold render targets are
/// the small [Builder] widgets inside this frame (left stripe, right
/// bracket, ◆ done-mark) and the value-color overrides passed down to the
/// steppers via constructor params.
class _SetRowFrame extends StatelessWidget {
  const _SetRowFrame({
    required this.child,
    required this.isCompleted,
    required this.display,
  });

  final Widget child;
  final bool isCompleted;
  final PrRowDisplay display;

  bool get _isGoldStripe =>
      display.state == PrRowState.pendingPredictedPr ||
      display.state == PrRowState.completedStandingPr;

  bool get _isGoldTint =>
      display.state == PrRowState.pendingPredictedPr ||
      display.state == PrRowState.completedStandingPr ||
      display.state == PrRowState.completedSupersededPr;

  @override
  Widget build(BuildContext context) {
    final stripeColor = _isGoldStripe
        ? null // gold rendered via RewardAccent + Builder below
        : (isCompleted ? AppColors.success : AppColors.hotViolet);
    final stripeWidth = _isGoldStripe ? 4.0 : 3.0;

    final frameContent = Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair, width: 1)),
      ),
      child: Stack(
        children: [
          if (_isGoldTint)
            // 4% gold for predicted/standing, 2% for superseded — see the
            // PrRowState matrix in PLAN.md Phase 20.
            Positioned.fill(
              child: Builder(
                builder: (ctx) {
                  final gold = RewardAccent.of(ctx)?.color;
                  if (gold == null) return const SizedBox.shrink();
                  final alpha =
                      display.state == PrRowState.completedSupersededPr
                      ? 0.02
                      : 0.04;
                  return ColoredBox(color: gold.withValues(alpha: alpha));
                },
              ),
            ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isGoldStripe)
                  // 4dp gold rune-stripe — first of the three legal gold
                  // surfaces on a standing/predicted PR row.
                  SizedBox(
                    width: stripeWidth,
                    child: Builder(
                      builder: (ctx) {
                        final gold = RewardAccent.of(ctx)?.color;
                        return ColoredBox(color: gold ?? Colors.transparent);
                      },
                    ),
                  )
                else
                  Container(width: stripeWidth, color: stripeColor),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );

    // Wrap PR rows (gold stripe / tint / right bracket / value text) in a
    // single RewardAccent so every internal `RewardAccent.of(ctx)` resolves.
    // IconButton's IconTheme override prevents the stepper +/- icons from
    // inheriting gold; the steppers' value Text widgets set explicit colors
    // so they too are unaffected — the gold only lands on the targets that
    // explicitly opt in via Builder + RewardAccent.of, or via the explicit
    // valueColor params on the steppers.
    if (_isGoldStripe || _isGoldTint) {
      return RewardAccent(child: frameContent);
    }
    return frameContent;
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
///
/// On PR rows whose accent set covers the weight value, the stepper's value
/// text renders in gold (predicted/standing) or cream-700 (superseded). The
/// gold color is read from the ancestor [RewardAccent] via
/// `RewardAccent.of(context)`; cream is the default theme color so the
/// superseded state just clears the dim Opacity and keeps the cream weight.
class _WeightStepperCell extends ConsumerWidget {
  const _WeightStepperCell({
    required this.set,
    required this.weightUnit,
    required this.workoutExerciseId,
    required this.isAccented,
    required this.isSuperseded,
  });

  final ExerciseSet set;
  final String weightUnit;
  final String workoutExerciseId;
  final bool isAccented;
  final bool isSuperseded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(activeWorkoutProvider.notifier);

    // Dim rule: completed AND not carrying any accent keeps the 60% Opacity
    // ghost. Superseded rows clear the dim on the accented value(s) so the
    // cream-700 reads at full strength. Standing/predicted PR rows render
    // accented values at full strength regardless.
    final shouldDim = set.isCompleted && !isAccented;
    final dim = shouldDim ? 0.6 : 1.0;
    final unitColor = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    // Resolve the value-color override.
    //   * Superseded + accented → cream-700 (textCream w700) — explicit
    //     "you got there" signal without claiming gold parity.
    //   * Predicted/standing + accented → gold via RewardAccent.of(ctx).
    //   * Otherwise → null (let stepper fall back to theme primary).
    Color? valueColor;
    FontWeight? valueFontWeight;
    if (isAccented) {
      if (isSuperseded) {
        valueColor = AppColors.textCream;
        valueFontWeight = FontWeight.w700;
      } else {
        // Predicted or standing — pull gold from the ancestor RewardAccent.
        valueColor = RewardAccent.of(context)?.color;
        valueFontWeight = FontWeight.w800;
      }
    }

    return Opacity(
      opacity: dim,
      child: Row(
        children: [
          Expanded(
            child: WeightStepper(
              value: set.weight ?? 0,
              unit: weightUnit,
              valueColor: valueColor,
              valueFontWeight: valueFontWeight,
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
///
/// PR-accent rules mirror [_WeightStepperCell] — see that widget's doc for
/// the dim/superseded/standing decision tree.
class _RepsStepperCell extends ConsumerWidget {
  const _RepsStepperCell({
    required this.set,
    required this.workoutExerciseId,
    required this.isAccented,
    required this.isSuperseded,
  });

  final ExerciseSet set;
  final String workoutExerciseId;
  final bool isAccented;
  final bool isSuperseded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final shouldDim = set.isCompleted && !isAccented;
    final dim = shouldDim ? 0.6 : 1.0;

    Color? valueColor;
    FontWeight? valueFontWeight;
    if (isAccented) {
      if (isSuperseded) {
        valueColor = AppColors.textCream;
        valueFontWeight = FontWeight.w700;
      } else {
        valueColor = RewardAccent.of(context)?.color;
        valueFontWeight = FontWeight.w800;
      }
    }

    return Opacity(
      opacity: dim,
      child: RepsStepper(
        value: set.reps ?? 0,
        valueColor: valueColor,
        valueFontWeight: valueFontWeight,
        onChanged: (v) =>
            notifier.updateSet(workoutExerciseId, set.id, reps: v),
      ),
    );
  }
}

/// 52dp done-col with the completion control, plus the optional 4dp gold
/// right-bracket on standing/predicted PR rows.
///
/// The done-control rendering depends on [PrRowState] + completion:
///   * pending non-PR → `Checkbox` with violet 1.5dp border (○).
///   * pending predicted-PR → [_PredictedPrUncheckedMark] (◆ gold rune in
///     a gold-bordered box).
///   * completed (any state) → `Checkbox(value: true)` with green check.
class _DoneCell extends StatelessWidget {
  const _DoneCell({
    required this.display,
    required this.isCompleted,
    required this.locked,
    required this.onChanged,
  });

  final PrRowDisplay display;
  final bool isCompleted;
  final bool locked;
  final VoidCallback onChanged;

  bool get _hasGoldBracket =>
      display.state == PrRowState.pendingPredictedPr ||
      display.state == PrRowState.completedStandingPr;

  bool get _isPredictedPending =>
      display.state == PrRowState.pendingPredictedPr && !isCompleted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: isCompleted ? 'workout-set-completed' : 'workout-set-done',
      label: isCompleted
          ? l10n.setCompleted
          : (_isPredictedPending
                ? l10n.markSetAsDonePredictedPr
                : l10n.markSetAsDone),
      child: SizedBox(
        width: 52,
        // Stack the gold right-bracket overlay ABOVE the green tint and
        // checkbox so the bracket reads as a structural row edge rather
        // than a chip badge.
        child: Stack(
          children: [
            // Faint green tint behind a completed row's done-mark — mirrors the
            // mockup's `.done-col.completed { background: rgba(98,196,109,0.08) }`.
            Container(
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.success.withValues(alpha: 0.08)
                    : null,
              ),
            ),
            Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: _isPredictedPending
                    ? _PredictedPrUncheckedMark(
                        locked: locked,
                        onTap: onChanged,
                      )
                    : Checkbox(
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
            if (_hasGoldBracket)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: 4,
                child: Builder(
                  builder: (ctx) {
                    final gold = RewardAccent.of(ctx)?.color;
                    return ColoredBox(color: gold ?? Colors.transparent);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Custom unchecked mark for the predicted-PR row state. Renders a 32dp box
/// with a 1.5dp gold border at 50% opacity and a faint gold ◆ (U+25C6) glyph
/// at 70% opacity — visually says "this set is teed up to break a record".
///
/// Replaces the standard violet-bordered `Checkbox` only when the row is in
/// [PrRowState.pendingPredictedPr] and not yet completed. Tapping toggles
/// completion exactly like the standard checkbox would. Honors the same
/// `locked` flag the parent's _SetRowState uses to suppress fat-thumb taps
/// on freshly-added sets.
///
/// **Gold render path:** the border and glyph colors come from
/// `RewardAccent.of(context)`. The widget is built INSIDE the
/// [_SetRowFrame]'s [RewardAccent] ancestor, which is established whenever
/// the row's display is gold-bearing. If the ancestor is somehow missing
/// (defensive) the colors fall back to transparent — the box still tap-
/// targets but renders invisibly, surfacing the wiring bug rather than
/// silently using the wrong color.
class _PredictedPrUncheckedMark extends StatelessWidget {
  const _PredictedPrUncheckedMark({required this.locked, required this.onTap});

  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = RewardAccent.of(context)?.color ?? Colors.transparent;
    return GestureDetector(
      onTap: locked ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: gold.withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          '◆', // ◆ BLACK DIAMOND
          style: TextStyle(
            color: gold.withValues(alpha: 0.7),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1,
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
