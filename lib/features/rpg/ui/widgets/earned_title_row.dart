import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Single-row widget for the "Conquistados" region of the Titles screen.
///
/// Earned-but-not-equipped title with a body-part-hue dot, the title name,
/// the body-part·threshold meta line, and an "Equipar" / "Equip" CTA. The
/// whole row is tappable — tap-on-row opens the lore bottom sheet, while
/// tap-on-CTA fires [onEquip] without bubbling to [onTap]. The dual-target
/// shape mirrors the mockup at `docs/phase-26-mockups.html#titles`.
///
/// **Semantics shape (`cluster_semantics_identifier_pair_rule`):** the
/// Semantics wrapper carries `container: true`, `explicitChildNodes: true`,
/// and `button: onTap != null` so Flutter web's AOM exposes the row as a
/// single role=button tap target with a stable `titles-earned-row-<slug>`
/// identifier. The wrapper goes directly on the [InkWell] (the actual
/// gesture detector) — putting it on a parent layer causes the proven-broken
/// AOM dispatch surface from the `body_part_rank_row` series.
class EarnedTitleRow extends StatelessWidget {
  const EarnedTitleRow({
    super.key,
    required this.slug,
    required this.titleName,
    required this.bodyPartLabel,
    required this.thresholdLabel,
    required this.accentColor,
    this.onTap,
    this.onEquip,
  });

  /// Stable forever-key — drives the Semantics identifier
  /// `titles-earned-row-<slug>` so E2E selectors stay aligned across copy
  /// revisions.
  final String slug;

  /// Localized display name of the title.
  final String titleName;

  /// Localized body-part name. Character-level titles pass the localized
  /// "Personagem" / "Character" string instead.
  final String bodyPartLabel;

  /// Threshold label — `"Rank 5"` / `"Nível 10"` per title kind. The caller
  /// localizes via `titlesRowRankThreshold` / `titlesRowCharacterLevel`.
  final String thresholdLabel;

  /// Body-part hue for the left dot. Caller resolves the token via
  /// `bodyPartColor[bp]` (Phase 26a).
  final Color accentColor;

  /// Tap callback for the row body. Null disables the tap target.
  final VoidCallback? onTap;

  /// Tap callback for the "Equipar" CTA. Null disables the CTA but leaves
  /// the row tap target active (defensive — the equip mutation can be
  /// disabled while lore preview stays available).
  final VoidCallback? onEquip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      identifier: 'titles-earned-row-$slug',
      label: titleName,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleName,
                      style: AppTextStyles.headline.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textCream,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$bodyPartLabel · $thresholdLabel',
                      style: AppTextStyles.label.copyWith(
                        fontSize: 11,
                        color: AppColors.textDim,
                        letterSpacing: 0.08 * 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onEquip,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.hotViolet,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.titlesRowEquipCta,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 12,
                    color: AppColors.hotViolet,
                    letterSpacing: 0.10 * 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
