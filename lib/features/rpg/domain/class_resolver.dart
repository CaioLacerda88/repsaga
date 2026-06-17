import '../models/body_part.dart';
import '../models/character_class.dart';

/// Pure resolver from per-body-part rank distribution → [CharacterClass]
/// (spec §9.2).
///
/// **Resolution order (locked):**
///
/// ```
/// ranks   = [chest, back, legs, shoulders, arms, core]   (active only)
/// max_r   = max(ranks)
/// min_r   = min(ranks)
///
/// 1. if max_r < 5                              -> Initiate
/// 2. if min_r >= 5
///    AND (max_r - min_r) / max_r <= 0.30       -> Ascendant
/// 3. else                                      -> CLASS_BY_DOMINANT[argmax]
/// ```
///
/// Ascendant precedes the dominant lookup intentionally — balance is rarer
/// and the spec rewards it. The Initiate floor at `max < 5` keeps the badge
/// out of the dominant-class space until the user has crossed at least one
/// body-part's rank-5 threshold, which is the same threshold that unlocks
/// the first per-body-part title (spec §10.1) — keeping the two milestones
/// aligned.
///
/// **Tie-breaking on argmax (deterministic):** when two body parts share the
/// max rank, prefer the alphabetically-first body-part slug
/// (`arms` < `back` < `chest` < `core` < `legs` < `shoulders`). This is
/// invisible to lifters in practice — a true tie at every rank above 5
/// already routes to Ascendant — but it makes the function testable without
/// observer-dependent ordering.
///
/// **Why pure / static:** the input is fully described by the rank map and
/// the output is fully determined by it. A pure function is unit-testable
/// without a Riverpod container, and the provider layer can call it on any
/// snapshot (live, optimistic, simulated) without conditioning on the call
/// site. No `ref`, no async, no IO.
///
/// **Cardio (Phase 38e):** the resolver operates ONLY over
/// [strengthBodyParts] (the six strength tracks). Cardio now lives in
/// [activeBodyParts] (it counts toward Character Level) but is deliberately
/// kept OUT of class resolution — cardio recognition ships as cardio titles,
/// not a class. A [BodyPart.cardio] entry in the input map is silently
/// ignored; there is no Wayfarer class and cardio can never perturb the
/// Ascendant balance check.
class ClassResolver {
  const ClassResolver._();

  /// Fraction of the max rank that the spread `(max - min) / max` must stay
  /// within for the Ascendant bonus class to apply. Spec §9.2 locks this at
  /// 30% — the same predicate the cross-build "Even-Handed" title uses but
  /// at a lower minimum-rank threshold (5 vs 30).
  static const double ascendantSpreadFraction = 0.30;

  /// Minimum rank every body part must reach for Ascendant to qualify. Below
  /// this floor, the user is still consolidating and the dominant lookup
  /// (or Initiate, if max < 5) is the more honest read.
  static const int ascendantMinRank = 5;

  /// Rank below which every body part is treated as untrained and the
  /// resolver returns [CharacterClass.initiate] regardless of distribution.
  /// Mirrors spec §9.1 "Initiate" trigger ("All ranks ≤ 4" → max < 5).
  static const int initiateCeiling = 5;

  /// Body-part → dominant-class lookup. Wayfarer (cardio specialist) is v2
  /// and intentionally absent; cardio is filtered out of the input ranks.
  static const Map<BodyPart, CharacterClass> dominantClass = {
    BodyPart.arms: CharacterClass.berserker,
    BodyPart.chest: CharacterClass.bulwark,
    BodyPart.back: CharacterClass.sentinel,
    BodyPart.legs: CharacterClass.pathfinder,
    BodyPart.shoulders: CharacterClass.atlas,
    BodyPart.core: CharacterClass.anchor,
  };

  /// Resolve the class from a per-body-part rank distribution.
  ///
  /// [ranks] is keyed by [BodyPart]; missing entries default to rank 1 (the
  /// SQL default-row shape). Cardio entries are ignored — the resolver only
  /// considers the six strength tracks ([strengthBodyParts]).
  ///
  /// Returns [CharacterClass.initiate] when the input is empty or every rank
  /// is below [initiateCeiling].
  static CharacterClass resolve(Map<BodyPart, int> ranks) {
    // Project to the strength tracks only, defaulting missing entries to
    // rank 1 (matches the SQL default-row + RpgProgressSnapshot.progressFor
    // contract). Cardio is excluded here even though it is in
    // `activeBodyParts` for Character Level — it never feeds class/Ascendant.
    final activeRanks = <BodyPart, int>{
      for (final bp in strengthBodyParts) bp: ranks[bp] ?? 1,
    };

    final values = activeRanks.values.toList(growable: false);
    final maxRank = values.reduce((a, b) => a > b ? a : b);
    final minRank = values.reduce((a, b) => a < b ? a : b);

    // 1. Initiate floor — every rank still under 5.
    if (maxRank < initiateCeiling) {
      return CharacterClass.initiate;
    }

    // 2. Ascendant — balanced AND every rank past the consolidation floor.
    //    Order matters: Ascendant must precede the dominant lookup so a
    //    perfectly-balanced lifter is not classified by their argmax.
    if (minRank >= ascendantMinRank) {
      final spread = (maxRank - minRank) / maxRank;
      if (spread <= ascendantSpreadFraction) {
        return CharacterClass.ascendant;
      }
    }

    // 3. Dominant lookup. Tie-break by alphabetical body-part slug for
    //    deterministic output — a distribution where every rank is tied at
    //    the Ascendant floor or above already routes to Ascendant; this
    //    branch fires on partial ties between dominant tracks.
    final sortedBodyParts = activeRanks.keys.toList(growable: false)
      ..sort((a, b) => a.dbValue.compareTo(b.dbValue));

    var dominant = sortedBodyParts.first;
    var dominantRank = activeRanks[dominant]!;
    for (final bp in sortedBodyParts.skip(1)) {
      final rank = activeRanks[bp]!;
      if (rank > dominantRank) {
        dominant = bp;
        dominantRank = rank;
      }
    }

    return dominantClass[dominant] ?? CharacterClass.initiate;
  }
}
