import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../l10n/app_localizations.dart';

/// Result returned when the user confirms finishing a workout.
///
/// Q1 (notes-edit-after): the notes field was removed from the finish gate —
/// reflective text at the RPG celebration beat adds friction for the majority
/// who leave it blank and suffers recency bias. Notes are now written on the
/// calm, full-context History detail screen. This record is kept (rather than
/// collapsed to a bare `bool`) so the confirm/cancel contract stays explicit
/// and the type has a natural home if a future finish-gate field returns.
class FinishWorkoutResult {
  const FinishWorkoutResult();
}

/// Dialog shown when the user taps "Finish" on the active workout screen.
///
/// Warns about incomplete sets and confirms the finish. Returns a
/// [FinishWorkoutResult] on confirm, or `null` on cancel.
class FinishWorkoutDialog extends StatelessWidget {
  const FinishWorkoutDialog({required this.incompleteCount, super.key});

  final int incompleteCount;

  static Future<FinishWorkoutResult?> show(
    BuildContext context, {
    required int incompleteCount,
  }) {
    return showDialog<FinishWorkoutResult>(
      context: context,
      builder: (_) => FinishWorkoutDialog(incompleteCount: incompleteCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.finishWorkoutTitle),
      content: incompleteCount > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.incompleteSetsWarning(incompleteCount),
                    style: AppTextStyles.body.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            )
          // No incomplete sets and no notes field — the dialog is a plain
          // confirm gate. A null content keeps AlertDialog's title + actions
          // tightly spaced (no empty content gap).
          : null,
      actions: [
        Semantics(
          container: true,
          identifier: 'workout-keep-going',
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: dialogTextButtonStyle,
            child: Text(l10n.keepGoing),
          ),
        ),
        Semantics(
          container: true,
          identifier: 'workout-dialog-finish',
          label: l10n.saveAndFinish,
          child: FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(const FinishWorkoutResult()),
            // Use the shared FilledButton style so the 48dp floor is the
            // same single-source-of-truth as `dialogTextButtonStyle`.
            style: dialogFilledButtonStyle,
            child: Text(l10n.saveAndFinish),
          ),
        ),
      ],
    );
  }
}
