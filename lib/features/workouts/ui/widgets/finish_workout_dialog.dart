import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../l10n/app_localizations.dart';

/// Result returned when the user confirms finishing a workout.
class FinishWorkoutResult {
  const FinishWorkoutResult({this.notes});

  final String? notes;
}

/// Dialog shown when the user taps "Finish" on the active workout screen.
///
/// Warns about incomplete sets and allows adding optional notes.
/// Returns a [FinishWorkoutResult] on confirm, or `null` on cancel.
class FinishWorkoutDialog extends StatefulWidget {
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
  State<FinishWorkoutDialog> createState() => _FinishWorkoutDialogState();
}

class _FinishWorkoutDialogState extends State<FinishWorkoutDialog> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.finishWorkoutTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.incompleteCount > 0) ...[
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.incompleteSetsWarning(widget.incompleteCount),
                    style: AppTextStyles.body.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Semantics(
            container: true,
            identifier: 'workout-notes',
            label: l10n.notes,
            child: TextField(
              controller: _notesController,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: l10n.addNotesHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
        ],
      ),
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
            onPressed: () {
              final notes = _notesController.text.trim();
              Navigator.of(
                context,
              ).pop(FinishWorkoutResult(notes: notes.isEmpty ? null : notes));
            },
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
