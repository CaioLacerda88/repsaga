import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/muscle_group_body_part.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

void main() {
  group('muscleGroupToBodyPart (cross-feature mapping)', () {
    test('chest maps to BodyPart.chest', () {
      expect(muscleGroupToBodyPart(MuscleGroup.chest), BodyPart.chest);
    });

    test('back maps to BodyPart.back', () {
      expect(muscleGroupToBodyPart(MuscleGroup.back), BodyPart.back);
    });

    test('legs maps to BodyPart.legs', () {
      expect(muscleGroupToBodyPart(MuscleGroup.legs), BodyPart.legs);
    });

    test('shoulders maps to BodyPart.shoulders', () {
      expect(muscleGroupToBodyPart(MuscleGroup.shoulders), BodyPart.shoulders);
    });

    test('arms maps to BodyPart.arms', () {
      expect(muscleGroupToBodyPart(MuscleGroup.arms), BodyPart.arms);
    });

    test('core maps to BodyPart.core', () {
      expect(muscleGroupToBodyPart(MuscleGroup.core), BodyPart.core);
    });

    test('cardio returns null (no v1 identity hue)', () {
      // cardio has a token (AppColors.bodyPartCardio) but is
      // infrastructure-only for v1 — UI surfaces fall back to neutral.
      expect(muscleGroupToBodyPart(MuscleGroup.cardio), isNull);
    });
  });

  group('MuscleGroupBodyPart.toBodyPart (extension)', () {
    test('delegates to muscleGroupToBodyPart for every value', () {
      for (final group in MuscleGroup.values) {
        expect(group.toBodyPart(), muscleGroupToBodyPart(group));
      }
    });
  });
}
