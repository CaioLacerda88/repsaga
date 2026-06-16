import 'dart:math' as math;

import 'implied_tier.dart' show tierDiffMult;

/// Pure cardio-session XP calculator — Phase 38c LOCKED (v1).
///
/// Mirrors the canonical Python simulator at `tasks/cardio-xp-simulation.py`
/// and the SQL RPC `record_cardio_session` (migration 00079+). **If you change
/// a constant here, change the Python sim, the fixture generator
/// (`test/fixtures/generate_rpg_fixtures.py`), and the PL/pgSQL
/// `record_cardio_session` RPC in the same PR.** All four sites are checked
/// for parity by the integration + parity tests at 1e-4 (Dart↔Python) and
/// 0.01 (SQL live-row↔Dart) absolute.
///
/// Cardio is dimensionally distinct from strength (rate × time, not load), so
/// it does NOT reuse the weight×reps chain. It REUSES two things for
/// consistency with the strength system:
///
///   1. The shared piecewise rank curve ([RankCurve.rankForXp]) so a cardio
///      rank feels like a strength rank.
///   2. The `tier_diff_mult` capacity-chases-rank mechanic
///      ([tierDiffMult] from `implied_tier.dart`) — imported, NOT re-ported.
///
/// Formula (the chain `computeSessionXp` returns is per-session total, before
/// the caller-applied Vitality XP multiplier):
///
/// ```
/// (abs_met, rel) = session_met_and_intensity(vo2max, kind, value)
/// met_minutes    = abs_met × duration_min
/// eff_met_min    = met_minutes × intensity_mult(rel)
/// capped_met_min = weekly-cap split at 2500 (over-portion × 0.30)
/// base_xp        = capped_met_min ^ 0.60
/// demonstrated   = demonstrated_vo2(abs_met, duration_min)
/// tier           = implied_cardio_tier(demonstrated, age, female)
/// session_xp     = base_xp × tier_diff_mult(current_rank, tier)
///                          × modality_mult(modality) × 3.5
/// ```
///
/// ## Honesty guarantee (the thesis veto)
///
/// `tier` is what the session DEMONSTRATED (sustained MET back-projected via
/// the duration held), NOT the user's standing capacity — exactly as strength
/// credits the lift, not the lifter. A walk demonstrates ~walking-level VO₂ for
/// ANYONE → low tier → low rank credit. You cannot fake cardio rank.
///
/// ## Session resolution (sub-decision D6)
///
/// A logged `cardio_session` always resolves as `kind='abs'`. `abs_met` is
/// derived from the activity, never user-declared (RPE is NOT used for MET):
///   * run/treadmill WITH distance → pace-derived MET (ACSM running eq / 3.5)
///   * otherwise (duration-only, or non-distance modality) → per-modality ACSM
///     table-average MET ([cardioDefaultMet]).
/// See [sessionMetFromCardioLog].
class CardioXpCalculator {
  const CardioXpCalculator._();

  // ---- shared constants (verbatim from the strength baseline) --------------

  /// `base_xp = capped_met_minutes ^ 0.60` — shared sub-linear volume
  /// exponent (mirrors `volume_load^0.60`).
  static const double volumeExponent = 0.60;

  // ---- cardio-specific constants (v1 — calibrated on the 14-persona panel) --

  /// 1 MET = 3.5 mL O₂ / kg / min (ACSM).
  static const double metRest = 3.5;

  /// Calibrates the cardio "currency" (MET-min) onto the shared rank curve.
  static const double cardioXpScale = 3.5;

  /// Weekly intensity-weighted MET-min beyond which extra volume is heavily
  /// discounted (anti-grind). Anchored well above the WHO 500-1000 band.
  static const double weeklyCardioCapMetMin = 2500.0;

  /// Multiplier on the portion of weekly MET-min above [weeklyCardioCapMetMin].
  static const double overCapMult = 0.30;

  /// Genetic ceiling for VO₂max (practical human max ~90). Caps demonstrated
  /// VO₂ and best-effort estimates.
  static const double vo2CeilingCap = 90.0;

  // ---- est-VO₂max chain constants (Phase 38c §A) ---------------------------

