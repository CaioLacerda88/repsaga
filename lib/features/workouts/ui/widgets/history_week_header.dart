import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Sticky week header sliver delegate for the History screen.
///
/// Renders a 48dp pinned strip on top of a `surface2` background carrying:
///   * the localized week label on the left (Barlow Condensed tracked
///     micro-copy via [AppTextStyles.label]),
///   * a "N sets · M XP" roll-up on the right with the XP digits in
///     [AppColors.heroGold] ([AppTextStyles.numericSmall]).
///
/// Localization happens at the screen layer (per
/// `feedback_widget_l10n_parameterization`): the widget receives the
/// final, already-localized strings as constructor parameters so unit
/// tests don't need to assemble an `AppLocalizations` harness.
///
/// Pair with [WeekHeaderDelegate] inside a
/// `SliverPersistentHeader(pinned: true, …)`.
class HistoryWeekHeader extends StatelessWidget {
  const HistoryWeekHeader({
    required this.weekLabel,
    required this.rollupSetsLabel,
    required this.xpValue,
    super.key,
  });

  /// Pre-localized week-label string (e.g. "Week of May 20", "Semana de
  /// 20 mai"). The screen layer formats the date and supplies the final
  /// string through this constructor.
  final String weekLabel;

  /// Pre-localized "N sets" portion of the roll-up (e.g. "12 sets",
  /// "12 séries"). The XP portion is rendered separately so the digits
  /// can pick up [AppColors.heroGold] while the separator stays in the
  /// default text color.
  final String rollupSetsLabel;

  /// XP total for the week. Rendered as `+{xpValue} XP` in heroGold.
  final int xpValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'history-week-header',
      label: '$weekLabel · $rollupSetsLabel · +$xpValue XP',
      child: Container(
        height: 48,
        color: AppColors.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                weekLabel,
                style: AppTextStyles.label.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              rollupSetsLabel,
              style: AppTextStyles.numericSmall.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '·',
              style: AppTextStyles.numericSmall.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '+$xpValue XP',
              style: AppTextStyles.numericSmall.copyWith(
                color: AppColors.heroGold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `SliverPersistentHeaderDelegate` that hosts a [HistoryWeekHeader] at a
/// fixed 48dp extent.
///
/// Min == max means the header neither shrinks on scroll nor over-renders
/// when overscrolled — it just stays pinned.
class WeekHeaderDelegate extends SliverPersistentHeaderDelegate {
  const WeekHeaderDelegate({
    required this.weekLabel,
    required this.rollupSetsLabel,
    required this.xpValue,
  });

  final String weekLabel;
  final String rollupSetsLabel;
  final int xpValue;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return HistoryWeekHeader(
      weekLabel: weekLabel,
      rollupSetsLabel: rollupSetsLabel,
      xpValue: xpValue,
    );
  }

  @override
  bool shouldRebuild(covariant WeekHeaderDelegate oldDelegate) {
    return weekLabel != oldDelegate.weekLabel ||
        rollupSetsLabel != oldDelegate.rollupSetsLabel ||
        xpValue != oldDelegate.xpValue;
  }
}
