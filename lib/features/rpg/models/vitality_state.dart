import '../domain/vitality_state_mapper.dart';

/// Visual state of a body-part's rune sigil, derived from Vitality %.
///
/// Per design spec §8.4, Vitality % is **never displayed as a number on the
/// primary character sheet** — it drives the rune's visual state instead.
/// The thresholds below are the canonical contract: Dormant for never-trained
/// (peak == 0), Fading for stepped-off-the-path conditioning, Active for the
/// default "on the path" state, Radiant for peak conditioning.
///
/// The Stats Deep-Dive screen (Phase 18d, §13.3) is the only surface that
/// shows the underlying numeric percentage.
///
/// **State derivation lives in [VitalityStateMapper].** This file owns only
/// the enum + a back-compat extension that delegates. New code should
/// import [VitalityStateMapper] directly and call `fromPercent` /
/// `fromVitality` on it.
///
/// **BUG-035 split.** Until 2026-05-02 this file imported
/// `package:flutter/painting.dart` to expose a `borderColor` extension
/// returning a `Color`. That made `models/vitality_state.dart` (a domain
/// model) depend on the Flutter framework — a layering violation. The
/// `borderColor` extension now lives in
/// `lib/features/rpg/ui/utils/vitality_state_styles.dart` (the
/// `VitalityStateColor` extension) so the model file is Flutter-agnostic.
/// Existing call sites that wrote `state.borderColor` keep working — they
/// just import the styles helper instead of this file for that property.
enum VitalityState {
  /// `vitality_peak == 0`. Body part has never been trained; the
  /// `ewma / peak` ratio is mathematically undefined, so the percentage
  /// readout collapses to `—` (em-dash) rather than the misleading `0%`
  /// that reads as a failure grade. Distinct from [dormant], which means
  /// "trained once, conditioning fully decayed" — a genuinely zero ratio
  /// that DOES render as `0%`. Visual treatment matches dormant (dim/grey
  /// palette, no animation budget) — the difference is the percentage
  /// readout + the marginalia copy ("Uncharted — log a set to begin").
  untested,

  /// `vitality_peak > 0` and `ewma ~ 0` — body part trained at least once,
  /// then fully fallen off the path. Conditioning lost.
  /// Sigil renders at full opacity with a desaturated breathing-pulse halo.
  dormant,

  /// 1-30% of permanent peak. Conditioning lost — return to the path.
  /// Sigil renders at full opacity with a desaturated breathing-pulse halo.
  fading,

  /// 31-70% of permanent peak. Default "on the path" state. Static halo,
  /// attention-conserving.
  active,

  /// 71-100% of permanent peak. Peak conditioning. Sigil enlarged 10%, gold
  /// halo, sweep highlight cycle (~4-5s).
  radiant,
}

/// Compatibility shim around [VitalityStateMapper] — preserves the
/// existing `VitalityStateX.fromVitality(...)` call shape used by
/// character_sheet_state.dart, character_sheet_provider.dart, and the
/// existing widget/unit tests. New code should use [VitalityStateMapper]
/// directly.
///
/// **Color resolution moved.** `VitalityStateX.borderColor` lived here
/// pre-BUG-035; it now lives on the
/// `VitalityStateColor` extension in
/// `lib/features/rpg/ui/utils/vitality_state_styles.dart`. The reroute
/// keeps domain code (this file) Flutter-free while leaving the
/// `state.borderColor` call shape intact for UI consumers (they import
/// the UI helper instead).
extension VitalityStateX on VitalityState {
  /// Map a raw Vitality EWMA + permanent peak to a visual state.
  ///
  /// Delegates to [VitalityStateMapper.fromVitality] which normalises to
  /// the percentage `clamp(ewma / peak, 0, 1)` first and then dispatches
  /// to the §8.4 boundary thresholds. Boundary semantics:
  ///
  ///   * `peak == 0`              → Untested ("Uncharted — log a set to begin")
  ///   * `peak > 0 && pct == 0`   → Dormant ("Conditioning lost — return…")
  ///   * `0 < pct ≤ 0.30`         → Fading
  ///   * `0.30 < pct ≤ 0.70`      → Active
  ///   * `0.70 < pct ≤ 1.0`       → Radiant
  ///
  /// `ewma == 0` with `peak > 0` (fully decayed) computes
  /// `pct = 0/peak = 0` and falls into Dormant — a body part you trained
  /// once and have completely lost conditioning on. The dedicated
  /// [VitalityState.untested] state is reserved for the peak == 0 case
  /// where the ratio is undefined.
  static VitalityState fromVitality({
    required double vitalityEwma,
    required double vitalityPeak,
  }) =>
      VitalityStateMapper.fromVitality(ewma: vitalityEwma, peak: vitalityPeak);
}
