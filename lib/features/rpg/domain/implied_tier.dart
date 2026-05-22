/// Per-lift × per-gender Symmetric Strength tier interpolator
/// (Phase 29 v2 + 29.6 Refinement #1).
///
/// Returns an interpolated rank-equivalent in `[0.0, 70.0]` based on:
///   * Per-lift family table (bench / squat / deadlift / OHP / row / isolation)
///   * Gender (male = Symmetric Strength; female = strengthlevel.com snapshot
///     2026-05-20). `Gender.other` and NULL both fall back to the male table.
///   * Per-exercise variant discount (e.g. `leg_press` 0.65, `incline_bench`
///     0.90 — the variant is easier than the family's reference lift).
///   * Brzycki 1RM estimate: `1RM ≈ weight × 36 / (37 - reps)`.
///
/// Mirrors `tasks/rpg-xp-simulation.py::implied_tier` byte-for-byte. If you
/// change a tier table, discount, or the Brzycki formula here, change the
/// Python sim + regenerate the fixture in the same PR — the parity test
/// asserts 1e-4 absolute against the regenerated oracle.
///
/// Used by the per-set XP chain:
///   * `tier_diff_mult` — rewards lifts that punch above current rank
///   * `abs_strength_premium` (Phase 29.6 Path C) — rewards absolute strength
///
/// Pure module — no IO, no allocations beyond the const tables, no state.
library;

import 'dart:math' as math;

/// Lift family — drives which tier table the interpolator reads.
///
/// Mapping is exercise-aware (a bench-press variant resolves to
/// [LiftFamily.bench]; leg press to [LiftFamily.squat] with a discount; etc.).
/// Exercises not present in [_exerciseTierFamily] default to
/// [LiftFamily.bench] — same fallback as the Python sim.
enum LiftFamily { bench, squat, deadlift, ohp, row, isolation }

/// User gender — feeds the tier-table selection. NULL on the model layer
/// falls back to [Gender.male] (matches the documented backward-compat
/// path for users who haven't set their gender yet).
enum LiftGender { male, female, other }

/// Phase 29.6 Path C — fraction of [kEBonus] applied as
/// `abs_strength_premium = 1 + kEBonus × frac` where
/// `frac = clamp((T - kEFloor) / (kECeil - kEFloor), 0, 1)`.
///
/// Yields:
///   * `T ≤ kEFloor (35)` → frac = 0  → premium = 1.00
///   * `T ≥ kECeil  (55)` → frac = 1  → premium = 1.80
///   * Linear interp between.
const double kEBonus = 0.8;
const double kEFloor = 35.0;
const double kECeil = 55.0;

/// tier_diff_mult — Pokemon Gen 5 adaptation. Formula:
///   `mult = clamp(((2T + offset) / (T + R + offset))^exp, min, max)`
const double kTierDiffOffset = 10.0;
const double kTierDiffExp = 2.5;
const double kTierDiffMin = 0.25;
const double kTierDiffMax = 8.0;

/// Bodyweight 0 fallback: when the user hasn't supplied a bodyweight, we
/// return this neutral mid-table tier rather than blowing up the formula.
/// Matches the Python sim's behavior (15.0 = Beginner).
const double kBodyweightZeroFallback = 15.0;

// ---------------------------------------------------------------------------
// Tier tables — empirical normative ratios per lift family, per gender.
// Locked Phase 29 v2 + 29.6. Each row is (rank, bodyweight-ratio).
// ---------------------------------------------------------------------------

/// Tier row: `(rank, bodyweight-ratio)`.
typedef _TierRow = (int rank, double ratio);

const List<_TierRow> _benchMale = [
  (0, 0.50),
  (8, 0.75),
  (15, 1.00),
  (25, 1.25),
  (35, 1.50),
  (45, 1.75),
  (55, 2.00),
  (65, 2.50),
];

const List<_TierRow> _squatMale = [
  (0, 0.60),
  (8, 1.00),
  (15, 1.25),
  (25, 1.75),
  (35, 2.25),
  (45, 2.75),
  (55, 3.25),
  (65, 3.75),
];

const List<_TierRow> _deadliftMale = [
  (0, 0.80),
  (8, 1.25),
  (15, 1.50),
  (25, 2.00),
  (35, 2.50),
  (45, 3.00),
  (55, 3.50),
  (65, 3.75),
];

const List<_TierRow> _ohpMale = [
  (0, 0.30),
  (8, 0.45),
  (15, 0.60),
  (25, 0.75),
  (35, 0.90),
  (45, 1.05),
  (55, 1.20),
  (65, 1.40),
];

