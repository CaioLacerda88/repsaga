import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/conditioning_charge.dart';

void main() {
  group('ConditioningCharge.fromSnapshots', () {
    test('aggregate is the mean of clamp(ewma/peak) over trained bps', () {
      // chest: 50/100 = 0.5, back: 30/100 = 0.3 → mean before = 0.40
      // chest: 70/100 = 0.7, back: 50/100 = 0.5 → mean after  = 0.60
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest, BodyPart.back],
        before: const {
          BodyPart.chest: (ewma: 50, peak: 100),
          BodyPart.back: (ewma: 30, peak: 100),
        },
        after: const {
          BodyPart.chest: (ewma: 70, peak: 100),
          BodyPart.back: (ewma: 50, peak: 100),
        },
      );
      expect(charge.beforePct, closeTo(0.40, 1e-9));
      expect(charge.afterPct, closeTo(0.60, 1e-9));
      // delta = 0.60 - 0.40 = 0.20 → +20%
      expect(charge.deltaPercentInt, 20);
      expect(charge.shouldRender, isTrue);
    });

    test('clamps per-bp ratio to 1.0 when ewma exceeds peak', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 50, peak: 100)},
        // ewma > peak (transient overshoot) → clamps to 1.0, not 1.5
        after: const {BodyPart.chest: (ewma: 150, peak: 100)},
      );
      expect(charge.afterPct, 1.0);
      expect(charge.deltaPercentInt, 50);
    });

    test('excludes bps with peak == 0 (never charged → undefined ratio)', () {
      // back has peak 0 — undefined ratio, excluded from the mean on both
      // sides. Only chest contributes: before 0.5, after 0.8.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest, BodyPart.back],
        before: const {
          BodyPart.chest: (ewma: 50, peak: 100),
          BodyPart.back: (ewma: 0, peak: 0),
        },
        after: const {
          BodyPart.chest: (ewma: 80, peak: 100),
          BodyPart.back: (ewma: 0, peak: 0),
        },
      );
      expect(charge.beforePct, closeTo(0.5, 1e-9));
      expect(charge.afterPct, closeTo(0.8, 1e-9));
      expect(charge.deltaPercentInt, 30);
    });

    test('hides gracefully when no trained bp has charge data', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 0, peak: 0)},
        after: const {BodyPart.chest: (ewma: 0, peak: 0)},
      );
      expect(charge.beforePct, 0.0);
      expect(charge.afterPct, 0.0);
      expect(charge.shouldRender, isFalse);
    });

    test('hides gracefully when trained set is empty (day-zero)', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [],
        before: const {},
        after: const {},
      );
      expect(charge.shouldRender, isFalse);
    });

    test('delta clamps at 0 — never reads as a depleting bar', () {
      // after < before (e.g. a same-day re-save numerically flat, or a
      // decayed snapshot): the honest delta is 0%, never negative. The bar
      // is a rebuild signal only.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 80, peak: 100)},
        after: const {BodyPart.chest: (ewma: 60, peak: 100)},
      );
      expect(charge.deltaPct, 0.0);
      expect(charge.deltaPercentInt, 0);
      expect(charge.shouldRender, isFalse);
    });

    test('hides when delta rounds to 0% (fully-charged plateau)', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 99, peak: 100)},
        after: const {BodyPart.chest: (ewma: 100, peak: 100)},
      );
      // delta = 0.01 → rounds to 1%, renders. Bump to a sub-0.5% delta:
      final tiny = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 998, peak: 1000)},
        after: const {BodyPart.chest: (ewma: 1000, peak: 1000)},
      );
      expect(charge.deltaPercentInt, 1);
      expect(tiny.deltaPercentInt, 0);
      expect(tiny.shouldRender, isFalse);
    });
  });
}