  /// Median adult age — used when `profiles.date_of_birth` is NULL.
  static const int ageFallback = 35;

  /// Best-of trailing window for the rolling standing estimate (6 wk ≈
  /// 2 × τ_down).
  static const int vo2RollingWindowDays = 42;

  // ---- cross-credit constants (Phase 38c §B) -------------------------------

  /// Estimated work-under-tension per completed set (~8-12 rep set).
  /// Cross-credit-only; never touches strength XP.
  static const int setWorkSeconds = 30;

  /// Default inter-set rest when `workout_exercises.rest_seconds` is NULL.
  /// Cross-credit-only.
  static const int restDefault = 90;

  // ---- modality normalization ----------------------------------------------

  /// Reference = running 1.00. Whole-body/weight-bearing modalities elicit
  /// higher VO₂ at a matched %effort; resistance modalities are penalized
  /// (less central-cardiovascular-specific). Unknown modality → 1.00.
  static const Map<String, double> modalityMult = {
    'run': 1.00,
    'treadmill': 1.00,
    'row': 1.00,
    'swim': 1.00,
    'elliptical': 0.97,
    'bike': 0.95,
    'walk': 0.95,
    'hiit': 1.05,
    'strength': 0.80,
    'circuit': 0.90,
  };

  static double modalityMultFor(String modality) =>
      modalityMult[modality] ?? 1.00;

  // ---- intensity multiplier vs %VO₂max -------------------------------------

  /// Piecewise-linear anchors `(pct_vo2max, mult)` — Wenger & Bell: <~50% ≈
  /// maintenance, 90-100% = max-gain band. Clamped at both ends.
  static const List<(double, double)> intensityAnchors = [
    (0.35, 0.05),
    (0.50, 0.35),
    (0.70, 0.75),
    (0.85, 1.05),
    (0.95, 1.35),
    (1.05, 1.45),
  ];

  static double intensityMult(double pctVo2max) =>
      _interp(intensityAnchors, pctVo2max);

  // ---- sustainable fraction vs duration ------------------------------------

  /// Sustainable fraction of VO₂max by effort duration (velocity-duration /
  /// critical-power curve): ~100% for ~6 min, ~80% for ~60 min, etc. Turns a
  /// sustained MET into a demonstrated VO₂max.
  static const List<(double, double)> sustainAnchors = [
    (6, 1.00),
    (15, 0.93),
    (30, 0.88),
    (45, 0.84),
    (60, 0.80),
    (90, 0.76),
    (120, 0.74),
    (180, 0.70),
  ];

  static double sustainableFraction(double durationMin) =>
      _interp(sustainAnchors, durationMin);

  // ---- VO₂max → percentile → cardio tier (ACSM / Cooper norms) -------------

  /// VO₂max (mL/kg/min) at percentiles [5, 25, 50, 75, 90, 95] by sex × age
  /// decade. Keyed `(sex, decade)` where sex ∈ {'M','F'}.
  static const Map<(String, int), List<double>> vo2Norms = {
    ('M', 20): [29.0, 40.1, 48.0, 55.2, 61.8, 66.3],
    ('M', 30): [27.2, 35.9, 42.4, 49.2, 56.5, 59.8],
    ('M', 40): [24.2, 31.9, 37.8, 45.0, 52.1, 55.6],
    ('M', 50): [20.9, 27.1, 32.6, 39.7, 45.6, 50.7],
    ('M', 60): [17.4, 23.7, 28.2, 34.5, 40.3, 43.0],
    ('M', 70): [16.3, 20.4, 24.4, 30.4, 36.6, 39.7],
    ('F', 20): [21.7, 30.5, 37.6, 44.7, 51.3, 56.0],
    ('F', 30): [19.0, 25.3, 30.2, 36.1, 41.4, 45.8],
    ('F', 40): [17.0, 22.1, 26.7, 32.4, 38.4, 41.7],
    ('F', 50): [16.0, 19.9, 23.4, 27.6, 32.0, 35.9],
    ('F', 60): [13.4, 17.2, 20.0, 23.8, 27.0, 29.4],
    ('F', 70): [13.1, 15.6, 18.3, 20.8, 23.1, 24.1],
  };

