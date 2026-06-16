import 'cardio_xp_calculator.dart';

/// est-VO₂max chain — Phase 38c §A (app-only; NOT in the scored formula).
///
/// Produces the per-user `standing_vo2max` (mL·kg⁻¹·min⁻¹) that feeds the
/// session's relative-intensity term and is persisted on
/// `profiles.cardio_vo2max`. The chain is an *input derivation*, so it lives
/// outside the parity oracle EXCEPT for its two pure cores
/// ([bestEffortVo2FromPace] and [nonexerciseSeedVo2]), which are pinned by the
/// `est_vo2max_cases` fixture section so Dart matches Python exactly. The
/// rolling best-of-window ([rollingStandingVo2max]) is stateful/temporal and
/// covered by Dart + SQL unit/integration tests, not the fixture.
///
/// Keep this strictly separate from the session's `demonstrated_vo2` (which
/// drives the tier burst): [bestEffortVo2FromPace] is mathematically *equal*
/// to `demonstrated_vo2(acsm_vo2/3.5, dur)`, but it updates the standing
/// estimate — it is NOT the per-session tier signal.
///
/// Mirrors `tasks/cardio-xp-simulation.py`:
///   * [bestEffortVo2FromPace] ↔ `best_effort_vo2_from_pace`
///   * [nonexerciseSeedVo2]    ↔ `nonexercise_seed_vo2`
///   * [sessionMetFromCardioLog] ↔ `session_met_from_cardio_log`
class EstVo2max {
  const EstVo2max._();

  /// Modalities for which logged distance is interpretable as pace → VO₂ via
  /// the ACSM *running* equation (A1). Bike/row/swim need separate equations →
  /// duration-only for estimation in v1.
  static const Set<String> distanceModalities = {'run', 'treadmill'};

  /// Per-modality ACSM table-average MET for a logged session WITHOUT a
  /// pace-derived MET (duration-only, or a non-distance modality). The honest
  /// "activity type → ACSM MET value" basis. Never user-declared; RPE is NOT
  /// used for MET. Unknown modality → [CardioXpCalculator.metRest] (1 MET unit
  /// floor at rest level, matching the sim default).
  static const Map<String, double> cardioDefaultMet = {
    'run': 9.8,
    'treadmill': 9.8,
    'bike': 7.0,
    'row': 8.5,
    'swim': 8.0,
    'elliptical': 7.0,
    'walk': 3.8,
    'hiit': 11.0,
  };

  /// Cardio exercise slug → sim modality (the 5 default cardio slugs from
  /// migration 00014). Unknown / user-created slugs resolve to [unknownModality]
  /// ('other') via [modalityForSlug] — a NON-distance modality on purpose, so a
  /// custom slug logged with a distance is NOT pace-scored by the ACSM running
  /// equation (it would over/under-credit an arbitrary activity). Mirrors the
  /// SQL `rpg_cardio_slug_to_modality` ELSE branch.
  static const Map<String, String> slugToModality = {
    'treadmill': 'treadmill',
    'rowing_machine': 'row',
    'stationary_bike': 'bike',
    'jump_rope': 'hiit',
    'elliptical': 'elliptical',
  };

  /// Neutral fallback modality for unrecognized slugs — non-distance, so
  /// distance never feeds the pace equation; falls to the table-average MET
  /// path (via [cardioDefaultMet]'s `?? metRest`) and skips best-effort VO₂.
  static const String unknownModality = 'other';

  /// Resolves a cardio slug to a sim modality, defaulting unknown slugs to the
  /// non-distance [unknownModality]. Mirrors `rpg_cardio_slug_to_modality`.
  static String modalityForSlug(String slug) =>
      slugToModality[slug] ?? unknownModality;

  /// A1 best-effort est-VO₂max from a logged run/treadmill session.
  ///
  /// velocity → ACSM horizontal-running VO₂ (grade=0) → back-project via
  /// [CardioXpCalculator.sustainableFraction]. Returns null for non-distance
  /// modalities or missing/non-positive inputs (the standing estimate is left
  /// unchanged that session).
  ///
  /// This is EXACTLY `demonstrated_vo2(acsm_vo2/3.5, dur)` — one code path,
  /// reused — but with abs_met derived from MEASURED pace, not an estimate.
  static double? bestEffortVo2FromPace({
    required double? distanceM,
    required double? durationS,
    required String modality,
  }) {
    if (!distanceModalities.contains(modality)) return null;
    if (distanceM == null ||
        durationS == null ||
        distanceM <= 0 ||
        durationS <= 0) {
      return null;
    }
    final durationMin = durationS / 60.0;
    final vMPerMin = distanceM / durationMin;
    final acsmVo2 =
        0.2 * vMPerMin + CardioXpCalculator.metRest; // ACSM running, grade=0
    final raw = acsmVo2 / CardioXpCalculator.sustainableFraction(durationMin);
    return raw < CardioXpCalculator.vo2CeilingCap
        ? raw
        : CardioXpCalculator.vo2CeilingCap;
  }

