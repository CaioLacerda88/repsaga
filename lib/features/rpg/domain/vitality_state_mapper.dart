import '../models/vitality_state.dart';
// Hide the legacy `VitalityState` data class — `VitalityCalculator.step`
// returns it, but this mapper deals exclusively with the four-state enum
// from models/vitality_state.dart. Keeping the calculator's class name as
// VitalityState (rather than renaming it) avoids churn across §8.1 sites.
import 'vitality_calculator.dart' show VitalityCalculator;

/// Pure domain rules for the four-state Vitality collapse (§8.4).
///
/// Phase 18d Stage 2 + BUG-035 split:
///   * **Domain (this file):** boundary thresholds + the four-state
///     derivation. Zero Flutter dependencies, zero `AppLocalizations`
///     dependencies — unit-testable in pure Dart, reusable from any
///     surface (CLI tooling, server-side pre-computation, future widget
///     surfaces). The only collaborator is [VitalityCalculator] for the
///     `clamp(ewma/peak, 0, 1)` percentage helper, which is also pure.
///   * **UI (`lib/features/rpg/ui/utils/vitality_state_styles.dart`):**
///     Color resolution per state, per-body-part color palette, and
///     localized copy lookup. Imports Flutter + `AppLocalizations`.
///
/// **Why split:** the original mapper accumulated three Flutter-coupled
/// concerns (`Color borderColorFor`, `Map<BodyPart, Color> bodyPartColor`,
/// `String localizedCopy(_, AppLocalizations)`) over its lifetime. That
/// blocked unit-testing the boundary algorithm without widget binding
/// overhead and silently invited new methods to keep accreting in the
/// same file. The split is structural: any future visual concern goes
/// into the styles file, any future domain rule (e.g. a fifth state, a
/// new threshold) goes here.
///
/// **Boundary semantics (spec §8.4 + 2026-05-04 untested patch):**
///   * `peak == 0`              → `untested` ("Uncharted — log a set to begin")
///   * `peak > 0 && pct == 0`   → `dormant`  ("Conditioning lost — return…")
///   * `0 < pct ≤ 0.30`         → `fading`   (1-30% of peak)
///   * `0.30 < pct ≤ 0.70`      → `active`   ("On the path")
///   * `0.70 < pct ≤ 1.0`       → `radiant`  ("Path mastered")
///
/// `pct` is `clamp(ewma / peak, 0, 1)` — see [VitalityCalculator.percentage].
/// The `untested` branch is the only one where `pct` is mathematically
/// undefined (division by zero); every other branch has a real ratio.
///
/// Why this lives in `domain/` and not `models/`: the boundary logic is a
/// state-derivation rule, not a data shape. The enum itself stays in
/// `models/vitality_state.dart` so existing call sites (10+ files) keep
/// their current import — this class just centralises the rules they all
/// rely on. The compatibility shim in `VitalityStateX.fromVitality`
/// delegates here.
class VitalityStateMapper {
  const VitalityStateMapper._();

  /// Boundary at which fading transitions to active (inclusive lower).
  /// Spec §8.4: 1-30% maps to Fading.
  static const double fadingMaxPct = 0.30;

  /// Boundary at which active transitions to radiant (inclusive lower).
  /// Spec §8.4: 31-70% maps to Active.
  static const double activeMaxPct = 0.70;

  /// Map a Vitality percentage (0..1) to the four-state §8.4 collapse.
  ///
  /// `pct == 0` is the dormant boundary — peak HAS been established but
  /// EWMA fully decayed to zero. `pct > 1.0` is clamped to radiant (a guard
  /// against floating-point overshoot from numeric(14,4) round-trips).
  ///
  /// Boundary inclusivity matches spec §8.4:
  ///   * `pct = 0`     → dormant
  ///   * `pct = 0.30`  → fading  (right-edge inclusive)
  ///   * `pct = 0.70`  → active  (right-edge inclusive)
  ///   * `pct = 1.00`  → radiant
  ///
  /// **Why `fromPercent` never returns [VitalityState.untested]:** by the
  /// time a caller has a `pct` to pass, peak has already been observed >0
  /// — the percentage exists. Untested is the "ratio is undefined" branch
  /// (peak == 0) and is reachable only through [fromVitality]. Trend-chart
  /// reconstructions, mean-vitality halo derivation, and other paths that
  /// already have a ratio in hand stay on the four-state mapping.
  static VitalityState fromPercent(double pct) {
    if (pct <= 0) return VitalityState.dormant;
    if (pct <= fadingMaxPct) return VitalityState.fading;
    if (pct <= activeMaxPct) return VitalityState.active;
    return VitalityState.radiant;
  }

  /// Map raw EWMA + peak to a state, normalising via
  /// [VitalityCalculator.percentage] first.
  ///
  /// `peak <= 0` returns [VitalityState.untested] — a body part with no
  /// recorded peak has never been trained, the ewma/peak ratio is
  /// mathematically undefined, and the UI renders `—` instead of `0%` to
  /// avoid the "failure grade" misread. This handles the day-1 user
  /// (peak == 0, ewma == 0) and protects against divide-by-zero in the
  /// percentage helper. `peak > 0 && ewma == 0` (genuinely decayed) still
  /// returns [VitalityState.dormant] via [fromPercent].
  ///
  /// Note: this replaces the latent bug in the original
  /// `VitalityStateX.fromVitality` which compared raw EWMA against literal
  /// 30/70 — that semantics treated EWMA as if it were already a 0..100
  /// percentage, but EWMA in `body_part_progress` is volume-derived (often
  /// thousands). The bug was masked because the 18a `record_set_xp`
  /// function never updated `vitality_ewma` (always 0). Once the 18d
  /// nightly job populates EWMA correctly, this percentage-based mapper is
  /// the only correct semantics.
  static VitalityState fromVitality({
    required double ewma,
    required double peak,
  }) {
    if (peak <= 0) return VitalityState.untested;
    return fromPercent(VitalityCalculator.percentage(ewma: ewma, peak: peak));
  }
}
