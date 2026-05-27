import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';

/// One row of the S2 Mission Debrief lift table (Phase 31 Pass 3).
///
/// Layout (360dp baseline):
///   * BP hue dot (8dp filled circle, left-anchored)
///   * 8dp gap
///   * Exercise name — Barlow 14sp textCream, fills available width,
///     single-line ellipsis (wraps to 2 lines on narrow viewports)
///   * Weight × reps numeric — Rajdhani 700 16sp -0.02em, right-aligned.
///     `heroGold` when [prLabel] != null (PR row); otherwise `textCream`.
///   * 6dp gap
///   * Optional "PR" flag — Rajdhani 700 11sp +0.04em heroGold, only when
///     [prLabel] is non-null.
///
/// **Default height: 32dp.** Grows to 48dp if the exercise name wraps to
/// 2 lines. Most pt-BR / en exercise names fit at 14sp on 360dp.
///
/// **Decoupling Rule 2 (widget l10n parameterization).** Localized strings
/// (PR flag, "kg" unit) are passed in as already-localized values. The
/// widget never reads `AppLocalizations.of(context)` so it stays
/// unit-testable without an ARB harness.
///
/// **`// ignore: reward_accent`** annotations are required on the two
/// heroGold call sites (PR weight-x-reps + PR flag). The mockup designates
/// PR as the canonical reward; gold here is the PR signal — exactly the
/// scarcity-token contract `AppColors.heroGold` is reserved for.
class LiftRow extends StatelessWidget {
  const LiftRow({
    super.key,
    required this.bodyPartHue,
    required this.exerciseName,
    required this.peakReps,
    required this.peakWeightKg,
    required this.prLabel,
    required this.weightUnitLabel,
  });

  /// Body-part identity hue for the leading dot. Resolved by the caller
  /// from `BodyPartHues.hueFor(bp)`.
  final Color bodyPartHue;

  /// Pre-resolved exercise display name (already localized).
  final String exerciseName;

  /// Best set's reps (integer; rendered verbatim).
  final int peakReps;

  /// Best set's weight in kg. Rendered with `toStringAsFixed(0)` so 92.5
  /// → "93" and 100.0 → "100". The mockup pins integer values for the
  /// debrief row register; precise sub-kg numerics live on the per-set
  /// detail screens.
  final double peakWeightKg;

  /// Pre-localized "PR" flag text, or `null` when the row is not a PR.
  /// Non-null toggles both the heroGold weight × reps tint AND the
  /// trailing "PR" pill.
  final String? prLabel;

  /// Pre-localized weight unit suffix, e.g. "kg" / "lb".
  final String weightUnitLabel;

  @override
  Widget build(BuildContext context) {
    final isPR = prLabel != null;
    final weightStyle = AppTextStyles.numeric.copyWith(
      fontSize: 16,
      letterSpacing: -0.02 * 16,
      // PR row paints weight × reps in heroGold. The scarcity contract is
      // met (PR-only render); typographic accent, not a reward burst.
      // ignore: reward_accent — PR is the canonical reward; heroGold scarcity contract met (PR row only).
      color: isPR ? AppColors.heroGold : AppColors.textCream,
    );
    final weightText =
        '${peakWeightKg.toStringAsFixed(0)}$weightUnitLabel × $peakReps';

    return ConstrainedBox(
      // Min 32dp; row grows to 48dp when the exercise name wraps to 2
      // lines (the Text widget's intrinsic height drives the Row above
      // the floor). Cap at 48dp to keep the table predictable.
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // BP hue dot — 8dp filled circle, left-anchored.
          Container(
            key: const ValueKey('lift-row-hue-dot'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: bodyPartHue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              exerciseName,
              style: AppTextStyles.body.copyWith(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(weightText, style: weightStyle),
          if (isPR) ...[
            const SizedBox(width: 6),
            Text(
              prLabel!,
              style: AppTextStyles.numeric.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.04 * 11,
                // PR flag is the explicit reward chrome — heroGold by
                // design. Same scarcity rationale as the weight tint.
                // ignore: reward_accent — PR is the canonical reward; heroGold scarcity contract met.
                color: AppColors.heroGold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
