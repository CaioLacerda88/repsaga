import 'dart:math' as math;

/// Vitality EWMA (spec §8).
///
/// Asymmetric exponentially-weighted moving average on weekly volume per
/// body part. Rebuilds fast (τ_up = 14 days), decays slow (τ_down = 42 days
/// for the six strength tracks) — empirically grounded in myonuclear
/// retention literature (Bruusgaard 2010, Seaborne 2018, Psilander 2019).
///
/// **Two-speed decay (Phase 38e).** Cardiorespiratory conditioning detrains
/// FASTER than skeletal-muscle hypertrophy — VO2max losses are measurable
/// within ~2 weeks of cessation (Coyle 1984; Mujika & Padilla 2000) versus
/// the ~6-week myonuclear-retention floor for strength. The decay time
/// constant is therefore PER-BODY-PART: cardio uses [tauDownCardioDays]
/// (21d / ~3wk), the six strength tracks keep [tauDownStrengthDays] (42d /
/// ~6wk). τ_up is shared — retraining speed is the same fast-rebuild story
/// for both. **Never copy a τ between stats** — pass the body part's own
/// τ_down into [step] / [alphaDownFor].
///
/// **τ is in days** in the spec. The Python sim works in weeks because the
/// driver runs weekly (`-1 / 2.0` weeks ≡ `-7 / 14.0` days — the same α).
/// We store the raw τ in days to keep the unit-conversion site explicit
/// and to make a future per-day driver (Phase 18d) a constant swap.
///
/// All formulas operate on **weekly volume aggregates** (sum of
/// `attribution[bp] × volume_load` over the past 7 days). The driver layer
/// in Phase 18d schedules a daily run; this calculator is unit-independent
/// — it does the math, not the scheduling.
class VitalityCalculator {
  const VitalityCalculator._();

  /// τ_up in days — rebuild time constant. ~2 weeks. Shared across all
  /// body parts (cardio + strength rebuild at the same fast rate).
  static const double tauUpDays = 14.0;

  /// τ_down for the six strength tracks — decay time constant. ~6 weeks.
  static const double tauDownStrengthDays = 42.0;

  /// τ_down for the cardio track — ~3 weeks. Conditioning detrains roughly
  /// twice as fast as strength (Phase 38e two-speed decay).
  static const double tauDownCardioDays = 21.0;

  /// Legacy alias — the strength τ_down. Kept so existing call sites and
  /// the constants-parity fixture (`tau_down_days`) read the strength value
  /// without a rename churn. New code wanting the cardio τ uses
  /// [tauDownCardioDays] explicitly.
  static const double tauDownDays = tauDownStrengthDays;

  /// Sample period for the alphas — the cadence the EWMA is updated at.
  /// Default is weekly because that matches both the rolling weekly-volume
  /// window and the spec §8.1 derivation. The driver in 18d will pass a
  /// 7-day step.
  static const double samplePeriodDays = 7.0;

  /// `α_up = 1 - exp(-Δt / τ_up)` where Δt is one sample period.
  /// At Δt=7d, τ_up=14d → α_up ≈ 0.3935.
  static double get alphaUp => 1.0 - math.exp(-samplePeriodDays / tauUpDays);

  /// `α_down = 1 - exp(-Δt / τ_down)` for the given decay time constant.
  /// At Δt=7d, τ_down=42d → ≈ 0.1535 (strength); τ_down=21d → ≈ 0.2835
  /// (cardio). The faster cardio τ produces a LARGER α_down — more of the
  /// (lower) weekly volume is mixed in each step, so the EWMA falls quicker.
  static double alphaDownFor(double tauDownDays) =>
      1.0 - math.exp(-samplePeriodDays / tauDownDays);

  /// `α_down` for the six strength tracks (τ_down = 42d → ≈ 0.1535).
  static double get alphaDown => alphaDownFor(tauDownStrengthDays);

  /// Single-step EWMA update.
  ///
  /// - If the new weekly volume meets or exceeds the prior EWMA, use
  ///   [alphaUp] (rebuild fast).
  /// - Otherwise use the decay α derived from [tauDownDays] (decay slow).
  ///
  /// [tauDownDays] defaults to the strength time constant
  /// ([tauDownStrengthDays]); the cardio caller passes [tauDownCardioDays]
  /// so conditioning decays on its own faster clock. Peak is permanent —
  /// never decays. Returns the new (ewma, peak) pair; caller persists.
  static VitalityState step({
    required double priorEwma,
    required double priorPeak,
    required double weeklyVolume,
    double tauDownDays = tauDownStrengthDays,
  }) {
    final alpha = weeklyVolume >= priorEwma
        ? alphaUp
        : alphaDownFor(tauDownDays);
    final newEwma = alpha * weeklyVolume + (1.0 - alpha) * priorEwma;
    final newPeak = newEwma > priorPeak ? newEwma : priorPeak;
    return VitalityState(ewma: newEwma, peak: newPeak);
  }

  /// Convenience: the τ_down for a body-part token. Cardio → 21d, all
  /// strength tracks → 42d. Centralises the two-speed lookup so the
  /// repository/projection layer never hard-codes the cardio branch.
  static double tauDownForBodyPart(String bodyPart) =>
      bodyPart == 'cardio' ? tauDownCardioDays : tauDownStrengthDays;

  /// `Vitality_pct = clamp(ewma / peak, 0, 1)`.
  ///
  /// When peak is zero (untrained body part), returns 0 — the rune is
  /// dormant and there is no meaningful ratio.
  static double percentage({required double ewma, required double peak}) {
    if (peak <= 0) return 0;
    final p = ewma / peak;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }
}

/// Snapshot of EWMA + peak after one update step. Plain value class — not
/// persisted directly; the repository UPSERTs the two columns on
/// `body_part_progress`.
class VitalityState {
  const VitalityState({required this.ewma, required this.peak});

  final double ewma;
  final double peak;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VitalityState && other.ewma == ewma && other.peak == peak);

  @override
  int get hashCode => Object.hash(ewma, peak);

  @override
  String toString() => 'VitalityState(ewma: $ewma, peak: $peak)';
}