const List<_TierRow> _rowMale = [
  (0, 0.60),
  (8, 0.90),
  (15, 1.20),
  (25, 1.55),
  (35, 1.90),
  (45, 2.30),
  (55, 2.70),
  (65, 3.00),
];

const List<_TierRow> _isolationMale = [
  (0, 0.08),
  (8, 0.13),
  (15, 0.20),
  (25, 0.30),
  (35, 0.40),
  (45, 0.50),
  (55, 0.60),
  (65, 0.70),
];

const List<_TierRow> _benchFemale = [
  (0, 0.28),
  (8, 0.48),
  (15, 0.78),
  (25, 1.13),
  (35, 1.53),
  (45, 1.90),
  (55, 2.30),
  (65, 2.80),
];

const List<_TierRow> _squatFemale = [
  (0, 0.48),
  (8, 0.78),
  (15, 1.17),
  (25, 1.62),
  (35, 2.13),
  (45, 2.70),
  (55, 3.10),
  (65, 3.50),
];

const List<_TierRow> _deadliftFemale = [
  (0, 0.62),
  (8, 0.95),
  (15, 1.38),
  (25, 1.88),
  (35, 2.43),
  (45, 3.00),
  (55, 3.40),
  (65, 3.80),
];

const List<_TierRow> _ohpFemale = [
  (0, 0.20),
  (8, 0.35),
  (15, 0.53),
  (25, 0.75),
  (35, 1.00),
  (45, 1.25),
  (55, 1.50),
  (65, 1.80),
];

const List<_TierRow> _rowFemale = [
  (0, 0.48),
  (8, 0.72),
  (15, 1.00),
  (25, 1.35),
  (35, 1.70),
  (45, 2.10),
  (55, 2.50),
  (65, 2.80),
];

const List<_TierRow> _isolationFemale = [
  (0, 0.05),
  (8, 0.09),
  (15, 0.14),
  (25, 0.22),
  (35, 0.32),
  (45, 0.42),
  (55, 0.52),
  (65, 0.62),
];

const Map<LiftFamily, List<_TierRow>> _maleTables = {
  LiftFamily.bench: _benchMale,
  LiftFamily.squat: _squatMale,
  LiftFamily.deadlift: _deadliftMale,
  LiftFamily.ohp: _ohpMale,
  LiftFamily.row: _rowMale,
  LiftFamily.isolation: _isolationMale,
};

const Map<LiftFamily, List<_TierRow>> _femaleTables = {
  LiftFamily.bench: _benchFemale,
  LiftFamily.squat: _squatFemale,
  LiftFamily.deadlift: _deadliftFemale,
  LiftFamily.ohp: _ohpFemale,
  LiftFamily.row: _rowFemale,
  LiftFamily.isolation: _isolationFemale,
};

/// Exercise → tier family dispatch. Exercises not present here default to
/// [LiftFamily.bench] (same as the Python sim). The map intentionally
/// accepts both simulator short aliases (`bench`, `squat`, `pullup`) AND
/// real slugs (`barbell_bench_press`, `pull_up`) so production callers
/// passing live slugs work the same as the parity tests.
const Map<String, LiftFamily> _exerciseTierFamily = {
  // Bench family
  'bench': LiftFamily.bench,
  'incline_bench': LiftFamily.bench,
  'barbell_bench_press': LiftFamily.bench,
  'incline_barbell_bench_press': LiftFamily.bench,
  'machine_chest_press': LiftFamily.bench,
  // OHP family
  'overhead_press': LiftFamily.ohp,
  // Squat family
  'squat': LiftFamily.squat,
  'barbell_squat': LiftFamily.squat,
  'leg_press': LiftFamily.squat,
  'lunge': LiftFamily.squat,
  'walking_lunges': LiftFamily.squat,
  // Deadlift family
  'deadlift': LiftFamily.deadlift,
  'romanian_deadlift': LiftFamily.deadlift,
  // Row family
  'row': LiftFamily.row,
  'barbell_bent_over_row': LiftFamily.row,
  'pendlay_row': LiftFamily.row,
  'pulldown': LiftFamily.row,
  'lat_pulldown': LiftFamily.row,
  'pullup': LiftFamily.row,
  'pull_up': LiftFamily.row,
  'seated_row': LiftFamily.row,
  // Isolation family
  'curl': LiftFamily.isolation,
  'barbell_curl': LiftFamily.isolation,
  'tricep_pushdown': LiftFamily.isolation,
  'lateral_raise': LiftFamily.isolation,
  'plank': LiftFamily.isolation,
  'leg_raise': LiftFamily.isolation,
  'leg_extension': LiftFamily.isolation,
  'leg_curl': LiftFamily.isolation,
};

