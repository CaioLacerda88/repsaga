import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/encouragement_nudge_priority.dart';

void main() {
  group('selectNudge priority', () {
    test(
      'returns NudgeCrossBuildClose when crossBuildClose is set (highest priority)',
      () {
        final nudge = selectNudge(
          crossBuildClose: 'Forja Tripla',
          bodyPartTitleClose: (
            bodyPart: BodyPart.chest,
            titleName: 'Peitoral de Aço',
          ),
          remainingBucketWorkouts: 2,
          streakDays: 5,
        );

        expect(nudge, isA<NudgeCrossBuildClose>());
        expect(
          (nudge as NudgeCrossBuildClose).titleName,
          equals('Forja Tripla'),
        );
      },
    );

    test(
      'falls through to NudgeBodyPartTitleClose when crossBuildClose is null',
      () {
        final nudge = selectNudge(
          crossBuildClose: null,
          bodyPartTitleClose: (
            bodyPart: BodyPart.chest,
            titleName: 'Peitoral de Aço',
          ),
          remainingBucketWorkouts: 3,
          streakDays: 2,
        );

        expect(nudge, isA<NudgeBodyPartTitleClose>());
        final bp = nudge as NudgeBodyPartTitleClose;
        expect(bp.bodyPart, equals(BodyPart.chest));
        expect(bp.titleName, equals('Peitoral de Aço'));
      },
    );

    test(
      'falls through to NudgeRemainingWorkouts when both title fields are null',
      () {
        final nudge = selectNudge(
          crossBuildClose: null,
          bodyPartTitleClose: null,
          remainingBucketWorkouts: 3,
          streakDays: 4,
        );

        expect(nudge, isA<NudgeRemainingWorkouts>());
        expect((nudge as NudgeRemainingWorkouts).count, equals(3));
      },
    );

    test('falls through to NudgeStreak when remaining is 0', () {
      final nudge = selectNudge(
        crossBuildClose: null,
        bodyPartTitleClose: null,
        remainingBucketWorkouts: 0,
        streakDays: 4,
      );

      expect(nudge, isA<NudgeStreak>());
      expect((nudge as NudgeStreak).days, equals(4));
    });

    test('returns NudgeFirstStep when all inputs are null/0', () {
      final nudge = selectNudge(
        crossBuildClose: null,
        bodyPartTitleClose: null,
        remainingBucketWorkouts: 0,
        streakDays: 0,
      );

      expect(nudge, isA<NudgeFirstStep>());
    });

    test('treats negative streakDays as 0 (defensive)', () {
      final nudge = selectNudge(
        crossBuildClose: null,
        bodyPartTitleClose: null,
        remainingBucketWorkouts: 0,
        streakDays: -1,
      );

      expect(nudge, isA<NudgeFirstStep>());
    });
  });
}
