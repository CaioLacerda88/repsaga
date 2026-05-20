import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Empty-state placeholder shown on the plan management screen when the
/// current week's bucket has no routines yet.
///
/// Renders a calendar icon, helper text, and two CTAs: a primary
/// "Add routines" button (filled) and a secondary "Auto-fill" button
/// (outlined). Callers wire each CTA up to its respective screen-level
/// handler.
class PlanEmptyState extends StatelessWidget {
  const PlanEmptyState({
    super.key,
    required this.onAddRoutines,
    required this.onAutoFill,
  });

  final VoidCallback onAddRoutines;
  final VoidCallback onAutoFill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noRoutinesPlanned,
            style: AppTextStyles.body.copyWith(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            container: true,
            identifier: 'weekly-plan-add-routines',
            child: FilledButton.icon(
              onPressed: onAddRoutines,
              icon: const Icon(Icons.add),
              label: Text(l10n.addRoutines),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAutoFill,
            icon: const Icon(Icons.repeat),
            label: Text(l10n.autoFill),
          ),
        ],
      ),
    );
  }
}
