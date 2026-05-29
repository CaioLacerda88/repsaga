import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Sticky week header sliver delegate for the History screen.
///
/// Renders a 52dp pinned strip on top of a `surface2` background carrying:
///   * the localized week label on the left at the section-header register
///     ([AppTextStyles.sectionHeader] = 13sp tracked Barlow Condensed),
///     deliberately stronger than chip/tab `[AppTextStyles.label]` so the
///     heading reads above the card titles rather than below them.
///   * a "N sets · +M XP" roll-up on the right — sets in default text
///     color, XP digits in `hotViolet` (daily-driver register; NOT the
///     reward-scarcity gold, which is reserved for PRs / level-ups via
///     `RewardAccent`).
///
/// **Height: 52dp** — one register up from the 48dp tap/input default so
/// the header has the depth of a section heading, not an input field.
///
/// **Elevation shadow on overlap:** when scrolling cards pass beneath the
/// sticky header, the delegate's `overlapsContent` flag flips true and the
/// header paints a soft `abyss`-tinted shadow so the rolling cards read as
/// clearly _behind_ the header instead of fighting it for the surface
/// level. The shadow is animated implicitly by `DecoratedBox` rebuilding
/// on the flag transition.
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
    this.overlapsContent = false,
    super.key,
  });

  /// Pre-localized week-label string (e.g. "Week of May 20", "Semana de
  /// 20 mai", or "This Week" / "Esta semana" for the current ISO week).
  /// The screen layer formats the date and supplies the final string
  /// through this constructor.
  final String weekLabel;

  /// Pre-localized "N sets" portion of the roll-up (e.g. "12 sets",
  /// "12 séries"). The XP portion is rendered separately so the digits
  /// can pick up [AppColors.hotViolet] while the separator stays in the
  /// default text color.
  final String rollupSetsLabel;

  /// XP total for the week. Rendered as `+{xpValue} XP` in hotViolet.
  final int xpValue;

  /// Whether cards are currently scrolling underneath this sticky header.
  /// When true the header paints a soft drop-shadow to disambiguate
  /// elevation. Forwarded from the host `SliverPersistentHeaderDelegate`.
  final bool overlapsContent;

  /// Fixed extent. Co-located with the delegate so the widget and its
  /// host agree on the rendered height. See class doc for the 52dp
  /// rationale (section-heading register, one tier above 48dp inputs).
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'history-week-header',
      label: '$weekLabel · $rollupSetsLabel · +$xpValue XP',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          boxShadow: overlapsContent
              ? [
                  BoxShadow(
                    color: AppColors.abyss.withValues(alpha: 0.6),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    weekLabel,
                    style: AppTextStyles.sectionHeader.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.95,
                      ),
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
                    color: AppColors.hotViolet.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `SliverPersistentHeaderDelegate` that hosts a [HistoryWeekHeader] at a
/// fixed 52dp extent.
///
/// Min == max means the header neither shrinks on scroll nor over-renders
/// when overscrolled — it just stays pinned. The delegate forwards
/// `overlapsContent` into the header so the depth shadow can animate as
/// cards begin to slide beneath the pinned strip.
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
  double get minExtent => HistoryWeekHeader.height;

  @override
  double get maxExtent => HistoryWeekHeader.height;

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
      overlapsContent: overlapsContent,
    );
  }

  @override
  bool shouldRebuild(covariant WeekHeaderDelegate oldDelegate) {
    return weekLabel != oldDelegate.weekLabel ||
        rollupSetsLabel != oldDelegate.rollupSetsLabel ||
        xpValue != oldDelegate.xpValue;
  }
}
