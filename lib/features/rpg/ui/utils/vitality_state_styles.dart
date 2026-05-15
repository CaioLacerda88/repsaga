import 'package:flutter/painting.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/body_part.dart';
import '../../models/vitality_state.dart';

/// UI-side resolver for the visual + localized presentation of
/// [VitalityState] and per-[BodyPart] colors.
///
/// **Why this lives in `ui/utils/` and not `domain/` (BUG-035):** the
/// [VitalityStateMapper] in `domain/` owned `Color` resolution
/// (`borderColorFor`, `bodyPartColor`) and `AppLocalizations` lookup
/// (`localizedCopy`) — both Flutter-framework concerns. That gave the
/// domain layer a hard dependency on `package:flutter/painting.dart` plus
/// the generated `AppLocalizations`, which:
///   * blocked unit-testing the boundary algorithm without Flutter
///     widget-binding overhead;
///   * coupled the saga business rules to the presentation framework, so
///     a future CLI / server-side surface couldn't reuse the rules
///     without dragging in Flutter; and
///   * silently invited new domain methods to keep accreting UI concerns
///     in the same file.
///
/// The split is structural: `domain/vitality_state_mapper.dart` owns
/// boundary thresholds + the four-state collapse (pure Dart). This file
/// owns Color + localized-copy resolution. UI consumers import this
/// helper at the widget boundary and call into the domain mapper for the
/// state derivation only.
///
/// **Single source of truth contract preserved.** The palette the UI
/// resolves to is still locked here in one place — every consumer of a
/// per-state color, per-body-part color, or per-state copy line MUST go
/// through this helper. Splitting the resolution per surface would
/// re-introduce the drift the original mapper existed to prevent
/// (chart-line cyan vs halo dot purple vs progress bar orange for the
/// same body part).
class VitalityStateStyles {
  const VitalityStateStyles._();

  // ---------------------------------------------------------------------------
  // Per-state colors (the rune-glow palette, locked to AppTheme tokens)
  // ---------------------------------------------------------------------------

  /// Stamp/border tint per state — used by `RankStamp` borders, the
  /// vitality-radar vertex dots, and the §13.3 stats-table state chip.
  ///
  /// Choices (per AppTheme palette):
  ///   * `untested` → [AppColors.textDim] — same dim/grey token as dormant;
  ///                  the visual treatment is intentionally identical so
  ///                  "never trained" and "fully decayed" share the rune-
  ///                  silent palette. The differentiation lives in the
  ///                  percentage readout (`—` vs `0%`) and the marginalia
  ///                  copy line.
  ///   * `dormant`  → [AppColors.textDim] — cold, ash-gray; the rune is silent.
  ///   * `fading`   → [AppColors.primaryViolet] — the "lost path" tone, present
  ///                  but not loud.
  ///   * `active`   → [AppColors.hotViolet] — the default brand-bright violet,
  ///                  the rune at rest "on the path".
  ///   * `radiant`  → [AppColors.heroGold] — the reward-only token, peak
  ///                  conditioning. Rendered through `RewardAccent` at the
  ///                  widget-tree level (see `lib/core/theme/README.md`).
  ///
  /// **Reward-scarcity contract.** Only `radiant` resolves to `heroGold`.
  /// `untested` reuses the dim/grey token so the new state cannot
  /// accidentally widen the gold surface area.
  static Color borderColorFor(VitalityState s) {
    switch (s) {
      case VitalityState.untested:
        // Reuse the dormant dim/grey token: untested is rune-silent in the
        // same way dormant is. The pct readout (`—`) + marginalia copy
        // ("Uncharted — log a set to begin") carry the differentiation.
        return AppColors.textDim;
      case VitalityState.dormant:
        return AppColors.textDim;
      case VitalityState.fading:
        return AppColors.primaryViolet;
      case VitalityState.active:
        return AppColors.hotViolet;
      case VitalityState.radiant:
        // §8.4 Radiant IS the reward signal (peak conditioning). Sinks are
        // CustomPainter Paint.color + Border.all + Paint().shader, none of
        // which read IconTheme/DefaultTextStyle from a RewardAccent
        // ancestor — so the widget-tree contract cannot apply here.
        // ignore: reward_accent — see comment above; structurally impossible to wrap painter sinks in RewardAccent
        return AppColors.heroGold;
    }
  }

  /// Halo glow tint per state. For most states this is the same as the
  /// border color (single source of truth for the rune palette); the
  /// indirection exists so a future design pass can split halo vs border
  /// without touching every consumer.
  static Color haloColorFor(VitalityState s) => borderColorFor(s);

  /// Progress-bar fill color per state. Hairlines and full progress bars
  /// alike use this — not the body-part color — because the progress bar
  /// communicates "current conditioning state" (a temporal signal) rather
  /// than "which body part" (an identity signal). Identity is conveyed by
  /// the row position + sigil; conditioning is conveyed by the color ramp.
  static Color progressBarColorFor(VitalityState s) => borderColorFor(s);

  // ---------------------------------------------------------------------------
  // Per-body-part chart palette (locked once)
  // ---------------------------------------------------------------------------

