import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/rank_curve.dart';

Map<String, dynamic> _loadFixtures() {
  final file = File('test/fixtures/rpg_xp_fixtures.json');
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

const double _eps =
    1e-6; // looser at high ranks where cumulative XP is millions

void main() {
  late final Map<String, dynamic> fixtures;

  setUpAll(() {
    fixtures = _loadFixtures();
  });

  group('Constants parity with Python sim', () {
    test('xp_base == 60', () {
      final meta = fixtures['meta'] as Map<String, dynamic>;
      expect(RankCurve.xpBase, meta['xp_base']);
      expect(RankCurve.xpBase, 60);
    });

    test('xp_growth == 1.10', () {
      final meta = fixtures['meta'] as Map<String, dynamic>;
      expect(RankCurve.xpGrowth, meta['xp_growth']);
      expect(RankCurve.xpGrowth, 1.10);
    });

    test('maxRank == 99', () {
      expect(RankCurve.maxRank, 99);
    });
  });

  group('xpToNext — geometric growth', () {
    test('rank 1 -> 2 needs xpBase = 60', () {
      expect(RankCurve.xpToNext(1), 60.0);
    });

    test('rank n -> n+1 grows by factor 1.10', () {
      final r1 = RankCurve.xpToNext(10);
      final r2 = RankCurve.xpToNext(11);
      expect(r2 / r1, closeTo(1.10, 1e-12));
    });
  });

  group('cumulativeXpForRank — milestones (spec §6 table)', () {
    test('rank 1 cumulative is 0', () {
      expect(RankCurve.cumulativeXpForRank(1), 0.0);
    });

    test('every spec milestone matches the Python sim within tolerance', () {
      final rankCurve = fixtures['rank_curve'] as Map<String, dynamic>;
      final milestones = rankCurve['milestones'] as List<dynamic>;
      for (final raw in milestones) {
        final m = raw as Map<String, dynamic>;
        final rank = m['rank'] as int;
        final expected = (m['cumulative_xp'] as num).toDouble();
        // Use a relative tolerance for the very large numbers (rank 99 ≈ 6.8M).
        final tol = expected.abs() * 1e-9 + _eps;
        expect(
          RankCurve.cumulativeXpForRank(rank),
          closeTo(expected, tol),
          reason: 'cumulativeXpForRank($rank)',
        );
      }
    });

    test('spec milestones — rank 10 ≈ 814 (per spec §6 table)', () {
      // Python sim authoritative value (60 × (1.10^9 - 1) / 0.10).
      expect(RankCurve.cumulativeXpForRank(10), closeTo(814.768614, 1e-4));
    });

    test('spec milestones — rank 50 ≈ 63_431', () {
      expect(RankCurve.cumulativeXpForRank(50), closeTo(63431, 1.0));
    });

    test('spec milestones — rank 99 ≈ 6_832_761', () {
      expect(RankCurve.cumulativeXpForRank(99), closeTo(6832761, 5.0));
    });

    test('cumulative XP is strictly monotonic', () {
      for (var n = 2; n <= RankCurve.maxRank; n++) {
        expect(
          RankCurve.cumulativeXpForRank(n),
          greaterThan(RankCurve.cumulativeXpForRank(n - 1)),
        );
      }
    });

    test('cumulative table length is 99 (one entry per rank)', () {
      expect(RankCurve.cumulativeTable.length, 99);
    });
  });

  group('rankForXp — inverse + boundary semantics', () {
    test('every fixture lookup matches the Python sim', () {
      final rankCurve = fixtures['rank_curve'] as Map<String, dynamic>;
      final lookups = rankCurve['lookups'] as List<dynamic>;
      for (final raw in lookups) {
        final l = raw as Map<String, dynamic>;
        final total = (l['total_xp'] as num).toInt();
        final expected = l['rank'] as int;
        expect(
          RankCurve.rankForXp(total),
          expected,
          reason: 'rankForXp($total)',
        );
      }
    });

    test('zero or negative XP returns 1', () {
      expect(RankCurve.rankForXp(0), 1);
      expect(RankCurve.rankForXp(-100), 1);
    });

    test('exactly at the threshold awards the new rank (>= boundary)', () {
      expect(RankCurve.rankForXp(60), 2); // 60 = cumulative for rank 2
      expect(RankCurve.rankForXp(59.99), 1);
    });

    test('XP saturating beyond rank 99 caps at 99', () {
      expect(RankCurve.rankForXp(10000000), 99);
      expect(RankCurve.rankForXp(double.maxFinite), 99);
    });
  });

  group('xpInRank / xpToNextRank / progressFraction', () {
    test('at exact rank threshold, xpInRank = 0 and progressFraction = 0', () {
      final cum = RankCurve.cumulativeXpForRank(10);
      expect(RankCurve.xpInRank(cum, 10), 0.0);
      expect(RankCurve.progressFraction(cum, 10), 0.0);
    });

    test('halfway through a rank, progressFraction ≈ 0.5', () {
      final cum = RankCurve.cumulativeXpForRank(5);
      final delta = RankCurve.xpToNext(5);
      final mid = cum + delta / 2;
      expect(RankCurve.progressFraction(mid, 5), closeTo(0.5, 1e-9));
    });

    test('xpToNextRank — at threshold equals xpToNext(rank)', () {
      final cum = RankCurve.cumulativeXpForRank(20);
      expect(
        RankCurve.xpToNextRank(cum, 20),
        closeTo(RankCurve.xpToNext(20), 1e-9),
      );
    });

    test('at maxRank, xpToNextRank == 0 and progressFraction == 1', () {
      final cum = RankCurve.cumulativeXpForRank(99);
      expect(RankCurve.xpToNextRank(cum, 99), 0.0);
      expect(RankCurve.progressFraction(cum, 99), 1.0);
    });

    test('total below threshold is treated as 0 (defensive)', () {
      // If a stale rank value is paired with a too-low totalXp, we don't
      // emit a negative remainder.
      expect(RankCurve.xpInRank(0, 10), 0.0);
      expect(RankCurve.progressFraction(0, 10), 0.0);
    });
  });

  group('characterLevel', () {
    test('every fixture case matches', () {
      final cases = fixtures['character_level'] as List<dynamic>;
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final ranks = (c['ranks'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as int),
        );
        final expected = c['character_level'] as int;
        expect(
          characterLevel(ranks),
          expected,
          reason: 'characterLevel($ranks)',
        );
      }
    });

    test('all-1 ranks → level 1', () {
      expect(
        characterLevel({
          'chest': 1,
          'back': 1,
          'legs': 1,
          'shoulders': 1,
          'arms': 1,
          'core': 1,
        }),
        1,
      );
    });

    test('empty map → level 1 (no active ranks → defensive default)', () {
      expect(characterLevel({}), 1);
    });

    test(
      'cardio is excluded in v1 (high cardio rank does not bump character level)',
      () {
        // 6 strength tracks at rank 1, plus cardio at rank 50: lvl computed
        // only from the 6 active tracks, so still rank-1 → lvl 1.
        expect(
          characterLevel({
            'chest': 1,
            'back': 1,
            'legs': 1,
            'shoulders': 1,
            'arms': 1,
            'core': 1,
            'cardio': 50,
          }),
          1,
        );
      },
    );

    test('mixed ranks — sum/4 boundary: ranks total 30, n=6 → lvl 7', () {
      expect(
        characterLevel({
          'chest': 5,
          'back': 5,
          'legs': 5,
          'shoulders': 5,
          'arms': 5,
          'core': 5,
        }),
        7,
      );
    });

    test('all-99 ranks → theoretical max level 148', () {
      expect(
        characterLevel({
          'chest': 99,
          'back': 99,
          'legs': 99,
          'shoulders': 99,
          'arms': 99,
          'core': 99,
        }),
        148,
      );
    });
  });
}