  /// A3 cold-start seed: the p25 ("below-median untrained") anchor of the
  /// user's (sex, age_band) VO₂ norm. Conservative prior — first real efforts
  /// can only raise it. [age] null → [CardioXpCalculator.ageFallback].
  static double nonexerciseSeedVo2({required int? age, required bool female}) {
    final a = age ?? CardioXpCalculator.ageFallback;
    final sex = female ? 'F' : 'M';
    return CardioXpCalculator.vo2Norms[(sex, _ageBand(a))]![1]; // p25 anchor
  }

  /// D6 session resolution: a logged cardio session → absolute MET.
  ///
  /// run/treadmill WITH distance → pace-derived MET (`acsm_vo2 / 3.5`).
  /// otherwise → per-modality ACSM table-average MET ([cardioDefaultMet]).
  /// Always `kind='abs'` for a logged session. Never user-declared.
  static double sessionMetFromCardioLog({
    required String modality,
    required double? distanceM,
    required double? durationS,
  }) {
    if (distanceModalities.contains(modality) &&
        distanceM != null &&
        distanceM > 0 &&
        durationS != null &&
        durationS > 0) {
      final vMPerMin = distanceM / (durationS / 60.0);
      final acsmVo2 = 0.2 * vMPerMin + CardioXpCalculator.metRest;
      return acsmVo2 / CardioXpCalculator.metRest;
    }
    return cardioDefaultMet[modality] ?? CardioXpCalculator.metRest;
  }

  /// A4 rolling standing estimate: best-of trailing window, floored at the
  /// non-exercise seed.
  ///
  /// `standing = max(seed, max(best_effort over qualifying sessions in the
  /// trailing 42 days))`. The standing estimate is NEVER lowered *within* the
  /// window (best-of); it only drops when the best qualifying session ages out
  /// — exactly the Coyle-detraining shape the Vitality layer encodes. Sessions
  /// with no qualifying best-effort (duration-only / non-distance) contribute
  /// nothing and do not lower the estimate.
  ///
  /// [qualifyingBestEfforts] is the list of [bestEffortVo2FromPace] results for
  /// sessions inside the window (callers pre-filter by date and drop nulls).
  static double rollingStandingVo2max({
    required double seedVo2,
    required Iterable<double> qualifyingBestEfforts,
  }) {
    var best = seedVo2;
    for (final v in qualifyingBestEfforts) {
      if (v > best) best = v;
    }
    return best;
  }

  static int _ageBand(int age) {
    final decade = (age ~/ 10) * 10;
    if (decade < 20) return 20;
    if (decade > 70) return 70;
    return decade;
  }
}

/// Cross-credit (strength → cardio) — Phase 38c §B (app-only; parity-checked
/// pure core).
///
/// Derives an ACSM resistance-training MET band from a strength session's work
/// density. The result feeds the cardio pipeline as a `kind='abs'` entry — it
/// NEVER touches the strength formula (one-directional; the structural gate is
/// in migration 00077). All thresholds are on estimated/planned signals, never
/// user-declared: "I did a hard workout" cannot move the MET.
///
/// Mirrors `tasks/cardio-xp-simulation.py::est_met_from_density`.
class CrossCredit {
  const CrossCredit._();

  /// §B work-density → ACSM RT MET band ∈ {3.5, 5.0, 6.0, 8.0}, evaluated
  /// top-down (first match wins). Uses the CORRECTED §B decision function:
  /// the 8.0 band gates on rest+cadence, NOT density, so a wall-clock-bound
  /// metcon isn't under-shot.
  ///
  /// `sets_per_min = completed_sets / (session_seconds / 60)`.
  static double estMetFromDensity({
    required int completedSets,
    required double sessionSeconds,
    required double avgRest,
  }) {
    if (completedSets <= 0 || sessionSeconds <= 0) return 3.5;
    final setsPerMin = completedSets / (sessionSeconds / 60.0);
    if (avgRest <= 35 && setsPerMin >= 0.50) return 8.0; // dense circuit/metcon
    if (avgRest <= 75 && setsPerMin >= 0.40) return 6.0; // vigorous PL/BB
    if (avgRest <= 120) return 5.0; // vigorous free-weight
    return 3.5; // light/moderate, long rest
  }
}
