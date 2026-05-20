import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_muscle_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// "Coming in v2" cardio row.
///
/// Visually distinct from the six active body-part rows: rendered against
/// the [surface] tint, sigil at 30% opacity, label + subtitle in [textDim].
/// No rank stamp, no hairline — there is no progression here yet, so the
/// UI doesn't pretend there is.
///
/// The kickoff lock keeps cardio in the schema (`BodyPart.cardio`) but out
/// of `activeBodyParts`. This row exists so the user sees the path is
/// known but still asleep — communicates "we're aware of cardio, it's not
/// abandoned, just not active yet."
class DormantCardioRow extends StatelessWidget {
  const DormantCardioRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.4),
        border: const Border(
          top: BorderSide(color: AppColors.hair),
          bottom: BorderSide(color: AppColors.hair),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Opacity(
            opacity: 0.3,
            child: AppIcons.render(
              AppMuscleIcons.cardio,
              color: AppColors.textDim,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Cardio body-part label sits in the same slot as
                  // the six trained body-part labels on the rank rail
                  // (e.g. "CHEST", "BACK") which all use
                  // [AppTextStyles.label] UPPERCASE. Aligning the
                  // cardio row to the same register removes a typeface
                  // inconsistency in the rank-rail family.
                  l10n.muscleGroupCardio.toUpperCase(),
                  style: AppTextStyles.label.copyWith(color: AppColors.textDim),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.dormantCardioCopy,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