  static const List<double> _pcts = [5, 25, 50, 75, 90, 95];

  /// percentile → cardio tier [0,70] (mirrors strength implied_tier scale).
  static const List<(double, double)> tierAnchors = [
    (0, 0),
    (5, 5),
    (25, 18),
    (50, 25),
    (75, 37),
    (90, 50),
    (95, 60),
    (99, 68),
    (100, 70),
  ];

  static int _ageBand(int age) {
    final decade = (age ~/ 10) * 10;
    if (decade < 20) return 20;
    if (decade > 70) return 70;
    return decade;
  }

  static double vo2ToPercentile(double vo2, int age, bool female) {
    final sex = female ? 'F' : 'M';
    final norms = vo2Norms[(sex, _ageBand(age))]!;
    // (vo2, pct) ascending in vo2, bracketed by (0,0) and (ceiling, 100).
    final anchors = <(double, double)>[
      (0.0, 0.0),
      for (var i = 0; i < norms.length; i++) (norms[i], _pcts[i]),
      (vo2CeilingCap, 100.0),
    ];
    return _interp(anchors, vo2);
  }

  /// Estimated VO₂max → sex/age percentile → cardio tier [0,70].
  static double impliedCardioTier(double vo2, int age, bool female) =>
      _interp(tierAnchors, vo2ToPercentile(vo2, age, female));

  /// What VO₂max this session *demonstrates*: sustained VO₂ (MET×3.5)
  /// back-projected to a max via the duration held. This is what the rank
  /// credits — like strength credits the lift, not the lifter.
  static double demonstratedVo2(double absMet, double durationMin) {
    final raw = (absMet * metRest) / sustainableFraction(durationMin);
    return raw < vo2CeilingCap ? raw : vo2CeilingCap;
  }

  // ---- session resolution + intensity --------------------------------------

  /// Resolve a logged session to `(absolute_MET, relative_intensity)`.
  ///
  /// `kind='abs'` (walking, fixed machine settings): absolute MET is fixed;
  /// `rel = MET×3.5/VO₂max` falls as the user gets fitter (clamped ≤ 1.20).
  /// `kind='rel'` (self-paced effort): the user picks the relative effort; a
  /// fitter athlete runs faster so `abs_met = rel × VO₂max / 3.5`.
  static (double absMet, double rel) sessionMetAndIntensity(
    double vo2max,
    String kind,
    double value,
  ) {
    if (kind == 'abs') {
      final absMet = value;
      final rel = math.min(1.20, (absMet * metRest) / vo2max);
      return (absMet, rel);
    }
    final rel = value;
    final absMet = (rel * vo2max) / metRest;
    return (absMet, rel);
  }

  /// Per-session XP. Returns the decomposed [CardioXpComponents].
  ///
  /// [weekUsedMetMin] is the intensity-weighted MET-min already accrued this
  /// week (for the cap split); [CardioXpComponents.weekUsedAfter] reports the
  /// post-session total the caller persists. The Vitality XP multiplier is
  /// applied by the caller (computed once per week), exactly as the sim's
  /// `simulate_cardio` applies `vmult` outside `compute_session_xp`.
  static CardioXpComponents computeSessionXp({
    required double vo2max,
    required int age,
    required bool female,
    required String modality,
    required double durationMin,
    required String kind,
    required double value,
    required double currentRank,
    double weekUsedMetMin = 0.0,
  }) {
    final (absMet, rel) = sessionMetAndIntensity(vo2max, kind, value);
    final metMin = absMet * durationMin;
    final imult = intensityMult(rel);
    final effMetMin = metMin * imult;

    // Weekly diminishing returns (split the portion over the cap).
    final remaining = math.max(0.0, weeklyCardioCapMetMin - weekUsedMetMin);
    final under = math.min(effMetMin, remaining);
    final over = effMetMin - under;
    final cappedMetMin = under + over * overCapMult;
    final weekUsedAfter = weekUsedMetMin + effMetMin;

    final baseXp = math.pow(cappedMetMin, volumeExponent).toDouble();
    final dvo2 = demonstratedVo2(absMet, durationMin);
    final tier = impliedCardioTier(dvo2, age, female);
    final tdm = tierDiffMult(impliedTier: tier, currentRank: currentRank);
    final mod = modalityMultFor(modality);
    final xp = baseXp * tdm * mod * cardioXpScale;

    return CardioXpComponents(
      absMet: absMet,
      relIntensity: rel,
      metMinutes: metMin,
      intensityMult: imult,
      effMetMin: effMetMin,
      cappedMetMin: cappedMetMin,
      weekUsedAfter: weekUsedAfter,
      baseXp: baseXp,
      demonstratedVo2: dvo2,
      impliedTier: tier,
      tierDiffMult: tdm,
      modalityMult: mod,
      sessionXp: xp,
    );
  }

