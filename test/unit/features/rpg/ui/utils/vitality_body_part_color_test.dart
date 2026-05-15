import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';

void main() {
  group(
    'VitalityStateStyles.bodyPartColor — chest and back use identity tokens',
    () {
      test('chest maps to bodyPartChest', () {
        expect(
          VitalityStateStyles.bodyPartColor[BodyPart.chest],
          AppColors.bodyPartChest,
        );
      });

      test('back maps to bodyPartBack', () {
        expect(
          VitalityStateStyles.bodyPartColor[BodyPart.back],
          AppColors.bodyPartBack,
        );
      });

      // Regression: the other entries should still match their existing
      // tokens. If a later sub-phase rebinds legs/shoulders/arms/core,
      // these expectations get updated then — not now.
      test('legs still maps to success', () {
        expect(
          VitalityStateStyles.bodyPartColor[BodyPart.legs],
          AppColors.success,
        );
      });

      test('shoulders still maps to warning', () {
        expect(
          VitalityStateStyles.bodyPartColor[BodyPart.shoulders],
          AppColors.warning,
        );
      });

      test('arms still maps to error', () {
        expect(
          VitalityStateStyles.bodyPartColor[BodyPart.arms],
          AppColors.error,
        );
      });
    },
  );
}
