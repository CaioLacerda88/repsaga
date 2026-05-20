/// Cross-feature bridge from [MuscleGroup] (exercises feature) to
/// [BodyPart] (rpg feature) and from there to the body-part hue token.
///
/// Lives in `core/theme/` rather than either feature folder because it
/// bridges two features that must not import each other (CLAUDE.md
/// "No cross-feature imports" rule). Same pattern as `core/format/
/// weight_unit.dart`: cross-cutting concern lives at `core/`, both
/// features stay isolated.
///
/// Why the mapping is `MuscleGroup → BodyPart?` (nullable):
///   * The six v1 strength pillars (chest, back, legs, shoulders, arms,
///     core) map 1:1 — they have an identity hue in
///     [VitalityStateStyles.bodyPartColor].
///   * `MuscleGroup.cardio` and any future non-strength-pillar muscle
///     group (e.g. glutes, traps, calves, forearms, neck if added)
///     return `null`. Cardio is v2 / "infrastructure-only" per
///     [AppColors.bodyPartCardio] dartdoc — UI surfaces fall back to a
///     neutral color for these groups.
///
/// Direction: exercises consumes the rpg identity, never the reverse.
/// Both features remain decoupled — this helper is the only place that
/// knows both enums.
library;

import 'package:flutter/painting.dart';

import '../../features/exercises/models/exercise.dart';
import '../../features/rpg/models/body_part.dart';
import '../../features/rpg/ui/utils/vitality_state_styles.dart';

/// Maps a [MuscleGroup] to its corresponding [BodyPart] for the six v1
/// strength pillars. Returns `null` for muscle groups that don't have a
/// body-part identity token (currently: `cardio`).
///
/// Use [muscleGroupHueColor] when all you need is the hue color — that
/// wraps this function plus the [VitalityStateStyles.bodyPartColor]
/// lookup so UI call sites never import the rpg feature directly.
BodyPart? muscleGroupToBodyPart(MuscleGroup group) => switch (group) {
  MuscleGroup.chest => BodyPart.chest,
  MuscleGroup.back => BodyPart.back,
  MuscleGroup.legs => BodyPart.legs,
  MuscleGroup.shoulders => BodyPart.shoulders,
  MuscleGroup.arms => BodyPart.arms,
  MuscleGroup.core => BodyPart.core,
  // v1 has no cardio identity surface (see AppColors.bodyPartCardio
  // dartdoc — infrastructure-only for v1, deferred to v1.1+). Callers
  // get a null and fall back to a neutral color.
  MuscleGroup.cardio => null,
};

/// Resolves a [MuscleGroup] to its body-part identity hue at full
/// saturation, or `null` when the group has no identity token (cardio
/// + any future non-strength-pillar value). UI callers consume this
/// without importing the rpg feature directly.
///
/// Returns the same color values as
/// `VitalityStateStyles.bodyPartColor[BodyPart.<x>]` — locking on this
/// helper preserves the "single source of truth" contract documented in
/// [VitalityStateStyles.bodyPartColor].
Color? muscleGroupHueColor(MuscleGroup group) {
  final bp = muscleGroupToBodyPart(group);
  if (bp == null) return null;
  return VitalityStateStyles.bodyPartColor[bp];
}

/// Extension form of [muscleGroupToBodyPart] / [muscleGroupHueColor]
/// for call-site readability: `MuscleGroup.chest.hueColor` reads as a
/// property of the muscle group itself.
extension MuscleGroupBodyPart on MuscleGroup {
  /// See [muscleGroupToBodyPart].
  BodyPart? toBodyPart() => muscleGroupToBodyPart(this);

  /// See [muscleGroupHueColor].
  Color? get hueColor => muscleGroupHueColor(this);
}
