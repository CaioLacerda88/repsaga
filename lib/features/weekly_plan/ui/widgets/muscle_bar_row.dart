import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// One row in the Engajamento section.
///
/// Layout (horizontal, ~22dp):
///   [6dp dot] [UPPERCASE 10sp name] [4dp stacked track ──────] [X / Y]
///
/// Track has two stacked fills on the same 4dp height:
///   * planned-fill: bodyPartColor at 40% opacity, width = plannedSets/maxScale
///   * done-fill:    bodyPartColor at 100% opacity, width = doneSets/maxScale
///
/// `maxScale` is the largest plannedSets value across all 6 bars (or 1 if
/// all are zero) — passed in by the parent so every bar shares the same
/// x-axis.
class MuscleBarRow extends StatelessWidget {
  const MuscleBarRow({
    super.key,
    required this.name,
    required this.bodyPartColor,
    required this.doneSets,
    required this.plannedSets,
    required this.maxScale,
  });

  final String name;
  final Color bodyPartColor;
  final int doneSets;
  final int plannedSets;
  final int maxScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final donePct = maxScale > 0 ? doneSets / maxScale : 0.0;
    final plannedPct = maxScale > 0 ? plannedSets / maxScale : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bodyPartColor,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            // 72dp is the smallest width that fits "SHOULDERS" (the longest
            // body-part name in EN) at 10sp / Inter 600 / letterSpacing 0.5
            // without the AOM ellipsis kicking in. Verified during Phase 26e
            // visual verification at 320 / 360 / 412dp viewports.
            width: 72,
            child: Text(
              name.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: AppColors.textDim,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  // Track background (low-contrast).
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.xpTrack,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Planned fill (40% opacity).
                  // FractionallySizedBox per cluster_align_widthfactor_zerofill —
                  // Align(widthFactor:, childless ColoredBox) collapses to 0×0
                  // under loose constraints.
                  FractionallySizedBox(
                    widthFactor: plannedPct.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bodyPartColor.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Done fill (100% opacity) overlays the planned fill —
                  // done is always a subset of planned, so the stack ordering
                  // is correct.
                  FractionallySizedBox(
                    widthFactor: donePct.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: bodyPartColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              '$doneSets / $plannedSets',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textCream,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
