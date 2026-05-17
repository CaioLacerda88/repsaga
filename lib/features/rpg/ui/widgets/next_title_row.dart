import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Progress row for the "Próximos" region of the Titles screen.
///
/// Body-part-hue dot, title name, tabular `current / threshold` figure,
/// a body-part-hue progress bar, and an ICU-plural sub-line
/// (`titlesNextSubBodyPart` / `titlesNextSubCharacter` and their `One`
/// singular variants). The whole row is tappable → opens the lore bottom
/// sheet.
///
/// **Progress bar shape (cluster_align_widthfactor_zerofill):** the fill
/// uses [FractionallySizedBox] inside a tight-constrained [ClipRRect]
/// container — NOT `Align(widthFactor:)` with a childless `ColoredBox`,
/// which collapses to 0×0 under loose constraints. Matches the proven
/// pattern in `body_part_rank_row.dart`.
///
/// **Semantics shape (cluster_semantics_identifier_pair_rule):** Semantics
/// wrapper directly on the InkWell with `container: true`,
/// `explicitChildNodes: true`, `button: onTap != null`, and the stable
/// `titles-next-row-<slug>` identifier so Flutter web's AOM forwards taps
/// to the gesture detector.
class NextTitleRow extends StatelessWidget {
  const NextTitleRow({
    super.key,
    required this.slug,
    required this.titleName,
    required this.accentColor,
    required this.currentValue,
    required this.thresholdValue,
    required this.bodyPartLabel,
    required this.isCharacterLevel,
    this.onTap,
  });

  /// Stable forever-key — drives the Semantics identifier
  /// `titles-next-row-<slug>`.
  final String slug;

  /// Localized display name of the title.
  final String titleName;

  /// Body-part hue for the left dot and progress bar fill. Caller resolves
  /// via `bodyPartColor[bp]` for body-part rows, or the character-level
  /// palette for `isCharacterLevel: true` rows.
  final Color accentColor;

  /// Current rank (body-part) or character level. Always < [thresholdValue]
  /// at the call site — already-earned titles are filtered out upstream.
  final int currentValue;

  /// Required rank or character level for this title.
  final int thresholdValue;

  /// Localized body-part name, or the localized "Personagem" / "Character"
  /// string when [isCharacterLevel] is true. Sub-line copy embeds this
  /// directly via the ICU placeholder.
  final String bodyPartLabel;

  /// Whether this row is the character-level next-title (true) or a
  /// per-body-part next-title (false). Drives sub-line copy selection
  /// between `titlesNextSubCharacter*` and `titlesNextSubBodyPart*`.
  final bool isCharacterLevel;

  /// Tap callback. Null disables the tap target (defensive — the screen
  /// always wires this to the lore bottom-sheet preview).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = thresholdValue - currentValue;
    final progress = thresholdValue <= 0
        ? 0.0
        : (currentValue / thresholdValue).clamp(0.0, 1.0);

    final String subLine;
    if (isCharacterLevel) {
      subLine = remaining == 1
          ? l10n.titlesNextSubCharacterOne
          : l10n.titlesNextSubCharacter(remaining);
    } else {
      subLine = remaining == 1
          ? l10n.titlesNextSubBodyPartOne(bodyPartLabel)
          : l10n.titlesNextSubBodyPart(bodyPartLabel, remaining);
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      identifier: 'titles-next-row-$slug',
      label: titleName,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                  Text(
                    '$currentValue / $thresholdValue',
                    style: AppTextStyles.label.copyWith(
                      fontSize: 12,
                      color: AppColors.textDim,
                      letterSpacing: 0.04 * 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // cluster_align_widthfactor_zerofill: FractionallySizedBox
              // inside a tight-constrained Container — never
              // `Align(widthFactor:)` with a childless ColoredBox, which
              // collapses to 0x0 under loose constraints.
              ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusSm),
                child: Container(
                  height: 4,
                  color: AppColors.xpTrack,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: accentColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subLine,
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
