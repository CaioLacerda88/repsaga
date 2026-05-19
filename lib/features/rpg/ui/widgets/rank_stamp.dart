import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/vitality_state.dart';
// Pulled in for the `VitalityStateColor.borderColor` extension on
// VitalityState (rank-stamp border tint). Extension lives in ui/utils/
// post-BUG-035 so the model file stays Flutter-agnostic.
import '../utils/vitality_state_styles.dart';

/// Circular rank badge — Rajdhani 700 numeral on the elevated [surface2]
/// disc, with the border color driven by the body-part's [VitalityState].
///
/// The 22sp Rajdhani 700 is per the kickoff lock; tabular figures so the
/// digits don't shift width as the user ranks up. The state color flows
/// through a single border ring (no fill tint) — body-part rows already
/// communicate vitality via the rune sigil and hairline progress, so a
/// loud filled disc would compete.
class RankStamp extends StatelessWidget {
  const RankStamp({
    super.key,
    required this.rank,
    required this.vitalityState,
    this.size = 44,
  });

  final int rank;
  final VitalityState vitalityState;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: vitalityState.borderColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: const TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textCream,
          height: 1,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );
  }
}
