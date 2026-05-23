import '../../../../rpg/models/body_part.dart';

/// Discriminated union for the per-state forward-hook line on the summary
/// panel. The screen layer resolves a localized line for each variant
/// (Decoupling Rule 2 — strings localize at the screen, not the widget).
///
/// Mockup §5:
///   - State 1, 2, 5, 6, 8: "Faltam {xp} XP\npara {bodyPart} rank {n}." (NextRank)
///   - State 3, 4: PR-specific hook (PRDetail variant).
///   - State 7, 10: "Faltam {ranks} ranks\npara nível {n+1}." (NextLevel)
///   - State 9: class flavor (handled in summary header).
sealed class NextStepHookKind {
  const NextStepHookKind();
}

/// "Falta {xp} XP para {bodyPart} rank {n}." — most common forward hook.
/// Mockup §5 States 1, 2, 5, 6, 8.
class NextRankHook extends NextStepHookKind {
  const NextRankHook({
    required this.bodyPart,
    required this.xpToNextRank,
    required this.nextRank,
  });
  final BodyPart bodyPart;
  final int xpToNextRank;
  final int nextRank;
}

/// "Faltam {ranks} ranks para nível {nextLevel}." — character-level hook.
/// Mockup §5 States 7, 10.
class NextLevelHook extends NextStepHookKind {
  const NextLevelHook({
    required this.ranksToNextLevel,
    required this.nextLevel,
  });
  final int ranksToNextLevel;
  final int nextLevel;
}

/// PR-anchored hook: "Supino · 95kg × 5\n+5kg vs anterior." Mockup §5 State 3.
class PrDetailHook extends NextStepHookKind {
  const PrDetailHook({
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.improvementKg,
  });
  final String exerciseName;
  final double weightKg;
  final int reps;
  final double improvementKg;
}

/// Pure derivation of the next-step hook from the post-finish snapshot.
///
/// Inputs are plain primitives so this function unit-tests without harness.
/// The screen layer wires per-tier disambiguation:
///   * baseline / day-zero / rank-up: [NextRankHook]
///   * character-level-up / max-combo: [NextLevelHook]
///   * PR (without rank-up): [PrDetailHook]
///   * class-change: handled by summary header (no NextStepHookKind)
class NextStepHookResolver {
  const NextStepHookResolver._();

  /// Pick the appropriate variant.
  ///
  /// Precedence (matches mockup §5 state script):
  ///   1. [hasLevelUp] → [NextLevelHook]
  ///   2. [prDetail] != null → [PrDetailHook]
  ///   3. dominant BP has a next rank → [NextRankHook]
  ///   4. Otherwise null (e.g. user is at maxRank on everything — degenerate).
  static NextStepHookKind? resolve({
    required bool hasLevelUp,
    required PrDetailHook? prDetail,
    required BodyPart? dominantBodyPart,
    required int? dominantXpToNextRank,
    required int? dominantNextRank,
    required int? ranksToNextLevel,
    required int? nextLevel,
  }) {
    if (hasLevelUp && ranksToNextLevel != null && nextLevel != null) {
      return NextLevelHook(
        ranksToNextLevel: ranksToNextLevel,
        nextLevel: nextLevel,
      );
    }
    if (prDetail != null) return prDetail;
    if (dominantBodyPart != null &&
        dominantXpToNextRank != null &&
        dominantXpToNextRank > 0 &&
        dominantNextRank != null) {
      return NextRankHook(
        bodyPart: dominantBodyPart,
        xpToNextRank: dominantXpToNextRank,
        nextRank: dominantNextRank,
      );
    }
    return null;
  }
}
