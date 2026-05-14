import 'dart:math' as math;

/// Pure XP-per-set calculator (RPG v1).
///
/// Mirrors the canonical Python simulator at `tasks/rpg-xp-simulation.py`.
/// **If you change a constant here, change the Python sim, the fixture
/// generator (`test/fixtures/generate_rpg_fixtures.py`), and the PL/pgSQL
/// `record_set_xp` RPC in the same PR.** All three paths are checked for
/// parity by the integration tests.
///
/// Formula (spec §4 + Phase 24a difficulty_mult — see
/// `docs/xp-difficulty-framework.md` §6):
///
/// ```
/// set_xp = volume_load^0.65
///        × intensity_mult(reps)
///        × strength_mult(weight, peak)
///        × novelty_mult(session_volume)
///        × cap_mult(weekly_volume)
///        × difficulty_mult(exercise)
/// ```
///
/// `difficulty_mult` is per-exercise data sourced from
/// `exercises.difficulty_mult` (numeric, range [0.85, 1.25] enforced by a
/// SQL CHECK constraint). The Dart calculator does NOT compute the
/// composite (tier_mult + secondary bump); it receives the pre-clamped
/// composite value from the caller and multiplies. User-created exercises
/// without an explicit assignment default to 1.0 at the column level.
///
/// This is the **total** XP for the set, before per-body-part attribution.
/// Distribution to body parts happens in `xp_distribution.dart`.
class XpCalculator {
  const XpCalculator._();

  // ---- tunable constants ---------------------------------------------------

  /// Sub-linear volume exponent. 10× volume produces ~4.5× XP, not 10×.
  /// Empirically chosen so a junk-volume session can't outrun a heavy session.
  static const double volumeExponent = 0.65;

  /// τ for novelty diminishing returns within a session, in attributed sets.
  /// After ~15 sets attributed to a body part, the next set earns e^-1 ≈ 37 %
  /// of base XP.
  static const double noveltyDenominator = 15.0;

  /// Effective sets per body part in a 7-day rolling window before the cap
  /// halves further XP for that body part.
  static const double weeklyCapSets = 20.0;

  /// Multiplier applied to set_xp once `weekly_volume_for_body_part`
  /// crosses [weeklyCapSets].
  static const double overCapMultiplier = 0.5;

  /// Floor of the per-exercise `difficulty_mult` range.
  ///
  /// Documented for parity with the migration's CHECK constraint
  /// (`difficulty_mult BETWEEN 0.85 AND 1.25`). The calculator does NOT
  /// enforce this clamp itself — the source-of-truth is the SQL constraint
  /// and the Phase 24a curated UPDATE block. If a value outside this range
  /// reaches `computeSetXp`, that's a data-integrity bug to fix upstream,
  /// not silently clip here.
  static const double difficultyMultFloor = 0.85;

  /// Ceiling of the per-exercise `difficulty_mult` range. See
  /// [difficultyMultFloor] for enforcement notes.
  static const double difficultyMultCeiling = 1.25;

  /// Floor for the strength multiplier. A 50 % deload still earns
  /// `0.5 × set_xp`; below 40 % we floor to 0.4 — recovery sets still count,
  /// but for token amounts.
  static const double strengthMultFloor = 0.4;

  /// Volume floor — bodyweight beginners never produce zero base XP.
  static const double volumeLoadFloor = 1.0;

  // ---- intensity table -----------------------------------------------------

  /// Reps → multiplier table (spec §4.1). Lookup is **reps-floor**:
  /// 4 reps falls into the `reps >= 3` row → 1.25.
  ///
  /// Stored as parallel const lists so the calculator stays a hot-path-safe
  /// pure function (no Map allocation per set).
  static const List<int> _intensityRepsBoundaries = [1, 3, 5, 8, 12, 15, 20];
  static const List<double> _intensityMultipliers = [
    1.30, // reps >= 1 (fallback if reps > 0)
    1.25, // reps >= 3
    1.20, // reps >= 5
    1.00, // reps >= 8 (baseline hypertrophy)
    0.95, // reps >= 12
    0.90, // reps >= 15
    0.80, // reps >= 20+
  ];

  /// Returns the intensity multiplier for [reps].
  ///
  /// Reps below 1 (e.g. zero or negative) fall back to 1.0 — defensive only;
  /// callers should validate at the model layer. Reps `>= 20` saturate at 0.8.
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

  // ---- volume + base -------------------------------------------------------