  /// Body-part → chart line / sigil tint when the surface needs to convey
  /// **which body part** rather than **which conditioning state**.
  ///
  /// Lock contract (UI-critic note): every surface that draws a per-body-
  /// part visual differentiation reads from this map. The §13.3 stats
  /// deep-dive trend chart (Stage 3), the future per-body-part history
  /// graph, and any "all six body parts at a glance" surface MUST consume
  /// these colors. Introducing a second source = inevitable drift across
  /// surfaces.
  ///
  /// Color choices (from AppTheme palette + spec §3 metaphors):
  ///   * `chest`     → [AppColors.hotViolet]    — bright primary, anchors the
  ///                   pressing identity at the top of the radar.
  ///   * `back`      → [AppColors.primaryViolet]— deep base violet, the
  ///                   pulling foundation that mirrors chest across the body.
  ///   * `legs`      → [AppColors.success]      — the green of foundation /
  ///                   ground-stride; lower-body roots the saga.
  ///   * `shoulders` → [AppColors.warning]      — warm yellow-amber, the
  ///                   "yoke" / overhead reach distinct from heroGold.
  ///   * `arms`      → [AppColors.error]        — red of the sinew; arms are
  ///                   the visible specialist rank (§9.1 Berserker).
  ///   * `core`      → [AppColors.textDim]      — neutral spine tone; core
  ///                   stabilises but doesn't lead the eye.
  ///   * `cardio`    → [AppColors.hair]         — muted hairline; v2 track,
  ///                   intentionally desaturated until earnable.
  ///
  /// `heroGold` is intentionally NOT in this map — it stays scarce as the
  /// reward token reserved for the `radiant` state and §13.2 rank-up
  /// celebrations.
  static const Map<BodyPart, Color> bodyPartColor = {
    BodyPart.chest: AppColors.hotViolet,
    BodyPart.back: AppColors.primaryViolet,
    BodyPart.legs: AppColors.success,
    BodyPart.shoulders: AppColors.warning,
    BodyPart.arms: AppColors.error,
    BodyPart.core: AppColors.textDim,
    BodyPart.cardio: AppColors.hair,
  };

  // ---------------------------------------------------------------------------
  // Vitality ramp color (Phase 26a)
  // ---------------------------------------------------------------------------

  /// Resolves a vitality percentage to its band color on the HP-drain
  /// ramp (Phase 26a).
  ///
  /// Bands:
  ///   * 66%–100%  → [AppColors.vitalityHigh]
  ///   * 34%–65%   → [AppColors.vitalityMid]
  ///   * 0%–33%    → [AppColors.vitalityLow]
  ///   * null or out of [0,1] → [AppColors.textDim] (untested / malformed)
  ///
  /// Used on the Stats deep-dive vitality table percentage column
  /// (Phase 26c) and any other surface that needs to communicate
  /// conditioning state via color.
  static Color vitalityRampColorFor(double? percentage) {
    if (percentage == null || percentage < 0.0 || percentage > 1.0) {
      return AppColors.textDim;
    }
    if (percentage >= 0.66) return AppColors.vitalityHigh;
    if (percentage >= 0.34) return AppColors.vitalityMid;
    return AppColors.vitalityLow;
  }

  // ---------------------------------------------------------------------------
  // Localized copy (l10n)
  // ---------------------------------------------------------------------------

  /// Returns the localized marginalia copy line for [state] per spec §8.4 +
  /// §13.3. These copy lines render ONLY on the stats deep-dive screen —
  /// the character sheet stays number-free and copy-free, the rune state
  /// alone is the signal there.
  ///
  /// **Single source of truth.** This helper owns the
  /// [VitalityState] → [AppLocalizations] string association; consumers
  /// just provide the [AppLocalizations] instance from their `BuildContext`
  /// (e.g. `AppLocalizations.of(context)`). We deliberately do NOT return
  /// a raw key string — `AppLocalizations` (Flutter gen-l10n) has no
  /// runtime key-lookup API, so a key-returning helper would force every
  /// consumer to write a second switch from key back to getter, defeating
  /// the centralisation goal.
  static String localizedCopy(VitalityState state, AppLocalizations l10n) {
    switch (state) {
      case VitalityState.untested:
        return l10n.vitalityCopyUntested;
      case VitalityState.dormant:
        return l10n.vitalityCopyDormant;
      case VitalityState.fading:
        return l10n.vitalityCopyFading;
      case VitalityState.active:
        return l10n.vitalityCopyActive;
      case VitalityState.radiant:
        return l10n.vitalityCopyRadiant;
    }
  }
}

/// Compatibility extension on [VitalityState] that exposes the per-state
/// border color via the legacy `state.borderColor` call shape used by
/// rank stamps, rune halos, vitality radar vertex dots, and the xp
/// progress hairline.
///
/// Lives in the UI utils layer (BUG-035) — the `models/vitality_state.dart`
/// file is now Flutter-agnostic, so the extension that returns a Color
/// must travel with it. New code should prefer
/// [VitalityStateStyles.borderColorFor] explicitly; the extension stays
/// for the existing surface area where the property-style read reads more
/// naturally inside a `Border.all(color: ...)` argument.
extension VitalityStateColor on VitalityState {
  /// Border / vertex / rune-halo tint for this state. Delegates to
  /// [VitalityStateStyles.borderColorFor] so the palette stays locked in
  /// one place.
  Color get borderColor => VitalityStateStyles.borderColorFor(this);
}
