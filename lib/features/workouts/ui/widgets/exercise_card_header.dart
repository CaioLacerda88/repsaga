import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../exercises/models/exercise.dart';
import '../../providers/workout_providers.dart';

/// Row at the top of each active-workout card — name + info affordance +
/// reorder / swap / delete actions.
///
/// Phase 38b: extracted from `exercise_card.dart` (was `_ExerciseCardHeader`)
/// so the strength [ExerciseCard] and the cardio `CardioEntryCard` share ONE
/// header source of truth — the mockup's "coherence comes from the shell"
/// rule. Owns no state — every interaction is forwarded to a callback
/// supplied by the parent.
///
/// [trailing], when non-null, REPLACES the entire action cluster (reorder
/// arrows / swap / delete). The completed cardio card uses it to render the
/// green ✓ per the locked mockup state 3.
class ExerciseCardHeader extends ConsumerWidget {
  const ExerciseCardHeader({
    required this.exercise,
    required this.workoutExerciseId,
    required this.reorderMode,
    required this.isFirst,
    required this.isLast,
    required this.onShowDetail,
    required this.onSwap,
    required this.onConfirmRemove,
    this.trailing,
    super.key,
  });

  final Exercise? exercise;
  final String workoutExerciseId;
  final bool reorderMode;
  final bool isFirst;
  final bool isLast;
  final void Function(BuildContext context, Exercise exercise) onShowDetail;
  final Future<void> Function(BuildContext context) onSwap;
  final Future<void> Function(BuildContext context) onConfirmRemove;

  /// Replaces the trailing action cluster when non-null (e.g. the green ✓
  /// on a completed cardio entry).
  final Widget? trailing;

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
          // See `PROJECT.md §0 Cluster Ledger` "Semantics container/explicitChildNodes is
          // needed at EVERY tap-merging boundary".
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: l10n.exerciseSemanticsLabel(
              exercise?.name ?? l10n.exerciseGeneric,
            ),
            // PR-3 (H2/Q6): `onLongPress` was wired to the swap-via-picker
            // flow. That gesture was undiscoverable AND destructive — an
            // accidental long-press would silently open the picker and a
            // stray tap on a different exercise immediately re-attributed
            // every logged set to the new PR history. The visible
            // `swap_horiz` IconButton in the header (rendered by the else-
            // branch below) is the sole entry point for swap. Per Q6
            // decision (industry has converged AWAY from gesture shortcuts
            // in gym apps).
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: exercise != null
                  ? () => onShowDetail(context, exercise!)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Inner visual content is decorative — the parent Semantics
                  // label already describes the affordance ("Exercise: ….
                  // Tap for details."). ExcludeSemantics here prevents the
                  // inner Text + Icon from emitting their own semantic
                  // nodes that the AOM would merge upward into a sibling
                  // group, which is exactly the bug PR #152 fix #3 chased.
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            exercise?.name ?? l10n.exerciseGeneric,
                            style: AppTextStyles.title,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // M8 (PR-5) — bumped from 14dp α=0.35 to 16dp α=0.5.
                        // Pre-fix the info glyph was below the visibility
                        // threshold and the "tap header for details"
                        // affordance was invisible to first-time users.
                        // 16dp + 50% alpha reads as a quiet hint without
                        // competing with the exercise name.
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
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
        if (trailing != null)
          trailing!
        else if (reorderMode) ...[
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
