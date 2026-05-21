import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/implied_tier.dart';

/// Tolerance for the per-lift × per-gender tier interpolator. The Python
/// sim is the oracle — these tests assert the Dart port matches at 1e-9
/// absolute for every fixture row.
const double _eps = 1e-9;

Map<String, dynamic> _loadFixtures() {
  final file = File('test/fixtures/rpg_xp_fixtures.json');
  if (!file.existsSync()) {
    throw StateError(
      'rpg_xp_fixtures.json missing — run '
      '`python test/fixtures/generate_rpg_fixtures.py` first.',
    );
  }
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late final Map<String, dynamic> fixtures;

  setUpAll(() {
    fixtures = _loadFixtures();
  });

  group('impliedTier — fixture parity', () {
    test('every case matches Python sim within $_eps absolute', () {
      final cases = fixtures['implied_tier'] as List<dynamic>;
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final exercise = c['exercise'] as String;
        final weight = (c['weight_kg'] as num).toDouble();
        final reps = c['reps'] as int;
        final bw = (c['bodyweight_kg'] as num).toDouble();
        final female = c['female'] as bool;
        final expected = (c['implied_tier'] as num).toDouble();
        final actual = impliedTier(
          exercise: exercise,
          weightKg: weight,
          reps: reps,
          bodyweightKg: bw,
          gender: female ? LiftGender.female : LiftGender.male,
        );
        expect(
          actual,
          closeTo(expected, _eps),
          reason:
              '[${c['name']}] '
              'exercise=$exercise w=$weight r=$reps bw=$bw female=$female',
        );
      }
    });
  });

  group('impliedTier — gender NULL fallback', () {
    test('null gender matches male table (Diego bench pin)', () {
      // Diego: bench 85kg × 5 @ 80kg BW. Brzycki 1RM ≈ 95.6, ratio ≈ 1.20.
      // Male bench table: Beginner (15, 1.00) → Intermediate (25, 1.25).
      // Interpolated tier ≈ 22.8.
      final maleResult = impliedTier(
        exercise: 'bench',
        weightKg: 85,
        reps: 5,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      final nullResult = impliedTier(
        exercise: 'bench',
        weightKg: 85,
        reps: 5,
        bodyweightKg: 80,
      );
      expect(nullResult, closeTo(maleResult, _eps));
      expect(maleResult, closeTo(22.8125, 1e-3));
    });

    test('Gender.other falls back to male table', () {
      final otherResult = impliedTier(
        exercise: 'bench',
        weightKg: 85,
        reps: 5,
        bodyweightKg: 80,
        gender: LiftGender.other,
      );
      final maleResult = impliedTier(
        exercise: 'bench',
        weightKg: 85,
        reps: 5,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      expect(otherResult, closeTo(maleResult, _eps));
    });
  });

  group('impliedTier — variant discount', () {
    test('leg_press 0.65 discount produces higher tier than back squat '
        'at same weight', () {
      // 100kg × 5 @ 80kg BW. Squat: 1RM 112.5, ratio 1.41 → tier between
      // Beginner (15, 1.25) and Intermediate (25, 1.75) → ~18.
      // Leg_press with 0.65 discount: same 1RM divided by 0.65 → ratio
      // 2.17 → much higher tier.
      final squat = impliedTier(
        exercise: 'squat',
        weightKg: 100,
        reps: 5,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      final legPress = impliedTier(
        exercise: 'leg_press',
        weightKg: 100,
        reps: 5,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      expect(
        squat,
        lessThan(legPress),
        reason:
            'leg_press discount should yield higher tier for the '
            'same load (it\'s easier; the lift counts for more rank credit '
            'per kg)',
      );
    });

    test('incline_bench 0.90 discount slightly above bench at same load', () {
      final bench = impliedTier(
        exercise: 'bench',
        weightKg: 80,
        reps: 8,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      final incline = impliedTier(
        exercise: 'incline_bench',
        weightKg: 80,
        reps: 8,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      expect(incline, greaterThan(bench));
    });
  });

  group('impliedTier — bodyweight edge cases', () {
    test('bodyweight 0 returns the documented kBodyweightZeroFallback '
        '(15.0)', () {
      expect(
        impliedTier(
          exercise: 'bench',
          weightKg: 100,
          reps: 5,
          bodyweightKg: 0,
          gender: LiftGender.male,
        ),
        kBodyweightZeroFallback,
      );
      expect(kBodyweightZeroFallback, 15.0);
    });

    test('negative bodyweight returns fallback (defensive)', () {
      expect(
        impliedTier(
          exercise: 'bench',
          weightKg: 100,
          reps: 5,
          bodyweightKg: -10,
          gender: LiftGender.male,
        ),
        kBodyweightZeroFallback,
      );
    });
  });

  group('impliedTier — persona pins from PR brief', () {
    test('Diego bench wk1 — male bench 85×5 @ 80kg', () {
      // Brzycki 1RM ≈ 95.625, ratio 1.195. Beginner (15, 1.00) →
      // Intermediate (25, 1.25). Interp ≈ 22.8.
      final t = impliedTier(
        exercise: 'bench',
        weightKg: 85,
        reps: 5,
        bodyweightKg: 80,
        gender: LiftGender.male,
      );
      expect(t, closeTo(22.8, 0.1));
    });

    test('Female Intermediate bench — 45×8 @ 60kg', () {
      // Brzycki 1RM 45×36/29 ≈ 55.86, ratio 0.931. Female bench:
      // Beginner (15, 0.78) → Intermediate (25, 1.13). Interp ≈ 19.3.
      final t = impliedTier(
        exercise: 'bench',
        weightKg: 45,
        reps: 8,
        bodyweightKg: 60,
        gender: LiftGender.female,
      );
      expect(t, closeTo(19.3, 0.2));
    });

    test('Elite bench — 180×3 @ 95kg lands at World-class (55+)', () {
      // Brzycki 1RM 180×36/34 ≈ 190.59, ratio 2.006. Male bench
      // World-class boundary at 2.00 → tier 55+.
      final t = impliedTier(
        exercise: 'bench',
        weightKg: 180,
        reps: 3,
        bodyweightKg: 95,
        gender: LiftGender.male,
      );
      expect(t, greaterThanOrEqualTo(55.0));
    });
  });

  // ---------------------------------------------------------------------------
  // tier_diff_mult + abs_strength_premium — pinned without fixture (the
  // canonical fixture rows live in xp_calculator_test.dart; here we add
  // a few extra targeted edge cases).
  // ---------------------------------------------------------------------------

  group('tierDiffMult — edge cases', () {
    test('T=R=1 produces exactly 1.0', () {
      expect(
        tierDiffMult(impliedTier: 1.0, currentRank: 1.0),
        closeTo(1.0, _eps),
      );
    });

    test('T=0 short-circuits to 1.0 (no tier signal)', () {
      expect(tierDiffMult(impliedTier: 0.0, currentRank: 50.0), 1.0);
    });

    test('extreme floor — weak lift at high rank clamps to '
        'kTierDiffMin (0.25)', () {
      expect(tierDiffMult(impliedTier: 1.0, currentRank: 99.0), kTierDiffMin);
    });

    test('rank floored at 1.0 — currentRank=0 treated as 1', () {
      expect(
        tierDiffMult(impliedTier: 25.0, currentRank: 0.0),
        closeTo(tierDiffMult(impliedTier: 25.0, currentRank: 1.0), _eps),
      );
    });
  });

  group('absStrengthPremium — boundary pins', () {
    test('exactly E_FLOOR (35) → 1.0', () {
      expect(absStrengthPremium(kEFloor), 1.0);
      expect(absStrengthPremiumFrac(kEFloor), 0.0);
    });

    test('exactly E_CEIL (55) → 1.8 (saturated)', () {
      expect(absStrengthPremium(kECeil), closeTo(1.8, _eps));
      expect(absStrengthPremiumFrac(kECeil), closeTo(1.0, _eps));
    });

    test('mid-band T=45 → frac=0.5, premium=1.4', () {
      expect(absStrengthPremiumFrac(45.0), closeTo(0.5, _eps));
      expect(absStrengthPremium(45.0), closeTo(1.4, _eps));
    });

    test('below floor saturates at frac=0, premium=1.0', () {
      expect(absStrengthPremium(0.0), 1.0);
      expect(absStrengthPremium(34.99), 1.0);
    });

    test('above ceiling saturates at frac=1, premium=1.8', () {
      expect(absStrengthPremium(70.0), closeTo(1.8, _eps));
      expect(absStrengthPremium(100.0), closeTo(1.8, _eps));
    });
  });
}
