import 'package:flutter/material.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/models/weekly_plan.dart';
import 'routine_chip.dart';

/// Displays the WEEK COMPLETE review state when all bucket routines are done.
///
/// Shows: header, stats row, completed chips.
/// Per spec: no shame text for incomplete plans, just reduced opacity for
/// remaining items.
class WeekReviewSection extends StatelessWidget {
  const WeekReviewSection({
    required this.plan,
    required this.routineNames,
    this.totalVolume = 0,
    this.prCount = 0,
    this.weightUnit = 'kg',
    this.onNewWeek,
    super.key,
  });

  final WeeklyPlan plan;

  /// Maps routine IDs to display names.
  final Map<String, String> routineNames;

  /// Total volume lifted this week (in user's weight unit).
  final double totalVolume;

  /// Number of PRs hit this week.
  final int prCount;

  /// User's preferred weight unit ('kg' or 'lbs').
  final String weightUnit;

  /// Called when user taps NEW WEEK.
  final VoidCallback? onNewWeek;

  /// Green is reserved for positive completion beats ("WEEK COMPLETE" header
  /// + the `RoutineChipState.done` accent) — anything green signals "this
  /// milestone is achieved." The NEW WEEK affordance is a navigation CTA, not
  /// a completion signal, so it paints in the daily interactive violet.
  static const _completeHeaderColor = AppColors.success;
  static const _newWeekLinkColor = AppColors.hotViolet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final completedCount = plan.routines
        .where((r) => r.completedWorkoutId != null)
        .length;
    final isAllComplete =
        plan.routines.isNotEmpty &&
        plan.routines.every((r) => r.completedWorkoutId != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                identifier: isAllComplete
                    ? 'weekly-plan-complete'
                    : 'weekly-plan-this-week',
                child: Text(
                  isAllComplete ? l10n.weekComplete : l10n.thisWeek,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 13,
                    letterSpacing: 0.12 * 13,
                    fontWeight: FontWeight.w700,
                    color: isAllComplete
                        ? _completeHeaderColor
                        : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
            if (onNewWeek != null)
              InkWell(
                onTap: onNewWeek,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    l10n.newWeekLink,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 13,
                      letterSpacing: 0.12 * 13,
                      color: _newWeekLinkColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Stats row
        Text(
          _buildStatsText(
            completedCount,
            l10n,
            Localizations.localeOf(context).languageCode,
          ),
          style: AppTextStyles.body.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),

        // Completed chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: plan.routines.map((routine) {
              final name = routineNames[routine.routineId] ?? l10n.routines;
              final isDone = routine.completedWorkoutId != null;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Opacity(
                  opacity: isDone ? 1.0 : 0.3,
                  child: RoutineChip(
                    sequenceNumber: routine.order,
                    routineName: name,
                    chipState: isDone
                        ? RoutineChipState.done
                        : RoutineChipState.remaining,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _buildStatsText(int sessions, AppLocalizations l10n, String locale) {
    final parts = <String>[l10n.sessionsCount(sessions)];

    if (totalVolume > 0) {
      final volumeStr = AppNumberFormat.compactVolume(
        totalVolume,
        locale: locale,
      );
      parts.add('$volumeStr $weightUnit');
    }

    if (prCount > 0) {
      parts.add(l10n.prsCount(prCount));
    }

    return parts.join('  ');
  }
}

/// A simple stats row widget that can be reused.
class WeekStatsChip extends StatelessWidget {
  const WeekStatsChip({
    required this.value,
    required this.label,
    this.valueColor,
    super.key,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(
        children: [
          // WeekStatsChip value — Rajdhani numeric (since the value is a
          // numerical chip stat).
          Text(
            value,
            style: AppTextStyles.numeric.copyWith(
              fontSize: 16,
              color: valueColor,
            ),
          ),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
