import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/conditioning_charge.dart';

void main() {
  group('ConditioningCharge.fromSnapshots — per-bp charge', () {
    test('charge fraction uses refPeak as the denominator', () {
      // chest: ewma 50 / refPeak 100 = 0.5 before, 70/100 = 0.7 after.
      // Note refPeak != peak — peak is ignored entirely.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 50, peak: 999, refPeak: 100)},
        after: const {BodyPart.chest: (ewma: 70, peak: 999, refPeak: 100)},
      );
      final chest = charge.parts.single;
      expect(chest.beforePct, closeTo(0.5, 1e-9));
      expect(chest.afterPct, closeTo(0.7, 1e-9));
      // delta = 0.20 → +20%.
      expect(chest.deltaPercentInt, 20);
      expect(chest.isMax, isFalse);
      expect(charge.shouldRender, isTrue);
    });

    test('clamps per-bp ratio to 1.0 when ewma exceeds refPeak', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 50, peak: 0, refPeak: 100)},
        after: const {BodyPart.chest: (ewma: 150, peak: 0, refPeak: 100)},
      );
      final chest = charge.parts.single;
      expect(chest.afterPct, 1.0);
      // before 0.5 → after 1.0 → +50%, and isMax (>= 0.995).
      expect(chest.deltaPercentInt, 50);
      expect(chest.isMax, isTrue);
    });

    test('excludes bps with refPeak <= 0 (never charged → no charge data)', () {
      // back has refPeak 0 — undefined fraction, excluded entirely.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest, BodyPart.back],
        before: const {
          BodyPart.chest: (ewma: 50, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 0, peak: 0, refPeak: 0),
        },
        after: const {
          BodyPart.chest: (ewma: 80, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 0, peak: 0, refPeak: 0),
        },
      );
      expect(charge.parts.map((p) => p.bodyPart), [BodyPart.chest]);
      expect(charge.parts.single.deltaPercentInt, 30);
    });

    test('hides when no trained bp has charge data (day-zero)', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 0, peak: 0, refPeak: 0)},
        after: const {BodyPart.chest: (ewma: 0, peak: 0, refPeak: 0)},
      );
      expect(charge.parts, isEmpty);
      expect(charge.alreadyChargedToday, isFalse);
      expect(charge.shouldRender, isFalse);
    });

    test('hides when trained set is empty', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [],
        before: const {},
        after: const {},
      );
      expect(charge.shouldRender, isFalse);
    });
  });

  group('ConditioningCharge — MÁX detection', () {
    test('afterPct >= 0.995 is MÁX with a full rune and zero delta', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.legs],
        before: const {BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100)},
        after: const {BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100)},
      );
      final legs = charge.parts.single;
      expect(legs.isMax, isTrue);
      expect(legs.afterPct, 1.0);
      // No positive gain → 0, never a +0 gainer delta (widget shows MÁX).
      expect(legs.deltaPercentInt, 0);
    });

    test('99.4% is NOT MÁX (below the 0.995 threshold)', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.legs],
        before: const {BodyPart.legs: (ewma: 980, peak: 1000, refPeak: 1000)},
        after: const {BodyPart.legs: (ewma: 994, peak: 1000, refPeak: 1000)},
      );
      expect(charge.parts.single.isMax, isFalse);
    });
  });

  group('ConditioningCharge — +1% floor', () {
    test('a real positive gain that rounds to 0 is floored to +1%', () {
      // 100/10000 = 1.00% → 112/10000 = 1.12% → raw +0.12pp → rounds to 0,
      // floored to 1 because there IS a genuine positive step.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.arms],
        before: const {BodyPart.arms: (ewma: 100, peak: 9999, refPeak: 10000)},
        after: const {BodyPart.arms: (ewma: 112, peak: 9999, refPeak: 10000)},
      );
      expect(charge.parts.single.deltaPercentInt, 1);
    });

    test('a truly flat part stays at 0% (not floored to +1%)', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.arms],
        before: const {BodyPart.arms: (ewma: 100, peak: 9999, refPeak: 10000)},
        after: const {BodyPart.arms: (ewma: 100, peak: 9999, refPeak: 10000)},
      );
      expect(charge.parts.single.deltaPercentInt, 0);
    });

    test('a decayed (after < before) part reads 0%, never negative', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.arms],
        before: const {BodyPart.arms: (ewma: 80, peak: 100, refPeak: 100)},
        after: const {BodyPart.arms: (ewma: 60, peak: 100, refPeak: 100)},
      );
      expect(charge.parts.single.deltaPercentInt, 0);
    });
  });

  group('ConditioningCharge — ordering', () {
    test('gainers sort by delta descending', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.arms, BodyPart.core, BodyPart.back],
        before: const {
          BodyPart.arms: (ewma: 50, peak: 100, refPeak: 100), // +12 → 0.62
          BodyPart.core: (ewma: 40, peak: 100, refPeak: 100), // +24 → 0.64
          BodyPart.back: (ewma: 60, peak: 100, refPeak: 100), // +17 → 0.77
        },
        after: const {
          BodyPart.arms: (ewma: 62, peak: 100, refPeak: 100),
          BodyPart.core: (ewma: 64, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 77, peak: 100, refPeak: 100),
        },
      );
      expect(charge.parts.map((p) => p.bodyPart), [
        BodyPart.core, // +24
        BodyPart.back, // +17
        BodyPart.arms, // +12
      ]);
    });

    test('MÁX/held rows sort after gainers', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [
          BodyPart.legs, // maxed, delta 0
          BodyPart.back, // +17 gainer
          BodyPart.cardio, // maxed, delta 0
        ],
        before: const {
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 60, peak: 100, refPeak: 100),
          BodyPart.cardio: (ewma: 100, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 77, peak: 100, refPeak: 100),
          BodyPart.cardio: (ewma: 100, peak: 100, refPeak: 100),
        },
      );
      // Gainer first; then the two held rows (enum-index tiebreak: legs < cardio).
      expect(charge.parts.map((p) => p.bodyPart), [
        BodyPart.back,
        BodyPart.legs,
        BodyPart.cardio,
      ]);
    });
  });

  group('ConditioningCharge — render gate', () {
    test('all-maxed session still renders (allHeld true)', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.legs, BodyPart.cardio],
        before: const {
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
          BodyPart.cardio: (ewma: 100, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
          BodyPart.cardio: (ewma: 100, peak: 100, refPeak: 100),
        },
      );
      expect(charge.shouldRender, isTrue);
      expect(charge.allHeld, isTrue);
      expect(charge.hasMaxedParts, isTrue);
      // All EWMAs exactly flat → ALSO the guard signal. allHeld + guard can
      // coexist; the widget prefers the guard branch. Here all are maxed
      // AND flat, so alreadyChargedToday is true.
      expect(charge.alreadyChargedToday, isTrue);
    });

    test('a maxed part that still stepped is not all-held', () {
      // legs maxed but its ewma rose (still climbing toward a higher refPeak
      // would be the real case; here refPeak == ewma so it pins at 1.0 but
      // the ewma changed → not flat, not allHeld).
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.legs, BodyPart.back],
        before: const {
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 60, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.legs: (ewma: 100, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 77, peak: 100, refPeak: 100),
        },
      );
      expect(charge.allHeld, isFalse); // back gained
      expect(charge.alreadyChargedToday, isFalse); // back's ewma changed
    });
  });

  group('ConditioningCharge — alreadyChargedToday (guard)', () {
    test('every trained bp with flat EWMA → guard true', () {
      // Same-day re-save: server skipped the step, EWMAs byte-identical.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest, BodyPart.back],
        before: const {
          BodyPart.chest: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 33, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.chest: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 33, peak: 100, refPeak: 100),
        },
      );
      expect(charge.alreadyChargedToday, isTrue);
      expect(charge.shouldRender, isTrue);
    });

    test('a single stepped bp breaks the guard signal', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest, BodyPart.back],
        before: const {
          BodyPart.chest: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 33, peak: 100, refPeak: 100),
        },
        after: const {
          BodyPart.chest: (ewma: 55, peak: 100, refPeak: 100),
          BodyPart.back: (ewma: 50, peak: 100, refPeak: 100), // stepped
        },
      );
      expect(charge.alreadyChargedToday, isFalse);
    });

    test('guard requires charge data — empty parts is not guard-blocked', () {
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {BodyPart.chest: (ewma: 0, peak: 0, refPeak: 0)},
        after: const {BodyPart.chest: (ewma: 0, peak: 0, refPeak: 0)},
      );
      expect(charge.alreadyChargedToday, isFalse);
      expect(charge.shouldRender, isFalse);
    });

    test('a bp absent from before but present after counts as a real step', () {
      // before snapshot has no row for this bp (first charge ever this
      // session) → treated as a step, not a guard-block.
      final charge = ConditioningCharge.fromSnapshots(
        trainedBodyParts: const [BodyPart.chest],
        before: const {},
        after: const {BodyPart.chest: (ewma: 30, peak: 100, refPeak: 100)},
      );
      expect(charge.alreadyChargedToday, isFalse);
      expect(charge.parts.single.beforePct, 0.0);
      expect(charge.parts.single.afterPct, closeTo(0.3, 1e-9));
    });
  });
}