  // ---- shared interpolation helper -----------------------------------------

  /// Piecewise-linear interpolation over `(x, y)` anchors, clamped at the ends.
  static double _interp(List<(double, double)> anchors, double x) {
    if (x <= anchors.first.$1) return anchors.first.$2;
    if (x >= anchors.last.$1) return anchors.last.$2;
    for (var i = 0; i < anchors.length - 1; i++) {
      final (x0, y0) = anchors[i];
      final (x1, y1) = anchors[i + 1];
      if (x0 <= x && x <= x1) {
        final t = (x - x0) / (x1 - x0);
        return y0 + t * (y1 - y0);
      }
    }
    return anchors.last.$2;
  }
}

/// The decomposed XP for a single cardio session — Phase 38c.
///
/// Plain value class — mirrors [CardioXpComponents.toJson] against the cardio
/// `xp_events.payload` keys so a Dart-driven computation reads byte-identical
/// to the live SQL save path. Keys appear in formula-chain order.
class CardioXpComponents {
  const CardioXpComponents({
    required this.absMet,
    required this.relIntensity,
    required this.metMinutes,
    required this.intensityMult,
    required this.effMetMin,
    required this.cappedMetMin,
    required this.weekUsedAfter,
    required this.baseXp,
    required this.demonstratedVo2,
    required this.impliedTier,
    required this.tierDiffMult,
    required this.modalityMult,
    required this.sessionXp,
  });

  /// Resolved absolute MET for the session.
  final double absMet;

  /// Relative intensity `MET×3.5 / VO₂max` (clamped ≤ 1.20 for `kind='abs'`).
  final double relIntensity;

  /// `abs_met × duration_min` — raw (un-intensity-weighted) MET-minutes.
  final double metMinutes;

  /// `intensity_mult(rel_intensity)`.
  final double intensityMult;

  /// `met_minutes × intensity_mult` — intensity-weighted volume (feeds the
  /// weekly cap accumulator).
  final double effMetMin;

  /// Post-weekly-cap-split MET-min that feeds `base_xp`.
  final double cappedMetMin;

  /// Weekly intensity-weighted MET-min after this session (caller persists).
  final double weekUsedAfter;

  /// `capped_met_min ^ 0.60`.
  final double baseXp;

  /// What VO₂max this session demonstrated (drives [impliedTier]).
  final double demonstratedVo2;

  /// Demonstrated VO₂ → sex/age percentile → cardio tier [0,70].
  final double impliedTier;

  /// Capacity-chases-rank burst (imported from the strength domain).
  final double tierDiffMult;

  /// Modality normalization multiplier.
  final double modalityMult;

  /// The total XP for this session, **before** the caller-applied Vitality
  /// multiplier.
  final double sessionXp;

  /// Serialized for the cardio `xp_events.payload`. Keys in formula-chain
  /// order so the on-disk form reads top-to-bottom like the multiplication.
  Map<String, dynamic> toJson() => {
    'abs_met': absMet,
    'rel_intensity': relIntensity,
    'met_minutes': metMinutes,
    'intensity_mult': intensityMult,
    'eff_met_min': effMetMin,
    'capped_met_min': cappedMetMin,
    'base_xp': baseXp,
    'demonstrated_vo2': demonstratedVo2,
    'implied_tier': impliedTier,
    'tier_diff_mult': tierDiffMult,
    'modality_mult': modalityMult,
    'session_xp': sessionXp,
  };
}
