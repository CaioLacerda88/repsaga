import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../utils/vitality_state_styles.dart';
import 'body_part_localization.dart';

/// Legend for [VitalityTrendChart] — one chip per active body part, each a
/// small body-part-tinted swatch + the localized track name (Phase 38e-bis).
///
/// The chart itself only ever draws ONE vivid line (the selected body part) +
/// six ghost lines, so without a legend the cardio line's teal can't be
/// distinguished from the ghosted strength lines by color alone. This legend
/// closes that gap: the 7th chip reads as **cardio in teal**, matching the
/// 7th teal trend line, so "the bright teal sawtooth is my conditioning" is
/// legible.
///
/// Cardio's swatch + label use the cardio identity teal
/// ([AppColors.bodyPartCardio]); the six strength chips use their
/// [VitalityStateStyles.bodyPartColor] identity hue. Order follows
/// [activeBodyParts] so cardio sits last, mirroring the rail + table.
class VitalityTrendChartLegend extends StatelessWidget {
  const VitalityTrendChartLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'vitality-trend-legend',
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          for (final bp in activeBodyParts)
            _LegendChip(
              color: VitalityStateStyles.bodyPartColor[bp] ?? AppColors.textDim,
              // Cardio reads as "Conditioning" (the track/stat name), not the
              // "Cardio" muscle-group label — same string the rail + table
              // cardio cell use. Strength chips use their muscle-group names.
              label: bp == BodyPart.cardio
                  ? l10n.cardioTrackLabel
                  : localizedBodyPartName(bp, l10n),
            ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: AppTextStyles.label.copyWith(
            fontSize: 9.5,
            letterSpacing: 0.8,
            color: AppColors.textDim,
          ),
        ),
      ],
    );
  }
}
