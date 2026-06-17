import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';

/// One cardio row of the S2 Mission Debrief ledger (Phase 38e).
///
/// Sibling of [LiftRow]: same row shell + geometry so a mixed strength +
/// cardio ledger reads coherent. Diverges only by:
///   * a TEAL ([AppColors.bodyPartCardio]) leading dot (vs the strength
///     body-part hue);
///   * the right-aligned value group renders the DURATION as the hero
///     numeral (Rajdhani-700 teal) where a [LiftRow] shows `kg × reps`,
///     followed by an optional dim distance/pace suffix.
///
/// **No PR, no heroGold.** Gold stays the strength-PR scarcity token; cardio
/// never borrows it.
///
/// **320dp guard.** The value group (`duration · distance · pace`) is wrapped
/// in a `FittedBox(scaleDown)` so the crowded all-segments case (long
/// duration like `1:02:30` + distance + pace) scales down instead of
/// overflowing on the narrowest frame — same guard `cardio_entry_card.dart`
/// uses. The duration hero never wraps; rows with fewer segments render at
/// full size.
///
/// **Decoupling Rule 2 (widget l10n parameterization).** All display strings
/// ([activityName], [durationLabel], [distanceSuffix], [paceSuffix]) are
/// passed in already-formatted; the widget never reads
/// `AppLocalizations.of(context)` or `CardioFormat` so it stays unit-testable
/// without an ARB harness.
class CardioEntryRow extends StatelessWidget {
  const CardioEntryRow({
    super.key,
    required this.activityName,
    required this.durationLabel,
    this.distanceSuffix,
    this.paceSuffix,
  });

  /// Pre-resolved exercise display name (already localized).
  final String activityName;

  /// Pre-formatted duration hero (e.g. `28:45`). Never wraps.
  final String durationLabel;

  /// Pre-formatted distance suffix (e.g. `5.2 km`), or null when not logged.
  final String? distanceSuffix;

  /// Pre-formatted pace suffix (e.g. `5:31/km`), or null when not derivable.
  final String? paceSuffix;

  @override
  Widget build(BuildContext context) {
    final suffixParts = <String>[?distanceSuffix, ?paceSuffix];

    return ConstrainedBox(
      // Min 32dp to match LiftRow; the activity name may wrap to 2 lines on
      // narrow viewports.
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Teal leading dot — the cardio identity cue.
          Container(
            key: const ValueKey('cardio-row-hue-dot'),
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.bodyPartCardio,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              activityName,
              style: AppTextStyles.body.copyWith(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Value group: duration hero + optional dim suffix. FittedBox
          // scaleDown shrinks the WHOLE group on the 320dp crowded case
          // rather than overflowing; no-op on 360/412dp.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    durationLabel,
                    style: AppTextStyles.numeric.copyWith(
                      fontSize: 16,
                      letterSpacing: -0.02 * 16,
                      color: AppColors.bodyPartCardio,
                    ),
                  ),
                  if (suffixParts.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· ${suffixParts.join(' · ')}',
                      style: AppTextStyles.numericSmall.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
