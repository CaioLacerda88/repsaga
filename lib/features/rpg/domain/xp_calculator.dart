import 'dart:math' as math;

import 'implied_tier.dart';

/// Pure XP-per-set calculator — Phase 29 v2 + 29.6 LOCKED.
///
/// Mirrors the canonical Python simulator at `tasks/rpg-xp-simulation.py`
/// and the SQL RPC chain (migration 00065+). **If you change a constant
/// here, change the Python sim, the fixture generator
/// (`test/fixtures/generate_rpg_fixtures.py`), and the PL/pgSQL
/// `record_set_xp` / `record_session_xp_batch` / `_rpg_backfill_chunk`
/// RPCs in the same PR.** All four sites are checked for parity by the
/// integration tests at 1e-4 absolute.
///
/// Formula (11-multiplier chain — Phase 29 v2 + 29.6):
///
/// ```
/// set_xp = volume_load^0.60
///        × intensity_mult(reps, near_failure)
///        × strength_mult(weight, peak)
///        × novelty_mult(session_volume)
///        × cap_mult(weekly_volume)
///        × difficulty_mult(exercise)
///        × tier_diff_mult(implied_tier, current_rank)
///        × abs_strength_premium(implied_tier)        [Phase 29.6 Path C]
///        × overload_mult(weight, reps, prior_band_best)
///        × frequency_mult(sessions_this_week_for_bp)
///        × attribution_share[body_part]              [applied by caller]
/// ```
///
/// The chain `computeSetXp` returns is **per-set total** (before
/// attribution to body parts). Body-part fan-out is the caller's job
/// (`xp_distribution.dart`) — it multiplies the returned [SetXpComponents.setXp]
/// by each `attribution[body_part]` share.
///
/// ## Backward-compat (legacy Phase 24 chain)
///
/// All Phase 29 v2 parameters are optional and default to neutral
/// values (multiplier = 1.0). A caller that passes only the Phase 24c
/// six-arg signature gets a chain that's numerically equivalent to the
/// pre-29 chain — same as the Python sim's documented backward-compat
/// path. This keeps the integration tests in `test/integration/rpg_*`
/// compiling without churn while the live SQL save-path is the only
/// production consumer of the new multipliers.
///
/// New parameter semantics:
///
///   * [impliedTier] — lift-implied rank from
///     [impliedTier] (the function in `implied_tier.dart`). Pass 0 (or
///     omit) → tier_diff_mult = 1.0, abs_strength_premium = 1.0.
///   * [currentRank] — user's current rank for the dominant body part.
///     Defaults to 1 (fresh-account neutral state). Only matters when
///     [impliedTier] > 0.
///   * [priorBandWeight] / [priorBandReps] — the best prior set in the
///     SAME rep band for this exercise. Both null → overload_mult = 1.0.
///   * [sessionsThisWeekForBodyPart] — count of distinct sessions in the
///     7-day window that touched the dominant body part. Null or 1 →
///     frequency_mult = 1.0. Per-bp counts > 5 saturate at 1.0.
///   * [targetReps] — programmed target. When [nearFailure] isn't
///     explicitly set and `actualReps < targetReps × 0.85`, near_failure
///     is inferred (Refinement #4).
///   * [nearFailure] — explicit flag. Default false. When true, adds
///     [kNfIntensityBonus] (+0.10) to the intensity multiplier.
class XpCalculator {
  const XpCalculator._();

  // ---- tunable constants (Phase 29 v2 + 29.6) ------------------------------

  /// Sub-linear volume exponent. 10× volume produces ~4.0× XP, not 10×.
  /// Phase 24d calibration: 0.65 → 0.60 (tightened).
  static const double volumeExponent = 0.60;

  /// τ for novelty diminishing returns within a session. After ~15 sets
  /// attributed to a body part, the next set earns e^-1 ≈ 37 % of base XP.
  static const double noveltyDenominator = 15.0;

  /// Effective sets per body part in a 7-day rolling window before
  /// [overCapMultiplier] applies. Phase 24d: 20.0 → 15.0.
  static const double weeklyCapSets = 15.0;

  /// Multiplier applied once `weekly_volume_for_body_part ≥ weeklyCapSets`.
  /// Phase 24d: 0.5 → 0.3.
  static const double overCapMultiplier = 0.3;

