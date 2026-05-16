import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/character_xp_calculator.dart';
import 'package:repsaga/features/rpg/domain/rank_curve.dart';

void main() {
  group('xpForNextCharacterLevel — single-body-part approximation', () {
    test('day-zero user — returns a non-zero positive value', () {
      final result = xpForNextCharacterLevel(
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
      expect(result, greaterThan(0));
    });

    test(
      'mid-level user — returns lifetimeXp + cheapest single-body-part advancement',
      () {
        final cum3 = RankCurve.cumulativeXpForRank(3);
        final cum4 = RankCurve.cumulativeXpForRank(4);
        final lifetimeXp = 5 * cum3 + cum4;
        final result = xpForNextCharacterLevel(
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
        expect(result, greaterThan(lifetimeXp));
        // Pin exact denominator. Cheapest path = chest rank 3→6.
        final cum6 = RankCurve.cumulativeXpForRank(6);
        expect(result, closeTo(lifetimeXp + (cum6 - cum3), 0.01));
      },
    );

    test(
      'just-leveled-up user (rank-sum at /4 boundary) needs 4 more ranks',
      () {
        final cum3 = RankCurve.cumulativeXpForRank(3);
        final cum4 = RankCurve.cumulativeXpForRank(4);
        final lifetimeXp = 4 * cum4 + 2 * cum3;
        final result = xpForNextCharacterLevel(
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
        expect(result, greaterThan(lifetimeXp));
      },
    );

    test(
      'all body parts at maxRank — returns lifetimeXp (100% fill, no further progression)',
      () {
        final maxCumXp = RankCurve.cumulativeXpForRank(RankCurve.maxRank);
        final lifetimeXp = 6 * maxCumXp;
        final result = xpForNextCharacterLevel(
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
        expect(result, lifetimeXp);
      },
    );
  });
}
