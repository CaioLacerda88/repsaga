import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../l10n/app_localizations.dart';
import 'elapsed_timer.dart';

/// AppBar title block for the active workout screen.
///
/// Renders the editable workout name (TextField when [isEditing] is true,
/// tap-to-edit Row otherwise) above an [ElapsedTimer] readout.
///
/// Owns no state — [isEditing], [nameController], and the lifecycle
/// callbacks are supplied by the parent (`_ActiveWorkoutBodyState`) so this
/// widget stays a presentational column.
///
/// Extracted from `_ActiveWorkoutBodyState.build` to keep the body's build
/// method under the 50-line cap.
class ActiveWorkoutAppBarTitle extends StatelessWidget {
  const ActiveWorkoutAppBarTitle({
    required this.name,
    required this.isEditing,
    required this.nameController,
    required this.onSubmitName,
    required this.onTapToEdit,
    required this.startedAt,
    super.key,
  });

  /// Current display name (used when not editing). Lives on the workout
  /// snapshot — passed in so this widget never reads providers.
  final String name;

  /// True while the user is actively editing — swaps the Row for a TextField.
  final bool isEditing;

  /// Pre-populated controller managed by the parent's State so cursor
  /// position and selection survive widget rebuilds.
  final TextEditingController nameController;

  /// Called when the user submits the name (Enter / tap outside).
  final VoidCallback onSubmitName;

  /// Called when the user taps the static name to begin editing. The parent
  /// is expected to seed [nameController] from [name] and flip `isEditing`.
  final VoidCallback onTapToEdit;

  /// Workout `startedAt` timestamp — passed through to [ElapsedTimer].
  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEditing)
          SizedBox(
            height: 36,
            child: TextField(
              controller: nameController,
              autofocus: true,
              maxLength: 80,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.titleMedium,
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                border: UnderlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => onSubmitName(),
              onTapOutside: (_) => onSubmitName(),
            ),
          )
        else
          Semantics(
            // Family 3 (AW-EX-F-BR1-04) / Family 6 — was a hard-coded
            // English literal. The localized ARB key honors the user's
            // locale when announcing the rename affordance to a screen
            // reader.
            label: l10n.workoutNameTapToRenameSemantics(name),
            child: GestureDetector(
              onTap: onTapToEdit,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(width: 4),
                  AppIcons.render(
                    AppIcons.edit,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        ElapsedTimer(startedAt: startedAt),
      ],
    );
  }
}