  /// Floor of the per-exercise `difficulty_mult` range. Documented for
  /// parity with the SQL CHECK constraint (`BETWEEN 0.85 AND 1.25`).
  /// The calculator does NOT enforce this clamp itself.
  static const double difficultyMultFloor = 0.85;

  /// Ceiling of the per-exercise `difficulty_mult` range.
  static const double difficultyMultCeiling = 1.25;

  /// Floor for the strength multiplier. A 50 % deload still earns
  /// `0.5 × set_xp`; below 40 % we floor to 0.4.
  static const double strengthMultFloor = 0.4;

  /// Volume floor — bodyweight beginners never produce zero base XP.
  static const double volumeLoadFloor = 1.0;

  // ---- Phase 29 v2 constants -----------------------------------------------

  /// Phase 29.6 Path C — see [implied_tier.kEBonus].
  static const double kEBonus = 0.8;
  static const double kEFloor = 35.0;
  static const double kECeil = 55.0;

  /// Phase 29 v2 Refinement #4 — additive intensity bonus when a set is
  /// flagged near-failure (either by [nearFailure] = true on the caller
  /// or inferred via `actualReps < targetReps × kNfTargetThreshold`).
  static const double kNfIntensityBonus = 0.10;

  /// Phase 29 v2 Refinement #4 — fraction-of-target below which a set is
  /// inferred near-failure. `8 reps < 10 × 0.85 = 8.5 → inferred`.
  static const double kNfTargetThreshold = 0.85;

  /// Phase 29 v2 Refinement #3 — multiplier table for
  /// `sessions_this_week_for_body_part`. 1-indexed: 1st session = 1.00,
  /// 2nd = 1.06, peak at 3rd = 1.10, then taper. Sessions beyond 5 clamp
  /// to the last entry (1.00).
  static const List<double> kFrequencyMultTable = [
    1.00,
    1.06,
    1.10,
    1.06,
    1.00,
  ];

  // ---- intensity table -----------------------------------------------------

  /// Reps → multiplier table. Lookup is **reps-floor**:
  /// 4 reps falls into the `reps >= 3` row → 1.25.
  static const List<int> _intensityRepsBoundaries = [1, 3, 5, 8, 12, 15, 20];
  static const List<double> _intensityMultipliers = [
    1.30, // reps >= 1
    1.25, // reps >= 3
    1.20, // reps >= 5
    1.00, // reps >= 8
    0.95, // reps >= 12
    0.90, // reps >= 15
    0.80, // reps >= 20+
  ];

  /// Returns the intensity multiplier for [reps] (without near-failure
  /// bonus). Reps below 1 return 1.0 — defensive fallback; reps `>= 20`
  /// saturate at 0.80.
  static double intensityForReps(int reps) {
    if (reps < 1) return 1.0;
    var matched = 1.0;
    for (var i = 0; i < _intensityRepsBoundaries.length; i++) {
      if (reps >= _intensityRepsBoundaries[i]) {
        matched = _intensityMultipliers[i];
      } else {
        break;
      }
    }
    return matched;
  }

  /// Intensity with the Phase 29 v2 Refinement #4 additive near-failure
  /// bonus. When [nearFailure] is true, adds [kNfIntensityBonus] (+0.10)
  /// to the base intensity.
  static double intensityWithNearFailure({
    required int reps,
    required bool nearFailure,
  }) {
    final base = intensityForReps(reps);
    return base + (nearFailure ? kNfIntensityBonus : 0.0);
  }

  /// Phase 29 v2 Refinement #4 — infer near-failure when
  /// `actualReps < targetReps × kNfTargetThreshold`. `targetReps` NULL
  /// or <= 0 → not inferred.
  static bool nearFailureInferred({
    required int actualReps,
    required int? targetReps,
  }) {
    if (targetReps == null || targetReps <= 0) return false;
    return actualReps < targetReps * kNfTargetThreshold;
  }

  // ---- volume + base -------------------------------------------------------

  /// `volume_load = max(1.0, weight_kg × reps)`.
  static double volumeLoad({required double weightKg, required int reps}) {
    if (reps < 1) return volumeLoadFloor;
    final raw = weightKg * reps;
    return raw < volumeLoadFloor ? volumeLoadFloor : raw;
  }

