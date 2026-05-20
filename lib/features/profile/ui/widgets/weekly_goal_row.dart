import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/profile_providers.dart';

/// Tappable row that shows the user's weekly training goal and opens a
/// bottom-sheet picker to change it.
class WeeklyGoalRow extends ConsumerWidget {
  const WeeklyGoalRow({super.key, required this.frequency});

  final int frequency;

  static const _frequencyOptions = [2, 3, 4, 5, 6];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: () => _showFrequencySheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.perWeekLabel(frequency),
                  style: AppTextStyles.title,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFrequencySheet(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.weeklyGoal,
                  style: AppTextStyles.title.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 4),
                Semantics(
                  container: true,
                  identifier: 'profile-goal-sheet-title',
                  child: Text(
                    l10n.frequencyQuestion,
                    style: AppTextStyles.body.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: _frequencyOptions.map((freq) {
                    final isSelected = freq == frequency;
                    return ChoiceChip(
                      label: Text('${freq}x'),
                      selected: isSelected,
                      onSelected: (_) {
                        ref
                            .read(profileProvider.notifier)
                            .updateTrainingFrequency(freq);
                        Navigator.of(ctx).pop();
                      },
                      selectedColor: theme.colorScheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
