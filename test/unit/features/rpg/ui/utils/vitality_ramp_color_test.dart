import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';

void main() {
  group('VitalityStateStyles.vitalityRampColorFor', () {
    test('returns vitalityHigh at 100% (exact upper bound)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(1.0),
        AppColors.vitalityHigh,
      );
    });

    test('returns vitalityHigh at 66% (high-band lower edge, inclusive)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.66),
        AppColors.vitalityHigh,
      );
    });

    test('returns vitalityMid at 65% (just below high-band cutoff)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.65),
        AppColors.vitalityMid,
      );
    });

    test('returns vitalityMid at 34% (mid-band lower edge, inclusive)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.34),
        AppColors.vitalityMid,
      );
    });

    test('returns vitalityLow at 33% (just below mid-band cutoff)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.33),
        AppColors.vitalityLow,
      );
    });

    test('returns vitalityLow at 0% (lower bound)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.0),
        AppColors.vitalityLow,
      );
    });

    test('returns textDim for null (untested state)', () {
      expect(VitalityStateStyles.vitalityRampColorFor(null), AppColors.textDim);
    });

    test('returns textDim for negative values (defensive)', () {
      // Defensive guard: vitality % should never be negative, but if a
      // bug produces one, fall back to the untested band rather than
      // returning the lower-band color (which would mislead the user
      // into thinking they have low conditioning when really the data
      // is malformed).
      expect(VitalityStateStyles.vitalityRampColorFor(-0.1), AppColors.textDim);
    });

    test('returns textDim for values above 1.0 (defensive)', () {
      expect(VitalityStateStyles.vitalityRampColorFor(1.5), AppColors.textDim);
    });

    test('returns vitalityHigh at 0.83 (interior of high band)', () {
      // Smoke for the interior of the high band so future readers
      // see the band's coverage is not only its boundary values.
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.83),
        AppColors.vitalityHigh,
      );
    });

    test('returns vitalityMid at 0.50 (interior of mid band)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.50),
        AppColors.vitalityMid,
      );
    });

    test('returns vitalityLow at 0.17 (interior of low band)', () {
      expect(
        VitalityStateStyles.vitalityRampColorFor(0.17),
        AppColors.vitalityLow,
      );
    });
  });
}