  /// `base_xp = volume_load^0.60` (Phase 24d).
  static double baseXp(double volumeLoad) {
    return math.pow(volumeLoad, volumeExponent).toDouble();
  }

  // ---- strength multiplier -------------------------------------------------

  /// `strength_mult = clamp(weight / peak, 0.40, 1.00)`.
  ///
  /// Special case: when `peak <= 0`, returns 1.0. Repository code is
  /// responsible for advancing the peak when `weight > peak`; this
  /// calculator does not mutate state.
  static double strengthMult({
    required double weightKg,
    required double peakLoad,
  }) {
    if (peakLoad <= 0) return 1.0;
    final ratio = weightKg / peakLoad;
    if (ratio < strengthMultFloor) return strengthMultFloor;
    if (ratio > 1.0) return 1.0;
    return ratio;
  }

  // ---- novelty -------------------------------------------------------------

  /// `novelty_mult = exp(-session_volume_for_body_part / 15)`.
  static double noveltyMult(double sessionVolumeForBodyPart) {
    if (sessionVolumeForBodyPart <= 0) return 1.0;
    return math.exp(-sessionVolumeForBodyPart / noveltyDenominator);
  }

  // ---- cap -----------------------------------------------------------------

  /// `cap_mult = 0.3 if weekly_volume >= 15 else 1.0` (Phase 24d).
  static double capMult(double weeklyVolumeForBodyPart) {
    return weeklyVolumeForBodyPart >= weeklyCapSets ? overCapMultiplier : 1.0;
  }

  // ---- Phase 29 v2 helpers -------------------------------------------------

  /// Phase 29 v2 Refinement #2 — progressive overload reward.
  ///
  /// AND/OR ladder (carried verbatim from the Python sim):
  ///   * `weight > prior` → 1.15 (new weight PR)
  ///   * `reps > prior_reps AND weight >= prior` → 1.10 (volume PR at load)
  ///   * `reps > prior OR weight > prior` → 1.05 (modest improvement)
  ///   * otherwise → 1.00
  ///
  /// `priorWeight` / `priorReps` NULL → 1.00 (no prior in this band).
  ///
  /// Caller is responsible for matching the rep band (heavy 1-4 /
  /// strength 5-7 / hypertrophy 8-12 / endurance 13+) — the calculator
  /// is band-agnostic, the band lookup happens at the repository layer.
  static double overloadMult({
    required double weightKg,
    required int reps,
    double? priorWeight,
    int? priorReps,
  }) {
    if (priorWeight == null || priorReps == null) return 1.0;
    if (weightKg > priorWeight) return 1.15;
    if (reps > priorReps && weightKg >= priorWeight) return 1.10;
    if (reps > priorReps || weightKg > priorWeight) return 1.05;
    return 1.0;
  }

  /// Phase 29 v2 Refinement #3 — sessions-per-body-part-per-7d table lookup.
  /// `sessionCount` is 1-indexed (1st session = 1.00). Clamps to 1 below
  /// and to the table length (5+) above — both endpoints land at 1.00.
  static double frequencyMult(int sessionCount) {
    final clamped = sessionCount.clamp(1, kFrequencyMultTable.length);
    return kFrequencyMultTable[clamped - 1];
  }

  // ---- end-to-end ----------------------------------------------------------

