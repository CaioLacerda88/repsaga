import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Empty-state body shown when the active workout has zero exercises.
///
/// Owns its own "Add exercise" CTA — when this body is rendered the screen's
/// FAB and Finish bottom bar are intentionally hidden, so this is the only
/// visible action. The Semantics identifier `workout-add-exercise` is the
/// E2E selector contract — duplicated on the FAB so Playwright matches
/// either entry point with the same selector.
class EmptyWorkoutBody extends StatelessWidget {
  const EmptyWorkoutBody({required this.onAddExercise, super.key});

  final VoidCallback onAddExercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcons.render(
              AppIcons.lift,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).addFirstExercise,
              style: AppTextStyles.title.copyWith(
                fontSize: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).tapButtonToStart,
              style: AppTextStyles.body.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              container: true,
              identifier: 'workout-add-exercise',
              child: FilledButton.icon(
                onPressed: onAddExercise,
                icon: const Icon(Icons.add),
                label: Text(AppLocalizations.of(context).addExercise),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
