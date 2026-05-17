import 'package:flutter/material.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/core/theme/radii.dart';
import 'package:repsaga/l10n/app_localizations.dart';

/// Top-right pill on the Titles screen showing `{earned} / {total}` titles
/// with a localized suffix ("conquistados" / "earned").
///
/// Tabular figures (`FontFeature.tabularFigures`) keep digit columns stable
/// so the counter doesn't reflow as values change.
class TitlesCounterPill extends StatelessWidget {
  const TitlesCounterPill({
    super.key,
    required this.earnedCount,
    required this.totalCount,
  });

  final int earnedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'titles-counter-pill',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
        child: Text(
          l10n.titlesCounterPill(earnedCount, totalCount),
          style: AppTextStyles.label.copyWith(
            fontSize: 11,
            color: AppColors.textDim,
            letterSpacing: 0.08 * 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
