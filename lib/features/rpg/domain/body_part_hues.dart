import 'package:flutter/painting.dart' show Color;

import '../../../core/theme/app_theme.dart';
import '../models/body_part.dart';

/// Canonical body-part → hue map (domain layer, single source of truth).
///
/// **Why this lives in `domain/` and not `ui/utils/` (PR 30b Important 5):**
/// the share-card composer (`SharePayload.fromPostSessionState` /
/// `SharePayload.dominantHue`) needs to resolve a body part to its identity
/// hue to project a renderable payload. The composer is a pure domain
/// transformation — it must not import from the `ui/` layer. Previously the
/// hue lookup lived only in `lib/features/rpg/ui/utils/vitality_state_styles.dart`
/// and `share_payload.dart` had to reach across the layer boundary to read it.
///
/// **`painting.dart`, not `material.dart`.** The map's values are
/// `Color` instances from `dart:ui`; importing the lightweight
/// `package:flutter/painting.dart` re-export is enough and matches the
/// pattern used by other domain-layer files that need `Color` (no
/// `Material` widget dependencies sneak in).
///
/// **Lock contract (UI-critic note, preserved verbatim from the original
/// `VitalityStateStyles` callsite):** every surface that draws a per-body-
/// part visual differentiation reads from this map. The §13.3 stats
/// deep-dive trend chart (Stage 3), the future per-body-part history
/// graph, and any "all six body parts at a glance" surface MUST consume
/// these colors. Introducing a second source = inevitable drift across
/// surfaces.
///
/// Color choices (from AppTheme palette + spec §3 metaphors):
///   * `chest`     → [AppColors.bodyPartChest] — pink (Phase 26a). Anatomical
///                   fit (pec/heart) + frees [hotViolet] from chest identity.
///   * `back`      → [AppColors.bodyPartBack]  — sky-blue (Phase 26a).
///                   Resolves the chest/back "two purples" hue collision.
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
class BodyPartHues {
  const BodyPartHues._();

  /// Body-part → identity hue lookup. Single source of truth shared by the
  /// stats trend chart, character card halos, rank rail row tints, share
  /// card composer, and any other "which body part" identity surface.
  static const Map<BodyPart, Color> bodyPartColor = {
    BodyPart.chest: AppColors.bodyPartChest,
    BodyPart.back: AppColors.bodyPartBack,
    BodyPart.legs: AppColors.success,
    BodyPart.shoulders: AppColors.warning,
    BodyPart.arms: AppColors.error,
    BodyPart.core: AppColors.textDim,
    BodyPart.cardio: AppColors.hair,
  };

  /// Convenience accessor with a fallback to `hotViolet` (the defensive
  /// brand color reserved for "no body part" / class-change overrides).
  /// Used by the share-card composer to keep the call site terse.
  static Color hueFor(BodyPart bp) =>
      bodyPartColor[bp] ?? AppColors.hotViolet;
}