  /// `volume_load = max(1.0, weight_kg × reps)`.
  ///
  /// The floor ensures bodyweight exercises (weight = 0) still produce a
  /// computable base. Negative/zero reps return the floor.
  static double volumeLoad({required double weightKg, required int reps}) {
    if (reps < 1) return volumeLoadFloor;
    final raw = weightKg * reps;
    return raw < volumeLoadFloor ? volumeLoadFloor : raw;
  }

  /// `base_xp = volume_load^0.65`.
  static double baseXp(double volumeLoad) {
    return math.pow(volumeLoad, volumeExponent).toDouble();
  }

  // ---- strength multiplier -------------------------------------------------

  /// `strength_mult = clamp(weight / peak, 0.40, 1.00)`.
  ///
  /// Special case: when `peak <= 0` (no prior peak recorded), we return
  /// 1.0. Repository code is responsible for **advancing** the peak when
  /// `weight > peak`; this calculator does not mutate state.
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
  ///
  /// `sessionVolumeForBodyPart` is the running sum of `attribution[bp]` for
  /// every prior set in the session that touched this body part (a
  /// fractional count — a 0.7-attribution bench set adds 0.7, not 1.0).
  static double noveltyMult(double sessionVolumeForBodyPart) {
    if (sessionVolumeForBodyPart <= 0) return 1.0;
    return math.exp(-sessionVolumeForBodyPart / noveltyDenominator);
  }

  // ---- cap -----------------------------------------------------------------

  /// `cap_mult = 0.5 if weekly_volume >= 20 else 1.0`. (Strict `>=`.)
  ///
  /// `weeklyVolumeForBodyPart` is the rolling 7-day sum of
  /// `attribution[bp]` over completed sets — same fractional semantics as
  /// novelty.
  static double capMult(double weeklyVolumeForBodyPart) {
    return weeklyVolumeForBodyPart >= weeklyCapSets ? overCapMultiplier : 1.0;
  }

  // ---- end-to-end ----------------------------------------------------------

  /// Component breakdown for a single set. Returned by [computeSetXp] so
  /// callers can persist the breakdown for analytics / debugging while
  /// staying pure (no IO).
  ///
  /// The integration test asserts that the SQL `record_set_xp` RPC produces
  /// a row whose breakdown matches this struct within 0.0001 absolute.
  ///
  /// All fields are in the same order as the formula multiplication chain.
  static SetXpComponents computeSetXp({
    required double weightKg,
    required int reps,
    required double peakLoad,
    required double sessionVolumeForBodyPart,
    required double weeklyVolumeForBodyPart,
    required double difficultyMult,
  }) {
    final vl = volumeLoad(weightKg: weightKg, reps: reps);
    final base = baseXp(vl);
    final intensity = intensityForReps(reps);
    final strength = strengthMult(weightKg: weightKg, peakLoad: peakLoad);
    final novelty = noveltyMult(sessionVolumeForBodyPart);
    final cap = capMult(weeklyVolumeForBodyPart);
    final setXp = base * intensity * strength * novelty * cap * difficultyMult;
    return SetXpComponents(
      volumeLoad: vl,
      baseXp: base,
      intensityMult: intensity,
      strengthMult: strength,
      noveltyMult: novelty,
      capMult: cap,
      difficultyMult: difficultyMult,
      setXp: setXp,
    );
  }
}

/// The decomposed XP for a single set.
///
/// Plain value class — kept out of Freezed because it lives entirely in
/// memory between `computeSetXp` and the repository INSERT. Persisting the
/// JSON shape is the repository's job; the breakdown that goes into
/// `xp_events.payload` is built from these fields.
class SetXpComponents {
  const SetXpComponents({
    required this.volumeLoad,
    required this.baseXp,
    required this.intensityMult,
    required this.strengthMult,
    required this.noveltyMult,
    required this.capMult,
    required this.difficultyMult,
    required this.setXp,
  });

  final double volumeLoad;
  final double baseXp;
  final double intensityMult;
  final double strengthMult;
  final double noveltyMult;
  final double capMult;
  final double difficultyMult;

  /// The total XP for this set, **before** distribution to body parts.
  final double setXp;

  /// Serialized for `xp_events.payload`. Mirrors the field set the SQL RPC
  /// stores so a Dart-driven backfill produces byte-identical rows to the
  /// live save path. Keys appear in formula-chain order so the JSON shape
  /// reads top-to-bottom like the multiplication chain.
  Map<String, dynamic> toJson() => {
    'volume_load': volumeLoad,
    'base_xp': baseXp,
    'intensity_mult': intensityMult,
    'strength_mult': strengthMult,
    'novelty_mult': noveltyMult,
    'cap_mult': capMult,
    'difficulty_mult': difficultyMult,
    'set_xp': setXp,
  };
}
