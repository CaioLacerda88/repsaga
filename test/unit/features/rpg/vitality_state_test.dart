import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/vitality_state.dart';
// Pulled in for the `VitalityStateColor.borderColor` extension that
// covers the legacy `state.borderColor` shape — extension lives here
// post-BUG-035 so models/vitality_state.dart stays Flutter-agnostic.
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';

/// Compatibility-shim test for `VitalityStateX.fromVitality`. The real
/// boundary contract lives in `vitality_state_mapper_test.dart`; this file
/// confirms the shim still routes (ewma, peak) → mapper correctly so
/// existing call sites (character_sheet_state, character_sheet_provider,
/// body_part_rank_row test factory) keep working.
void main() {
  group('VitalityStateX.fromVitality (shim)', () {
    test('peak == 0 collapses to untested regardless of EWMA', () {
      // 2026-05-04 untested patch: peak == 0 is the never-trained branch
      // (ratio undefined). The shim must route through to the mapper which
      // returns the new dedicated state.
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 0, vitalityPeak: 0),
        VitalityState.untested,
      );
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 50, vitalityPeak: 0),
        VitalityState.untested,
      );
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 100, vitalityPeak: 0),
        VitalityState.untested,
      );
    });

    test('ewma == 0 with peak > 0 collapses to dormant', () {
      // pct = 0/peak = 0 → dormant per spec §8.4 boundary inclusivity.
      // Regression pin for the untested patch — the peak > 0 case must
      // remain dormant (genuinely decayed), not bleed into untested.
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 0, vitalityPeak: 100),
        VitalityState.dormant,
      );
    });

    test('1..30% of peak maps to fading', () {
      // pct = 1/100 = 0.01 → fading
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 1, vitalityPeak: 100),
        VitalityState.fading,
      );
      // pct = 30/100 = 0.30 → fading (right edge inclusive)
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 30, vitalityPeak: 100),
        VitalityState.fading,
      );
    });

    test('30+ε..70% maps to active', () {
      // pct = 31/100 = 0.31 → active
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 31, vitalityPeak: 100),
        VitalityState.active,
      );
      // pct = 70/100 = 0.70 → active (right edge inclusive)
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 70, vitalityPeak: 100),
        VitalityState.active,
      );
    });

    test('70+ε..100% maps to radiant', () {
      // pct = 71/100 = 0.71 → radiant
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 71, vitalityPeak: 100),
        VitalityState.radiant,
      );
      // pct = 100/100 = 1.00 → radiant
      expect(
        VitalityStateX.fromVitality(vitalityEwma: 100, vitalityPeak: 100),
        VitalityState.radiant,
      );
    });

    test(
      'large EWMA values normalised against larger peak (real-world scale)',
      () {
        // Spec §13.3 example: chest EWMA 8420, peak 9850 → pct 0.855 → radiant.
        expect(
          VitalityStateX.fromVitality(vitalityEwma: 8420, vitalityPeak: 9850),
          VitalityState.radiant,
        );
        // Half of peak → active.
        expect(
          VitalityStateX.fromVitality(vitalityEwma: 4925, vitalityPeak: 9850),
          VitalityState.active,
        );
        // 20% of peak → fading.
        expect(
          VitalityStateX.fromVitality(vitalityEwma: 1970, vitalityPeak: 9850),
          VitalityState.fading,
        );
      },
    );

    test('borderColor maps to the canonical AppColors palette per state', () {
      // Untested intentionally shares the dormant dim/grey token —
      // reward-scarcity contract preserves heroGold for radiant only.
      expect(VitalityState.untested.borderColor, AppColors.textDim);
      expect(VitalityState.dormant.borderColor, AppColors.textDim);
      expect(VitalityState.fading.borderColor, AppColors.primaryViolet);
      expect(VitalityState.active.borderColor, AppColors.hotViolet);
      expect(VitalityState.radiant.borderColor, AppColors.heroGold);
    });
  });
}
