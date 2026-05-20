import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../domain/weekly_engagement.dart';
import 'muscle_bar_row.dart';

/// 6-bar muscle-volume section in the plan editor.
///
/// Renders bars in canonical body-part order (chest, back, legs, shoulders,
/// arms, core). Cardio is intentionally excluded (v1).
///
/// The header has NO total counter: compound-attribution + tie-counting
/// would double-count sets when an exercise hits multiple body parts, so
/// the 6 bars are the truthful surface and any single "X / Y" header total
/// would mislead.
///
/// Body-part dot color resolves through [VitalityStateStyles.bodyPartColor]
/// (same precedent as `body_part_rank_row.dart`), falling back to
/// [AppColors.textDim] if the map is missing a key.
///
/// `headerLabel`, `infoIconSemanticsLabel`, `legendDoneLabel`, and
/// `legendPlannedLabel` are passed in from the screen layer because the
/// underlying l10n keys land in a later phase-26e task. Once those keys
/// exist, the screen wires them via `AppLocalizations.of(context).<key>`.
class EngajamentoSection extends StatelessWidget {
  const EngajamentoSection({
    super.key,
    required this.engagement,
    required this.headerLabel,
    required this.infoIconSemanticsLabel,
    required this.legendDoneLabel,
    required this.legendPlannedLabel,
    required this.onInfoTap,
  });

  final WeeklyEngagement engagement;
  final String headerLabel;
  final String infoIconSemanticsLabel;
  final String legendDoneLabel;
  final String legendPlannedLabel;
  final VoidCallback onInfoTap;

  static const _orderedBodyParts = <BodyPart>[
    BodyPart.chest,
    BodyPart.back,
    BodyPart.legs,
    BodyPart.shoulders,
    BodyPart.arms,
    BodyPart.core,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Shared max-scale: largest planned value across all 6 bars, so every
    // bar uses a consistent x-axis. Falls back to 1 so empty plans render
    // sane (zero-width) fills instead of NaN.
    var maxScale = 1;
    for (final bp in _orderedBodyParts) {
      final planned = engagement.plannedFor(bp);
      if (planned > maxScale) maxScale = planned;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hairline above section.
        const Divider(height: 1, color: AppColors.hair),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                headerLabel,
                style: AppTextStyles.title.copyWith(
                  fontSize: 14,
                  color: AppColors.textCream,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              // Per cluster_semantics_identifier_pair_rule:
              // container + explicitChildNodes + button + identifier on
              // the actual tap target (the IconButton).
              Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                identifier: 'engagement-info-icon',
                label: infoIconSemanticsLabel,
                child: IconButton(
                  key: const ValueKey('engagement-info-icon'),
                  icon: const Icon(Icons.info_outline, size: 16),
                  color: AppColors.textDim,
                  visualDensity: VisualDensity.compact,
                  onPressed: onInfoTap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final bp in _orderedBodyParts)
                MuscleBarRow(
                  name: _localizedName(bp, l10n),
                  bodyPartColor:
                      VitalityStateStyles.bodyPartColor[bp] ??
                      AppColors.textDim,
                  doneSets: engagement.doneFor(bp),
                  plannedSets: engagement.plannedFor(bp),
                  maxScale: maxScale,
                ),
              const SizedBox(height: 8),
              _Legend(
                doneLabel: legendDoneLabel,
                plannedLabel: legendPlannedLabel,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _localizedName(BodyPart bp, AppLocalizations l10n) {
    switch (bp) {
      case BodyPart.chest:
        return l10n.muscleGroupChest;
      case BodyPart.back:
        return l10n.muscleGroupBack;
      case BodyPart.legs:
        return l10n.muscleGroupLegs;
      case BodyPart.shoulders:
        return l10n.muscleGroupShoulders;
      case BodyPart.arms:
        return l10n.muscleGroupArms;
      case BodyPart.core:
        return l10n.muscleGroupCore;
      case BodyPart.cardio:
        // Unreachable — cardio filtered out of [_orderedBodyParts].
        return '';
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.doneLabel, required this.plannedLabel});

  final String doneLabel;
  final String plannedLabel;

  @override
  Widget build(BuildContext context) {
    final dim = AppTextStyles.label.copyWith(
      fontSize: 10,
      letterSpacing: 0.12 * 10,
      color: AppColors.textDim,
    );

    Widget swatch(double opacity) => Container(
      width: 10,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.hotViolet.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(2),
      ),
    );

    return Row(
      children: [
        swatch(1.0),
        const SizedBox(width: 4),
        Text(doneLabel, style: dim),
        const SizedBox(width: 12),
        swatch(0.4),
        const SizedBox(width: 4),
        Text(plannedLabel, style: dim),
      ],
    );
  }
}
