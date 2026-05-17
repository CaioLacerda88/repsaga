import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/cross_build_title_evaluator.dart';
import '../../models/body_part.dart';

/// heroGold-accented "Especial" card for the "Próximos" region of the
/// Titles screen.
///
/// Surfaces a cross-build title whose every condition is within 1 rank of
/// its floor. Renders a per-condition row for each [CrossBuildStat] — met
/// conditions show a heroGold check icon; unmet conditions render a
/// body-part-hue progress bar (`current / floor`). The bottleneck sub-line
/// `◆ Falta 1 rank em <bodyPart>` calls out the user's shortest path to
/// unlock.
///
/// This widget is one of the few legitimate readers of [AppColors.heroGold]
/// outside `RewardAccent`. The path is whitelisted in
/// `scripts/check_reward_accent.sh` AND each heroGold read carries an
/// inline `// ignore: reward_accent — <reason>` marker so a future
/// scope-tightening of the whitelist doesn't silently drop the exception.
///
/// **Progress bar shape (cluster_align_widthfactor_zerofill):** the fill
/// uses [FractionallySizedBox] inside a tight-constrained [ClipRRect]
/// container — never `Align(widthFactor:)` with a childless `ColoredBox`,
/// which collapses to 0x0 under loose constraints.
///
/// **Semantics shape (cluster_semantics_identifier_pair_rule):** Semantics
/// wrapper directly on the InkWell with `container: true`,
/// `explicitChildNodes: true`, `button: onTap != null`, and the stable
/// `titles-cross-build-card-<slug>` identifier so Flutter web's AOM
/// forwards taps to the gesture detector.
class CrossBuildCard extends StatelessWidget {
  const CrossBuildCard({
    super.key,
    required this.slug,
    required this.titleName,
    required this.stats,
    required this.bottleneckBodyPart,
    required this.bottleneckLabel,
    required this.statColors,
    required this.statLabels,
    this.onTap,
  });

  /// Stable forever-key — drives the Semantics identifier
  /// `titles-cross-build-card-<slug>`.
  final String slug;

  /// Localized display name of the title.
  final String titleName;

  /// (body-part, current, floor) tuples for the per-condition rows.
  /// Sourced from `crossBuildStatsFor(slug, ranks)`.
  final List<CrossBuildStat> stats;

  /// The body part the bottleneck sub-line calls out. The screen resolves
  /// this via `crossBuildStatsFor`'s ordering rule (smallest positive gap).
  final BodyPart bottleneckBodyPart;

  /// Localized body-part name for the bottleneck sub-line — embedded
  /// directly into `titlesCrossBuildBottleneck(bodyPartLabel)`.
  final String bottleneckLabel;

  /// Body-part hue per stat row dot + progress bar fill. The screen
  /// resolves via `VitalityStateStyles.bodyPartColor[bp]`.
  final Map<BodyPart, Color> statColors;

  /// Localized body-part name per stat row (for the row's accessibility
  /// label and visual chip). Caller localizes via
  /// `localizedBodyPartName(bp, l10n)`.
  final Map<BodyPart, String> statLabels;

  /// Tap callback. Null disables the tap target.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      identifier: 'titles-cross-build-card-$slug',
      label: titleName,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border.all(
              // ignore: reward_accent — 26d cross-build card heroGold border
              color: AppColors.heroGold.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      titleName,
                      style: AppTextStyles.headline.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textCream,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      // ignore: reward_accent — 26d cross-build ESPECIAL badge bg
                      color: AppColors.heroGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.titlesCrossBuildEspecial,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 10,
                        // ignore: reward_accent — 26d cross-build ESPECIAL text
                        color: AppColors.heroGold,
                        letterSpacing: 0.12 * 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final stat in stats) ...[
                _ConditionRow(
                  stat: stat,
                  accent: statColors[stat.bodyPart] ?? AppColors.textDim,
                  label: statLabels[stat.bodyPart] ?? '',
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 2),
              Text(
                l10n.titlesCrossBuildBottleneck(bottleneckLabel),
                style: AppTextStyles.label.copyWith(
                  fontSize: 11,
                  color: AppColors.textDim,
                  letterSpacing: 0.08 * 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One condition row inside a [CrossBuildCard].
///
/// Met conditions ([CrossBuildStat.isCleared]) render a heroGold check
/// icon on the right; unmet conditions render a body-part-hue
/// [FractionallySizedBox] progress bar (current / floor) plus the tabular
/// figure. Both shapes share the same body-part-hue dot + label layout on
/// the left so the rows align visually across the card.
class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.stat,
    required this.accent,
    required this.label,
  });

  final CrossBuildStat stat;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isCleared = stat.isCleared;
    final progress = stat.floor <= 0
        ? 1.0
        : (stat.current / stat.floor).clamp(0.0, 1.0);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
              letterSpacing: 0.08 * 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: isCleared
              ? const SizedBox.shrink()
              // cluster_align_widthfactor_zerofill: FractionallySizedBox
              // inside a tight-constrained Container — never
              // `Align(widthFactor:)` with a childless ColoredBox.
              : ClipRRect(
                  borderRadius: BorderRadius.circular(kRadiusSm),
                  child: Container(
                    height: 4,
                    color: AppColors.xpTrack,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: accent),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        if (isCleared)
          const Icon(
            Icons.check,
            // ignore: reward_accent — 26d cross-build met-condition check
            color: AppColors.heroGold,
            size: 14,
          )
        else
          Text(
            '${stat.current} / ${stat.floor}',
            style: AppTextStyles.label.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
              letterSpacing: 0.04 * 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
