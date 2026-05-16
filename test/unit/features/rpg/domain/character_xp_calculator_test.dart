import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/character_xp_calculator.dart';
import 'package:repsaga/features/rpg/domain/rank_curve.dart';

void main() {
  group('characterXpInLevel — single-body-part approximation', () {
    test(
      'day-zero user (all ranks 1, lifetimeXp 0) reports a non-zero denominator',
      () {
        final result = characterXpInLevel(
          ranks: {
            'chest': 1,
            'back': 1,
            'legs': 1,
            'shoulders': 1,
            'arms': 1,
            'core': 1,
          },
          lifetimeXp: 0,
          perBodyPartTotalXp: {
            'chest': 0,
            'back': 0,
            'legs': 0,
            'shoulders': 0,
            'arms': 0,
            'core': 0,
          },
        );
        // Sum-ranks = 6, n = 6 → (6-6) mod 4 = 0 → ranksToNextLevel = 4.
        // Cheapest path: any body part rank 1 → 5. extra = cumXp(5) - 0 ≈ 278.46.
        expect(result.xpInLevel, 0);
        expect(result.xpForNextLevel, greaterThan(0));
      },
    );

    test('mid-level user — denominator strictly greater than numerator', () {
      // Five body parts at rank 3 (just-ranked, totalXp = cumXp(3) = 126).
      // Core at rank 4 (just-ranked, totalXp = cumXp(4) = 198.6).
      // Sum-ranks = 19, n = 6 → (19-6) mod 4 = 1 → ranksToNextLevel = 3.
      // Cheapest single-body-part path: rank 3 → 6 needs cumXp(6) - 126 ≈ 240.3.
      final cum3 = RankCurve.cumulativeXpForRank(3);
      final cum4 = RankCurve.cumulativeXpForRank(4);
      final lifetimeXp = 5 * cum3 + cum4;
      final result = characterXpInLevel(
        ranks: {
          'chest': 3,
          'back': 3,
          'legs': 3,
          'shoulders': 3,
          'arms': 3,
          'core': 4,
        },
        lifetimeXp: lifetimeXp,
        perBodyPartTotalXp: {
          'chest': cum3,
          'back': cum3,
          'legs': cum3,
          'shoulders': cum3,
          'arms': cum3,
          'core': cum4,
        },
      );
      expect(result.xpInLevel, lifetimeXp);
      expect(result.xpForNextLevel, greaterThan(result.xpInLevel));

      // Pin the exact denominator so a curve-constant regression is caught.
      // Cheapest path: chest at rank 3 → 6 needs cumXp(6) - cum3. Core's path
      // (rank 4 → 7) costs cumXp(7) - cum4, which is more expensive — so the
      // helper picks chest's path.
      final cum6 = RankCurve.cumulativeXpForRank(6);
      final expectedExtra = cum6 - cum3;
      expect(result.xpForNextLevel, closeTo(lifetimeXp + expectedExtra, 0.01));
    });

    test(
      'just-leveled-up user (rank-sum at /4 boundary) needs 4 more ranks',
      () {
        // Four body parts at rank 4, two at rank 3. Sum-ranks = 22, n = 6.
        // (22-6) mod 4 = 0 → ranksToNextLevel = 4 (NOT zero — the user just
        // crossed the boundary, the next one is a full 4 ranks away).
        final cum3 = RankCurve.cumulativeXpForRank(3);
        final cum4 = RankCurve.cumulativeXpForRank(4);
        final lifetimeXp = 4 * cum4 + 2 * cum3;
        final result = characterXpInLevel(
          ranks: {
            'chest': 4,
            'back': 4,
            'legs': 4,
            'shoulders': 4,
            'arms': 3,
            'core': 3,
          },
          lifetimeXp: lifetimeXp,
          perBodyPartTotalXp: {
            'chest': cum4,
            'back': cum4,
            'legs': cum4,
            'shoulders': cum4,
            'arms': cum3,
            'core': cum3,
          },
        );
        expect(result.xpInLevel, lifetimeXp);
        expect(result.xpForNextLevel, greaterThan(result.xpInLevel));
      },
    );

    test(
      'all body parts at maxRank — denominator equals numerator (100% fill)',
      () {
        // Every body part at rank 99. Sum = 594. ranksToNextLevel = 4. Every
        // target = 103 > maxRank → all paths skipped → fallback returns
        // (lifetimeXp, lifetimeXp). Bar reads 100% with no further progression.
        final maxCumXp = RankCurve.cumulativeXpForRank(RankCurve.maxRank);
        final lifetimeXp = 6 * maxCumXp;
        final result = characterXpInLevel(
          ranks: {
            'chest': RankCurve.maxRank,
            'back': RankCurve.maxRank,
            'legs': RankCurve.maxRank,
            'shoulders': RankCurve.maxRank,
            'arms': RankCurve.maxRank,
            'core': RankCurve.maxRank,
          },
          lifetimeXp: lifetimeXp,
          perBodyPartTotalXp: {
            'chest': maxCumXp,
            'back': maxCumXp,
            'legs': maxCumXp,
            'shoulders': maxCumXp,
            'arms': maxCumXp,
            'core': maxCumXp,
          },
        );
        expect(result.xpInLevel, lifetimeXp);
        expect(result.xpForNextLevel, lifetimeXp);
      },
    );
  });
}