/// Per-exercise variant discount (a variant of the family's reference lift
/// is easier — e.g. `leg_press` is easier than back squat). Multiplied
/// against the ratio denominator, so a smaller discount = more credit for
/// the same load.
const Map<String, double> _exerciseTierDiscount = {
  'leg_press': 0.65,
  'pulldown': 0.75,
  'lat_pulldown': 0.75,
  'incline_bench': 0.90,
  'incline_barbell_bench_press': 0.90,
  'lunge': 0.80,
  'walking_lunges': 0.80,
  'plank': 0.50,
  'leg_raise': 0.50,
  'machine_chest_press': 0.60,
  'seated_row': 0.75,
  'leg_extension': 0.50,
  'leg_curl': 0.50,
  'romanian_deadlift': 0.90,
};

/// Brzycki 1RM estimate. Matches the Symmetric Strength curve.
double _brzycki1Rm(double weight, int reps) {
  if (reps <= 1) return weight;
  if (reps >= 37) return weight;
  return weight * 36.0 / (37.0 - reps);
}

/// Linear interpolate `(rank, ratio)` pairs.
double _interpTier(List<_TierRow> table, double ratio) {
  if (ratio <= table.first.$2) return table.first.$1.toDouble();
  if (ratio >= table.last.$2) return table.last.$1.toDouble();
  for (var i = 0; i < table.length - 1; i++) {
    final lo = table[i];
    final hi = table[i + 1];
    final loRatio = lo.$2;
    final hiRatio = hi.$2;
    if (loRatio <= ratio && ratio <= hiRatio) {
      if (hiRatio == loRatio) return lo.$1.toDouble();
      final loRank = lo.$1.toDouble();
      final hiRank = hi.$1.toDouble();
      return loRank +
          (ratio - loRatio) / (hiRatio - loRatio) * (hiRank - loRank);
    }
  }
  return table.last.$1.toDouble();
}

/// Returns the lift-implied tier in `[0.0, 70.0]` for the given set.
///
/// `gender` NULL → male table fallback. `bodyweightKg <= 0` → returns
/// [kBodyweightZeroFallback] (15.0).
///
/// Mirrors `tasks/rpg-xp-simulation.py::implied_tier` exactly. The parity
/// test asserts 1e-9 absolute against the regenerated fixture for every
/// case in `fixtures['implied_tier']`.
double impliedTier({
  required String exercise,
  required double weightKg,
  required int reps,
  required double bodyweightKg,
  LiftGender? gender,
}) {
  if (bodyweightKg <= 0) return kBodyweightZeroFallback;
  final family = _exerciseTierFamily[exercise] ?? LiftFamily.bench;
  // Gender NULL or `Gender.other` → male table (documented backward-compat).
  final tables = (gender == LiftGender.female) ? _femaleTables : _maleTables;
  final table = tables[family]!;
  final discount = _exerciseTierDiscount[exercise] ?? 1.0;
  final oneRm = _brzycki1Rm(weightKg, reps);
  final ratio = oneRm / bodyweightKg / discount;
  return _interpTier(table, ratio);
}

/// Phase 29.6 Path C fraction. Exposed so tests can pin it independent
/// of the multiplier helper. See top-of-file constants.
double absStrengthPremiumFrac(double impliedTier) {
  final frac = (impliedTier - kEFloor) / (kECeil - kEFloor);
  if (frac < 0) return 0.0;
  if (frac > 1) return 1.0;
  return frac;
}

/// `abs_strength_premium = 1.0 + kEBonus × frac(T)`. Saturates at 1.8
/// for `T ≥ kECeil`.
double absStrengthPremium(double impliedTier) {
  return 1.0 + kEBonus * absStrengthPremiumFrac(impliedTier);
}

/// `tier_diff_mult = clamp(((2T + offset) / (T + R + offset))^exp,
///                          kTierDiffMin, kTierDiffMax)`.
///
/// Rewards lifts that punch above the current rank. `T <= 0` short-
/// circuits to 1.0 (no tier signal). Current rank is floored at 1.0 to
/// avoid divide-by-zero at fresh-account state.
double tierDiffMult({
  required double impliedTier,
  required double currentRank,
}) {
  if (impliedTier <= 0) return 1.0;
  final r = currentRank < 1.0 ? 1.0 : currentRank;
  final num = 2.0 * impliedTier + kTierDiffOffset;
  final den = impliedTier + r + kTierDiffOffset;
  if (den <= 0) return kTierDiffMax;
  final raw = math.pow(num / den, kTierDiffExp).toDouble();
  if (raw < kTierDiffMin) return kTierDiffMin;
  if (raw > kTierDiffMax) return kTierDiffMax;
  return raw;
}
