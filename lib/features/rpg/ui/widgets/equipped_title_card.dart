import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Single-row card for the "Equipado" region of the Titles screen.
///
/// heroGold gradient surface (12% → 4% alpha) with a 40%-alpha heroGold
/// border, a body-part-hue dot on the left, title name + body-part·threshold
/// meta in the body, and a localized "Em uso" / "Active" tag on the right.
/// The whole row is a tap target — the screen wires [onTap] to the lore
/// bottom-sheet preview.
///
/// This widget is one of the few legitimate readers of [AppColors.heroGold]
/// outside `RewardAccent`. The path is whitelisted in
/// `scripts/check_reward_accent.sh` AND each heroGold read carries an inline
/// `// ignore: reward_accent — <reason>` marker so a future scope-tightening
/// of the whitelist doesn't silently drop the exception.
class EquippedTitleCard extends StatelessWidget {
  const EquippedTitleCard({
    super.key,
    required this.titleName,
    required this.bodyPartLabel,
    required this.thresholdLabel,
    required this.accentColor,
    this.onTap,
  });

  /// Localized display name of the title.
  final String titleName;

  /// Localized body-part name (e.g. "Costas" / "Back"). Character-level
  /// titles pass the localized "Personagem" / "Character" string instead.
  final String bodyPartLabel;

  /// Threshold label — `"Rank 5"` / `"Nível 10"` per title kind. The caller
  /// localizes this via `titlesRowRankThreshold` /
  /// `titlesRowCharacterLevel`.
  final String thresholdLabel;

  /// Body-part hue for the left dot. Caller resolves the token via
  /// `bodyPartColor[bp]` (Phase 26a).
  final Color accentColor;

  /// Tap callback. Null disables the tap target (defensive — the screen
  /// always wires this to the lore bottom-sheet preview).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      identifier: 'titles-equipped-card',
      label: titleName,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                // ignore: reward_accent — 26d equipped-card heroGold gradient
                AppColors.heroGold.withValues(alpha: 0.12),
                // ignore: reward_accent — 26d equipped-card heroGold gradient
                AppColors.heroGold.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border.all(
              // ignore: reward_accent — 26d equipped-card heroGold border
              color: AppColors.heroGold.withValues(alpha: 0.4),
            ),
          ),
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
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  // ignore: reward_accent — 26d equipped-card heroGold tag bg
                  color: AppColors.heroGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.titlesEquippedTag,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 11,
                    // ignore: reward_accent — 26d equipped-card heroGold tag text
                    color: AppColors.heroGold,
                    letterSpacing: 0.12 * 11,
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
