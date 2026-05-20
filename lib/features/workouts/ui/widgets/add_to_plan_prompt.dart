import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Shows a compact bottom sheet asking if the user wants to add
/// a standalone routine to their weekly plan.
///
/// Returns `true` if the user tapped "Add", `false` if "Skip",
/// or `null` if dismissed.
Future<bool?> showAddToPlanPrompt(
  BuildContext context, {
  required String routineName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (context) => _AddToPlanPromptContent(routineName: routineName),
  );
}

class _AddToPlanPromptContent extends StatelessWidget {
  const _AddToPlanPromptContent({required this.routineName});

  final String routineName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.addToPlanPrompt(routineName),
                    style: AppTextStyles.body.copyWith(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.skip),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