  /// Phase 29 v2 + 29.6 per-set XP. Returns the decomposed [SetXpComponents]
  /// — see the file dartdoc for the multiplication chain.
  ///
  /// Phase 29 v2 parameters are optional with neutral defaults (= 1.0) so
  /// legacy callers (the integration test fixtures, the parity test
  /// against the pre-29 fixture) still compile and produce the same
  /// numbers via the documented backward-compat path. Production callers
  /// (the live save path) live in SQL, not Dart — the Dart calculator
  /// exists for parity testing + offline scenarios.
  static SetXpComponents computeSetXp({
    required double weightKg,
    required int reps,
    required double peakLoad,
    required double sessionVolumeForBodyPart,
    required double weeklyVolumeForBodyPart,
    required double difficultyMult,
    // Phase 29 v2 — all optional / neutral defaults.
    double impliedTier = 0.0,
    double currentRank = 1.0,
    double? priorBandWeight,
    int? priorBandReps,
    int sessionsThisWeekForBodyPart = 1,
    bool nearFailure = false,
    int? targetReps,
  }) {
    final vl = volumeLoad(weightKg: weightKg, reps: reps);
    final base = baseXp(vl);
    // Phase 29 v2: infer near-failure if not explicitly set and we have
    // a target reps signal.
    final nfResolved =
        nearFailure ||
        nearFailureInferred(actualReps: reps, targetReps: targetReps);
    final intensity = intensityWithNearFailure(
      reps: reps,
      nearFailure: nfResolved,
    );
    final strength = strengthMult(weightKg: weightKg, peakLoad: peakLoad);
    final novelty = noveltyMult(sessionVolumeForBodyPart);
    final cap = capMult(weeklyVolumeForBodyPart);
    final tdMult = tierDiffMult(
      impliedTier: impliedTier,
      currentRank: currentRank,
    );
    final aspMult = absStrengthPremium(impliedTier);
    final oMult = overloadMult(
      weightKg: weightKg,
      reps: reps,
      priorWeight: priorBandWeight,
      priorReps: priorBandReps,
    );
    final fMult = frequencyMult(sessionsThisWeekForBodyPart);
    final setXp =
        base *
        intensity *
        strength *
        novelty *
        cap *
        difficultyMult *
        tdMult *
        aspMult *
        oMult *
        fMult;
    return SetXpComponents(
      volumeLoad: vl,
      baseXp: base,
      intensityMult: intensity,
      strengthMult: strength,
      noveltyMult: novelty,
      capMult: cap,
      difficultyMult: difficultyMult,
      tierDiffMult: tdMult,
      absStrengthPremium: aspMult,
      overloadMult: oMult,
      frequencyMult: fMult,
      impliedTier: impliedTier,
      nearFailureResolved: nfResolved,
      setXp: setXp,
    );
  }
}

/// The decomposed XP for a single set — Phase 29 v2 + 29.6.
///
/// Plain value class — kept out of Freezed because it lives entirely in
/// memory between `computeSetXp` and the repository INSERT. The JSON
/// shape mirrors the SQL `xp_events.payload` keys (in the same chain
/// order so the on-disk form reads top-to-bottom like the multiplication).
class SetXpComponents {
  const SetXpComponents({
    required this.volumeLoad,
    required this.baseXp,
    required this.intensityMult,
    required this.strengthMult,
    required this.noveltyMult,
    required this.capMult,
    required this.difficultyMult,
    required this.tierDiffMult,
    required this.absStrengthPremium,
    required this.overloadMult,
    required this.frequencyMult,
    required this.impliedTier,
    required this.nearFailureResolved,
    required this.setXp,
  });

  final double volumeLoad;
  final double baseXp;
  final double intensityMult;
  final double strengthMult;
  final double noveltyMult;
  final double capMult;
  final double difficultyMult;

  /// Phase 29 v2 Refinement #1 — punch-above-current-rank reward.
  final double tierDiffMult;

  /// Phase 29.6 Path C — absolute strength premium.
  final double absStrengthPremium;

  /// Phase 29 v2 Refinement #2 — in-band overload reward.
  final double overloadMult;

  /// Phase 29 v2 Refinement #3 — 7d frequency reward.
  final double frequencyMult;

  /// Phase 29 v2 — interpolated lift-implied tier in `[0.0, 70.0]`.
  final double impliedTier;

  /// Phase 29 v2 Refinement #4 — whether the set was treated as
  /// near-failure (either explicit or inferred from target_reps).
  final bool nearFailureResolved;

  /// The total XP for this set, **before** distribution to body parts.
  final double setXp;

  /// Serialized for `xp_events.payload`. Mirrors the field set the SQL
  /// RPC stores so a Dart-driven backfill produces byte-identical rows
  /// to the live save path. Keys appear in formula-chain order.
  Map<String, dynamic> toJson() => {
    'volume_load': volumeLoad,
    'base_xp': baseXp,
    'intensity_mult': intensityMult,
    'strength_mult': strengthMult,
    'novelty_mult': noveltyMult,
    'cap_mult': capMult,
    'difficulty_mult': difficultyMult,
    'tier_diff_mult': tierDiffMult,
    'abs_strength_premium': absStrengthPremium,
    'overload_mult': overloadMult,
    'frequency_mult': frequencyMult,
    'implied_tier': impliedTier,
    'near_failure': nearFailureResolved,
    'set_xp': setXp,
  };
}
