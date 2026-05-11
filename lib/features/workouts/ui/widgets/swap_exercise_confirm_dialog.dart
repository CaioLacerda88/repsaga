import 'package:flutter/material.dart';

import '../../../../core/theme/dialog_button_style.dart';
import '../../../../l10n/app_localizations.dart';

/// Confirm dialog shown before swapping an exercise that already has one or
/// more completed sets in the active workout.
///
/// **PR-3 (Q3) — conditional confirm with concrete exercise names.** Per Q3
/// product decision and the UI critic guidance on the PR-1 review pass, the
/// copy MUST name BOTH sides of the swap (old + new) plus the count of
/// logged sets that will re-attribute to the new exercise's PR history.
/// Generic "the new exercise" copy was explicitly rejected — concrete names
/// preserve the user's mental model and surface the data-attribution
/// consequence in plain language.
///
/// Wraps the actions in `Semantics(identifier:)` pair-rule wrappers so the
/// E2E suite can target Cancel and Swap deterministically (see
/// `WORKOUT.swapExerciseConfirmCancelButton` / `swapExerciseConfirmSwapButton`
/// in `test/e2e/helpers/selectors.ts`).
class SwapExerciseConfirmDialog extends StatelessWidget {
  const SwapExerciseConfirmDialog({
    required this.oldExerciseName,
    required this.newExerciseName,
    required this.completedSetCount,
    super.key,
  });

  final String oldExerciseName;
  final String newExerciseName;
  final int completedSetCount;

  /// Show the dialog as a modal. Returns `true` when the user taps Swap,
  /// `false` when they tap Cancel, `null` when they dismiss the barrier.
  static Future<bool?> show(
    BuildContext context, {
    required String oldExerciseName,
    required String newExerciseName,
    required int completedSetCount,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => SwapExerciseConfirmDialog(
        oldExerciseName: oldExerciseName,
        newExerciseName: newExerciseName,
        completedSetCount: completedSetCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      // PR-3 — pair-rule Semantics so the E2E suite can find the dialog
      // boundary deterministically. Title-as-identifier holds across
      // locales (en + pt) because the identifier is locale-independent
      // by construction.
      title: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'workout-swap-confirm-dialog',
        child: Text(l10n.swapExerciseConfirmTitle(newExerciseName)),
      ),
      content: Text(
        l10n.swapExerciseConfirmBody(
          completedSetCount,
          newExerciseName,
          oldExerciseName,
        ),
      ),
      actions: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'workout-swap-confirm-cancel',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: dialogTextButtonStyle,
            child: Text(l10n.cancel),
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'workout-swap-confirm-swap',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: dialogTextButtonStyle,
            child: Text(l10n.swapExerciseConfirmAction),
          ),
        ),
      ],
    );
  }
}
