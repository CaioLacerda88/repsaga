import 'rank_curve.dart';

/// Result shape for [characterXpInLevel].
///
/// `xpInLevel` is the numerator (always equals current lifetimeXp — the bar
/// fills the entire spent lifetime, not a within-band slice — because the
/// "level" boundary is rank-derived, not XP-derived). `xpForNextLevel` is
/// `xpInLevel + cheapestAdditionalXp`, where the cheapest path advances ONE
/// body part by `ranksToNextLevel` ranks. The bar renders fill =
/// `xpInLevel / xpForNextLevel`.
class CharacterXpBand {
  const CharacterXpBand({
    required this.xpInLevel,
    required this.xpForNextLevel,
  });

  final double xpInLevel;
  final double xpForNextLevel;
}

/// Active body parts contributing to character level. v1 = the 6 strength
/// tracks (cardio excluded — matches `activeBodyParts` in
/// `models/body_part.dart` but kept as `List<String>` here so the helper is
/// model-import-free and testable in pure Dart).
const _activeKeys = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];

/// Character XP band for the Saga header bar (Phase 26b).
///
/// Computes how much *additional* XP the user needs to earn — in a single
/// body part — to advance character level by one. The denominator returned
/// is `lifetimeXp + cheapestAdditionalXp`, so the bar's fill ratio
/// `xpInLevel / xpForNextLevel` reads "lifetime XP as a fraction of where
/// it would be if the user took the cheapest path to next character level."
///
/// **Approximation contract.** This DOES NOT solve the optimal multi-body-
/// part advancement (where partial rank-ups in different body parts could
/// sum to the +ranksToNextLevel target with strictly less XP). It picks one
/// body part and computes how much that body part alone needs to advance
/// by `ranksToNextLevel` ranks. The single-body-part path is an UPPER BOUND
/// on the true minimum, deterministic, and easy to reason about — the bar
/// stays monotonic (lifetime XP only increases, denominator only changes
/// on a rank-up).
///
/// **Why not solve the optimum.** The user can only train one body part
/// per set, but the "cheapest path" intuitively spans the K-cheapest single-
/// rank advances across distinct body parts. That requires a top-K selection
/// over an evolving cost vector (each rank-up makes the next rank more
/// expensive in the same body part). For a glanceable progress bar, the
/// single-body-part approximation is enough — the user is not playing an
/// optimization game, they're reading "how close am I to the next level?"
///
/// Edge cases:
///   * Day-zero user (all ranks 1, lifetimeXp 0): denominator is the XP
///     needed for one body part to reach rank 5 (4 rank-ups in 1 body part).
///   * Just-leveled-up user (rank-sum just crossed a /4 boundary): needs
///     4 more ranks, not 0.
///   * Maxed-out user (a body part hits rank 99): the helper falls back to
///     picking from the remaining 5. If all 6 are maxed, returns a denominator
///     equal to lifetimeXp (bar reads 100%, no further progression possible).
CharacterXpBand characterXpInLevel({
  required Map<String, int> ranks,
  required double lifetimeXp,
  required Map<String, double> perBodyPartTotalXp,
}) {
  var sumRanks = 0;
  var nActive = 0;
  for (final key in _activeKeys) {
    final r = ranks[key];
    if (r == null) continue;
    sumRanks += r;
    nActive += 1;
  }
  if (nActive == 0) {
    return CharacterXpBand(
      xpInLevel: lifetimeXp,
      xpForNextLevel: lifetimeXp + 1,
    );
  }
  final modulo = (sumRanks - nActive) % 4;
  final ranksToNextLevel = modulo == 0 ? 4 : 4 - modulo;

  double? cheapestExtraXp;
  for (final key in _activeKeys) {
    final currentRank = ranks[key];
    final totalXpForPart = perBodyPartTotalXp[key];
    if (currentRank == null || totalXpForPart == null) continue;
    final targetRank = currentRank + ranksToNextLevel;
    if (targetRank > RankCurve.maxRank) {
      // body part too maxed to advance
      continue;
    }
    final totalXpAtTarget = RankCurve.cumulativeXpForRank(targetRank);
    final extra = totalXpAtTarget - totalXpForPart;
    if (extra <= 0) {
      // defensive — shouldn't happen if curve is monotonic
      continue;
    }
    if (cheapestExtraXp == null || extra < cheapestExtraXp) {
      cheapestExtraXp = extra;
    }
  }

  if (cheapestExtraXp == null) {
    // All body parts are maxed out beyond what ranksToNextLevel can reach.
    // Render the bar at 100% with a denominator = lifetimeXp (no further
    // progression possible).
    return CharacterXpBand(xpInLevel: lifetimeXp, xpForNextLevel: lifetimeXp);
  }
  return CharacterXpBand(
    xpInLevel: lifetimeXp,
    xpForNextLevel: lifetimeXp + cheapestExtraXp,
  );
}
