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
/// right bracket). See PR #152 for the shipped Direction B layout.
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
    this.isBodyweight = false,
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

  /// True for `EquipmentType.bodyweight` exercises (push-ups, pull-ups,
  /// planks). When true, the row hides the entire weight stepper column —
  /// weight is meaningless for bodyweight movements and a user should not
  /// have to ignore a `0 kg` field that occupies 60% of the input width.
  /// The reps column expands to take the freed space.
  ///
  /// The PR-state resolver in `pr_row_state_resolver.dart` already handles
  /// the corresponding bookkeeping (only `RecordType.maxReps` is checked in
  /// bodyweight mode); this flag aligns the row chrome with that contract.
  ///
  /// Default `false` keeps backwards-compatibility: callers that don't pass
  /// the flag (tests pre-dating this property) get the standard weight +
  /// reps layout.
  final bool isBodyweight;

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

  /// Whether the row's current weight × reps exactly equal the previous-
  /// session set. When true, the row renders a subtle "= last set" indicator
  /// in place of the regular previous-session hint (Pillar 1, Phase 20
  /// post-merge polish).
  ///
  /// Treats null/zero current values as non-matching even if last is also
  /// zero — a freshly-added set with weight=0/reps=0 shouldn't read as
  /// "matching" before the user enters anything.
  bool _matchedLastSet() {
    final lastSet = widget.lastSet;
    if (lastSet == null) return false;
    final currentWeight = widget.set.weight ?? 0;
    final currentReps = widget.set.reps ?? 0;
    if (currentWeight == 0 && currentReps == 0) return false;
    final lastWeight = lastSet.weight ?? 0;
    final lastReps = lastSet.reps ?? 0;
    return currentWeight == lastWeight.toDouble() && currentReps == lastReps;
  }

  /// Whether the regular "Previous: {weight} × {reps}" hint line should be
  /// shown.
  ///
  /// Suppressed when:
  ///   * the set is already completed — the hint stays for *pre-completion*
  ///     reference. (Critique Problem 3 / Pillar 1 argued for keeping the
  ///     hint visible after completion too. The first attempt at that —
  ///     PR #159 — added a sibling Text widget that re-triggered the
  ///     Phase 20 Flutter Web semantics-engine role-swap bug on standing-
  ///     PR rows: the row frame's `flt-semantics-identifier` stopped
  ///     emitting because the new descendant Text caused a subsequent
  ///     SemanticsUpdate during the GenericRole → SemanticButton role
  ///     transition. `Semantics(container: true, explicitChildNodes: true)`
  ///     on the hint Padding kept the LABEL out of the parent group but did
  ///     NOT prevent the role-swap from dropping the row identifier. A
  ///     proper fix needs a layout-stable design — e.g., a fixed-height
  ///     placeholder for the hint slot — so adding/removing the hint Text
  ///     doesn't reflow the parent Column on completion. Deferred to a
  ///     dedicated PR; the match indicator below is shipped alone for now.
  ///   * the values exactly match — that case is covered by the
  ///     match-indicator path ([_matchedLastSet]) which gives the row a
  ///     clearer "you matched last session" affordance.
  bool _shouldShowHint() {
    final lastSet = widget.lastSet;
    if (lastSet == null) return false;
    if (widget.set.isCompleted) return false;
    if (_matchedLastSet()) return false;
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
          if (_matchedLastSet())
            // Subtle "= last set" affordance — Pillar 1's match indicator.
            // Deliberately NOT gold (gold is reserved for PRs by the
            // heroGold scarcity rule). textDim at full alpha gives the line
            // enough weight to read as a confirmation signal without
            // competing with the gold-tinted predicted/standing-PR rows.
            //
            // Wrapped in `Semantics(container: true, explicitChildNodes:
            // true)`: post-Phase-20 the hint is allowed to remain visible
            // after completion, and on a standing-PR row the row frame's
            // SemanticsNode role transitions GenericRole → SemanticButton
            // on a subsequent update. Without an explicit boundary here,
            // the sibling hint Text's label gets collected into the
            // ancestor exercise-card's group, which destabilises the row
            // frame's `flt-semantics-identifier` emission (the role-swap
            // bug captured in `tasks/lessons.md`). The container/explicit-
            // child-nodes pair pins the hint as its own a11y island so the
            // row frame's identifier survives the role swap.
            Padding(
              padding: const EdgeInsets.only(left: 56, bottom: 4, top: 2),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Text(
                  AppLocalizations.of(context).matchedLastSet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else if (_shouldShowHint())
            // Same `Semantics(container: true, explicitChildNodes: true)`
            // a11y-island treatment as the match-indicator branch above —
            // see that block's comment for the rationale.
            Padding(
              padding: const EdgeInsets.only(left: 56, bottom: 4, top: 2),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
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
                // Weight column hidden in bodyweight mode (push-ups, pull-ups,
                // planks). Weight is meaningless for bodyweight movements
                // and `pr_row_state_resolver.dart` already disregards it for
                // PR detection in this mode (only `RecordType.maxReps` is
                // checked). Hiding the column aligns the chrome with the
                // resolver contract; the reps column below absorbs the
                // freed space via `flex: 1` instead of `flex: 2` so it
                // expands to fill the input area between the set-num cell
                // and the done-cell.
                if (!widget.isBodyweight)
                  Expanded(
                    flex: 3,
                    child: _StepperColumn(
                      // No left border: the 3dp left rune-stripe + 48dp
                      // set-num cell already provide visual separation. A
                      // second 1dp hairline immediately to the right of the
                      // cell would double-line the gutter and consume
                      // horizontal slack we cannot afford on 360dp
                      // Brazilian-mid-market screens.
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
                  flex: widget.isBodyweight ? 1 : 2,
                  child: _StepperColumn(
                    // The left hairline border is the visual separator
                    // between weight and reps in the standard layout. In
                    // bodyweight mode the set-num cell is the immediate
                    // left neighbour so the hairline is redundant; drop it
                    // to keep the gutter clean.
                    showLeftBorder: !widget.isBodyweight,
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
/// **Gold render path (heroGold scarcity, structurally enforced).**
///
/// We deliberately scope [RewardAccent] as narrowly as the row state allows:
///
///   * **Predicted / standing PR rows** wrap the WHOLE frame in
///     [RewardAccent] — the gold stripe Builder, the right-bracket Builder
///     (in [_DoneCell]), the ◆ done-mark and the steppers' explicit
///     value-color params all need to resolve gold via `RewardAccent.of`.
///     The stepper +/- IconButtons override the inherited gold IconTheme
///     with their own theme color so they do not leak gold; the stepper
///     value Text widgets set explicit `color:` so they too ignore the
///     ancestor `DefaultTextStyle`.
///
///   * **Superseded-only rows** (`completedSupersededPr`) wrap [RewardAccent]
///     ONLY around the 2% tint Builder — the stripe is green (no
///     RewardAccent needed), there is no right bracket, and the value text
///     is cream-700 (set explicitly by the stepper cells, not via
///     RewardAccent). Scoping the wrap tightly means a future contributor
///     adding a bare `Icon()` or `Text()` inside a stepper cell on a
///     superseded row CANNOT silently render gold — there is no
///     RewardAccent ancestor to inherit from. Structural guarantee, not a
///     "be careful" rule.
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

    // Superseded rows ONLY need RewardAccent for the 2% gold tint Builder —
    // not for the stripe (green, not gold), not for the right bracket
    // (absent), not for the value text (cream-700, set explicitly by the
    // stepper cells). To preserve the heroGold scarcity guarantee
    // STRUCTURALLY rather than relying on IconButton's IconTheme precedence
    // happening to override the inherited gold IconTheme on every stepper
    // child, we narrow the RewardAccent ancestor on superseded rows to wrap
    // ONLY the tint widget. PR rows (predicted / standing) keep the full-
    // frame wrap because their stripe + bracket Builders also need to read
    // `RewardAccent.of(ctx)`.
    //
    // This means: a future contributor adding a bare `Icon()` or `Text()`
    // (without an explicit color) inside a stepper cell of a superseded row
    // CANNOT silently render gold — there is simply no RewardAccent ancestor
    // covering that subtree. The structural guarantee replaces the previous
    // implicit reliance on IconButton internals.
    final bool isSupersededOnly = _isGoldTint && !_isGoldStripe;

    final tintWidget = _isGoldTint
        // 4% gold for predicted/standing, 2% for superseded — see the
        // PrRowState matrix in PLAN.md Phase 20.
        ? Positioned.fill(
            child: Builder(
              builder: (ctx) {
                final gold = RewardAccent.of(ctx)?.color;
                if (gold == null) return const SizedBox.shrink();
                final alpha = display.state == PrRowState.completedSupersededPr
                    ? 0.02
                    : 0.04;
                return ColoredBox(color: gold.withValues(alpha: alpha));
              },
            ),
          )
        : null;

    final frameContent = Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair, width: 1)),
      ),
      child: Stack(
        children: [
          if (tintWidget != null)
            // On superseded-only rows, scope the RewardAccent ancestor
            // tightly to the tint Builder so no descendant of the row frame
            // (steppers, set-num cell, done-cell) can ever inherit the gold
            // IconTheme / DefaultTextStyle. PR rows wrap the whole frame
            // below — their stripe + bracket Builders need the ancestor too.
            isSupersededOnly ? RewardAccent(child: tintWidget) : tintWidget,
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

    // E2E selector hook — expose the row's PR state as a discriminating
    // Semantics identifier so Playwright can distinguish the 5 row states.
    // One identifier per row; the mapping is 1-to-1 with PrRowState.
    // This is purely a test-plumbing node (no label, no exclusiveActions) —
    // it does not affect screen-reader UX. The frame is already semantically
    // described by its children (_SetNumberCell + _DoneCell).
    final String rowStateId;
    switch (display.state) {
      case PrRowState.pendingPredictedPr:
        rowStateId = 'set-row-state-pending-pr';
      case PrRowState.completedStandingPr:
        rowStateId = 'set-row-state-standing-pr';
      case PrRowState.completedSupersededPr:
        rowStateId = 'set-row-state-superseded-pr';
      case PrRowState.completedNonPr:
        rowStateId = 'set-row-state-completed';
      case PrRowState.none:
        rowStateId = 'set-row-state-none';
    }

    // PR rows (predicted / standing) wrap the entire frame in RewardAccent
    // because BOTH the gold stripe (`_isGoldStripe`) Builder AND the right-
    // bracket Builder inside _DoneCell need the ancestor to resolve gold.
    // Superseded-only rows handled above with a narrower wrap.
    final Widget decorated = _isGoldStripe
        ? RewardAccent(child: frameContent)
        : frameContent;

    // `container: true` + `explicitChildNodes: true` is load-bearing — without
    // it, this identifier-only node merges with sibling Semantics in the
    // surrounding tree (header InkWell, column headers, neighbouring set rows),
    // producing a single giant `<flt-semantics role="group" flt-tappable="">`
    // overlay that intercepts pointer events meant for individual buttons.
    // The CI run that surfaced this regression (PR #152, 13 e2e failures)
    // showed the merged group covering "Exercise: … Tap for details. … SET
    // WEIGHT REPS" — i.e. the header InkWell, the column headers, AND the
    // set rows had collapsed into one tappable group. With `container: true`
    // the row owns its own SemanticsNode (the identifier is queryable as
    // `[flt-semantics-identifier="set-row-state-X"]`) and `explicitChildNodes`
    // keeps each descendant's Checkbox / GestureDetector / button semantics
    // independently addressable so per-button identifiers (`workout-set-done`,
    // `workout-set-completed`) keep emitting their own DOM nodes.
    return Semantics(
      identifier: rowStateId,
      container: true,
      explicitChildNodes: true,
      child: decorated,
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

    // Set-type micro-label color (Phase 20 polish #3 — long-press
    // discoverability). Mirrors the rune-stripe color family at ~50–60%
    // alpha so the label reads as quiet metadata, not a competing badge.
    // On a completed row everything dims together via the shared `color`
    // variable above — the label inherits the same alpha falloff.
    final typeLabelColor = set.isCompleted
        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
        : _setTypeLabelColor(set.setType);

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${set.setNumber}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    // Underline hint for tap-to-copy on sets > 1. Note: the
                    // underline lives on the digit, NOT on the type label —
                    // tap-to-copy is a per-digit affordance and adding the
                    // underline to the label would conflate the two
                    // interactions.
                    decoration: isCopyable ? TextDecoration.underline : null,
                    decorationColor: isCopyable
                        ? AppColors.hotViolet.withValues(alpha: 0.4)
                        : null,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
                // Persistent set-type micro-label below the digit. The label
                // is the affordance for the long-press cycle: a user who
                // sees `WU` and wonders what it means, long-presses, and
                // watches it cycle WU → DR → FL → WK has learned the feature
                // without a tooltip. Self-teaching by design.
                Text(
                  set.setType.tinyAbbr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: typeLabelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Set-type micro-label color (pre-completion). Mirrors the gym-floor state
/// palette at reduced alpha — Working tracks the default pending hotViolet,
/// Warmup tracks textCream (the brightest neutral), Drop tracks success
/// (green), Failure tracks **warning amber** (#FFB84D).
///
/// Failure deliberately does NOT use `AppColors.error` (the destructive-
/// action red). Red on a pending to-failure set reads as "something is
/// wrong" rather than "this is a max-effort set." Warning amber is tonally
/// distinct from heroGold (PR scarcity unaffected), distinct from the
/// success green used for dropsets, and distinct from the error red
/// reserved for destructive actions; it reads as "intense / push to limit"
/// without signaling breakage. See PR #163 for the audit + decision trail.
Color _setTypeLabelColor(SetType type) => switch (type) {
  SetType.working => AppColors.hotViolet.withValues(alpha: 0.55),
  SetType.warmup => AppColors.textCream.withValues(alpha: 0.45),
  SetType.dropset => AppColors.success.withValues(alpha: 0.55),
  SetType.failure => AppColors.warning.withValues(alpha: 0.60),
};

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
    // **Flutter Web Semantics role-swap workaround** — see lessons.md and
    // engine source `lib/web_ui/lib/src/engine/semantics/semantics.dart`
    // lines 1763-1771 (identifier dirty marker only fires on value change)
    // and 2282-2312 (role swap creates a new DOM element that only re-
    // applies the dirty attributes).
    //
    // The bug: when a SemanticsNode's role transitions on a SUBSEQUENT
    // semantic update from `GenericRole` → `SemanticButton` — because the
    // tap action arrives via merge from a descendant on the second frame —
    // the new role's freshly-created DOM element does NOT receive the
    // `flt-semantics-identifier` attribute. The identifier was set on the
    // initial frame, the dirty bit was cleared, the role swap creates a
    // fresh element, and the engine never re-marks the identifier dirty.
    // Playwright then can't resolve `[flt-semantics-identifier=...]`.
    //
    // The bug only fires for the predicted-PR path because that path uses
    // `_PredictedPrUncheckedMark` whose `GestureDetector` provides the tap
    // action via SECOND-frame merge (a custom widget's gesture is wired
    // into the AOM after layout). The Checkbox path works correctly
    // because Checkbox emits `isCheckable: true` flag DIRECTLY on the
    // first semantics frame, so its role is established as the identifier
    // is being set — no transition.
    //
    // **The asymmetric fix:**
    //
    //   * Predicted-PR path: the outer Semantics owns the identifier AND
    //     the button role + tap action. The engine sees `isButton=true`
    //     and the tap action on the SAME frame as the identifier+label,
    //     so it assigns `SemanticButton` immediately. No role swap. The
    //     identifier persists on the role's DOM element from frame 1.
    //   * Checkbox path: unchanged. The native Checkbox merge produces
    //     `isCheckable=true` on the first frame, so the role is settled
    //     before the merge cycle that wires up the identifier. No role
    //     transition occurs and the identifier survives.
    //
    // The widget test in `set_row_test.dart` group `predicted-PR
    // semantics contract` pins this contract: it asserts that the
    // identifier-bearing node has both `SemanticsFlag.isButton` AND
    // `SemanticsAction.tap` available. If the engine bug is fixed
    // upstream, that test still passes; if someone refactors the
    // predicted-PR path back to a non-asymmetric design, the test fires.
    final identifier = isCompleted
        ? 'workout-set-completed'
        : 'workout-set-done';
    final label = isCompleted
        ? l10n.setCompleted
        : (_isPredictedPending
              ? l10n.markSetAsDonePredictedPr
              : l10n.markSetAsDone);

    // Resolve the gold from the RewardAccent ancestor so the right-bracket
    // inherits the heroGold scarcity contract (gold is mounted by
    // [_SetRowFrame] for PR-bearing rows only).
    final gold = _hasGoldBracket
        ? (RewardAccent.of(context)?.color ?? Colors.transparent)
        : null;

    final Widget tapTarget = _isPredictedPending
        ? Semantics(
            identifier: identifier,
            label: label,
            button: true,
            // Tap action on the SAME Semantics widget as the identifier so
            // the button role is established on the first frame — bypasses
            // the engine role-swap bug. The inner GestureDetector still
            // receives real pointer events (its semantics are excluded).
            onTap: locked ? null : onChanged,
            child: _PredictedPrUncheckedMark(locked: locked, onTap: onChanged),
          )
        : Semantics(
            identifier: identifier,
            label: label,
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
          );

    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: isCompleted ? AppColors.success.withValues(alpha: 0.08) : null,
        border: gold != null
            ? Border(right: BorderSide(color: gold, width: 4))
            : null,
      ),
      child: Center(child: SizedBox(width: 32, height: 32, child: tapTarget)),
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
    // `excludeFromSemantics: true` is structurally required: the parent
    // [_DoneCell] now owns the button role + tap action on the SAME
    // Semantics widget that carries the `workout-set-done` identifier. If
    // this GestureDetector emitted its own `role=button` semantics on top
    // of that, Flutter's merge would re-create a child SemanticsNode whose
    // role-swap on subsequent frames drops the parent's identifier (engine
    // bug). The detector still receives real touch events via the
    // hit-test path — `excludeFromSemantics` only suppresses the AOM,
    // not pointer routing.
    //
    // Screen-reader UX is preserved by the parent Semantics' label
    // (`markSetAsDonePredictedPr` → "Mark set as done — predicted personal
    // record") and `button: true` flag. SR users hear "button: Mark set
    // as done — predicted personal record" and can activate it.
    return GestureDetector(
      onTap: locked ? null : onTap,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
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
