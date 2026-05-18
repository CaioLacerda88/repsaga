import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/domain/weekly_engagement.dart';

void main() {
  group(
    'primaryBodyPartsForSet — max-share with strict-equality tie counting',
    () {
      test(
        'should return only the dominant body part when one share is largest',
        () {
          // barbell_bench_press: chest 0.70, shoulders 0.20, arms 0.10
          final result = primaryBodyPartsForSet({
            'chest': 0.70,
            'shoulders': 0.20,
            'arms': 0.10,
          });
          expect(result, equals({BodyPart.chest}));
        },
      );

      test('should count both body parts on a strict-equality two-way tie', () {
        // Synthetic tie: chest 0.50, back 0.50.
        final result = primaryBodyPartsForSet({'chest': 0.50, 'back': 0.50});
        expect(result, equals({BodyPart.chest, BodyPart.back}));
      });

      test(
        'should pick only the strict max when shares are near-but-not-equal',
        () {
          final result = primaryBodyPartsForSet({
            'chest': 0.34,
            'back': 0.33,
            'legs': 0.33,
          });
          // 0.34 > 0.33 = 0.33: only chest wins (strict equality required for tie).
          expect(result, equals({BodyPart.chest}));
        },
      );

      test(
        'should treat 0.50 == 0.50 as a tie and 0.50 vs 0.499 as not a tie',
        () {
          final tied = primaryBodyPartsForSet({'chest': 0.50, 'back': 0.50});
          expect(tied, equals({BodyPart.chest, BodyPart.back}));

          final notTied = primaryBodyPartsForSet({
            'chest': 0.501,
            'back': 0.499,
          });
          expect(notTied, equals({BodyPart.chest}));
        },
      );

      test('should drop cardio keys (v1 engagement excludes cardio)', () {
        // Hypothetical cardio-heavy attribution that ties with legs.
        final result = primaryBodyPartsForSet({'cardio': 0.50, 'legs': 0.50});
        // Cardio is excluded from the v1 surface — only legs counts.
        expect(result, equals({BodyPart.legs}));
      });

      test('should return empty when every share is cardio', () {
        final result = primaryBodyPartsForSet({'cardio': 1.00});
        expect(result, isEmpty);
      });

      test('should return empty for an empty attribution map', () {
        final result = primaryBodyPartsForSet(const {});
        expect(result, isEmpty);
      });

      test('should ignore zero shares (no false ties at 0.0)', () {
        final result = primaryBodyPartsForSet({'chest': 0.0, 'back': 0.0});
        // No body part has a positive share — nothing counts.
        expect(result, isEmpty);
      });
    },
  );

  group('WeeklyEngagement — totals composition', () {
    test('should compose done + planned into per-body-part numerators', () {
      final engagement = WeeklyEngagement.from(
        done: {BodyPart.chest: 10, BodyPart.back: 4},
        planned: {BodyPart.chest: 8, BodyPart.shoulders: 6},
      );
      // chest: done=10, planned=8 → plannedFor = max(10,8) = 10.
      expect(engagement.doneFor(BodyPart.chest), 10);
      expect(engagement.plannedFor(BodyPart.chest), 10);
      // back: done=4, planned=0 → plannedFor = max(4,0) = 4.
      expect(engagement.doneFor(BodyPart.back), 4);
      expect(engagement.plannedFor(BodyPart.back), 4);
      // shoulders: done=0, planned=6 → plannedFor = max(0,6) = 6.
      expect(engagement.doneFor(BodyPart.shoulders), 0);
      expect(engagement.plannedFor(BodyPart.shoulders), 6);
      // Untouched body parts default to zero.
      expect(engagement.doneFor(BodyPart.legs), 0);
      expect(engagement.plannedFor(BodyPart.legs), 0);
    });

    test(
      'should clamp planned to max(done, planned) so done never exceeds planned',
      () {
        // Edge: user did 12 chest sets but only planned 6. Planned total =
        // max(12, 6) = 12 so the planned bar reads "12 / 12" and the done
        // fill matches it (no visual gap implying unplanned work).
        final engagement = WeeklyEngagement.from(
          done: {BodyPart.chest: 12},
          planned: {BodyPart.chest: 6},
        );
        expect(engagement.doneFor(BodyPart.chest), 12);
        expect(engagement.plannedFor(BodyPart.chest), 12);
      },
    );
  });
}
