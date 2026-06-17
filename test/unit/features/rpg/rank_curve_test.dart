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

    test('spec milestones — rank 10 ≈ 814 (geometric band)', () {
      // Phase 29 v2: rank 10 still in the geometric band (1..20).
      // Python sim authoritative value (60 × (1.10^9 - 1) / 0.10).
      expect(RankCurve.cumulativeXpForRank(10), closeTo(814.768614, 1e-4));
    });

    test('spec milestones — rank 20 sits exactly at the piecewise '
        'breakpoint', () {
      // Phase 29 v2: cumulative for rank 20 ≈ 3069.55 (end of geometric
      // band). Rank 21 = rank 20 cumulative + LINEAR_XP_PER_RANK exactly.
      expect(
        RankCurve.cumulativeXpForRank(RankCurve.xpGrowthBreakpoint),
        closeTo(3069.545, 1e-3),
      );
      expect(
        RankCurve.cumulativeXpForRank(RankCurve.xpGrowthBreakpoint + 1) -
            RankCurve.cumulativeXpForRank(RankCurve.xpGrowthBreakpoint),
        closeTo(RankCurve.linearXpPerRank, 1e-9),
      );
      expect(RankCurve.linearXpPerRank, 367.0);
    });

    test('spec milestones — rank 50 in the linear band', () {
      // Phase 29 v2 linear: cumulative(20) + (50 - 20) × 367 ≈ 14079.55
      expect(RankCurve.cumulativeXpForRank(50), closeTo(14079.55, 1.0));
    });

    test('spec milestones — rank 99 in the linear band', () {
      // Phase 29 v2 linear: cumulative(20) + (99 - 20) × 367 ≈ 32062.55
      expect(RankCurve.cumulativeXpForRank(99), closeTo(32062.55, 1.0));
    });

    test('every linear-band step adds exactly LINEAR_XP_PER_RANK', () {
      for (
        var n = RankCurve.xpGrowthBreakpoint + 1;
        n <= RankCurve.maxRank;
        n++
      ) {
        final delta =
            RankCurve.cumulativeXpForRank(n) -
            RankCurve.cumulativeXpForRank(n - 1);
        expect(
          delta,
          closeTo(RankCurve.linearXpPerRank, 1e-9),
          reason: 'rank $n delta should be ${RankCurve.linearXpPerRank}',
        );
      }
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
      'cardio contributes to character level (Phase 38e — 7 active tracks)',
      () {
        // 6 strength tracks at rank 1 + cardio at rank 50: cardio is now in
        // the active set, so it DOES bump the level. Σ=55, n=7 →
        // floor((55-7)/4)+1 = floor(48/4)+1 = 13.
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
          13,
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

    test('all-99 across seven active tracks → max level 172 (Phase 38e)', () {
      // Phase 38e: cardio joins the active set, so the all-maxed computed
      // ceiling rises 148 → 172. Denominator stays 4. (The saga_eternal
      // TITLE threshold stays 148 — that's a title-table concern; the
      // 172-cap title is Phase 38f.)
      expect(
        characterLevel({
          'chest': 99,
          'back': 99,
          'legs': 99,
          'shoulders': 99,
          'arms': 99,
          'core': 99,
          'cardio': 99,
        }),
        172,
      );
    });

    test('thesis — pure-strength level never regresses post-38e '
        '(denominator-stays-4 proof)', () {
      // The never-regress invariant: a user who has trained ONLY the six
      // strength tracks (cardio absent from the map, i.e. untrained / rank
      // 1) must land on the EXACT same Character Level the pre-38e 6-track
      // formula produced. Because cardio at rank 1 adds +1 to both Σ ranks
      // and N_active, the numerator (Σ − N) is unchanged.
      //
      // For every strength-rank combination, the level computed over the
      // six present keys (cardio absent → skipped) equals the level
      // computed when cardio is explicitly rank 1 (present, contributes 0
      // to the numerator). Both equal the legacy 6-track value.
      const combos = <Map<String, int>>[
        {
          'chest': 1,
          'back': 1,
          'legs': 1,
          'shoulders': 1,
          'arms': 1,
          'core': 1,
        },
        {
          'chest': 5,
          'back': 5,
          'legs': 5,
          'shoulders': 5,
          'arms': 5,
          'core': 5,
        },
        {
          'chest': 20,
          'back': 18,
          'legs': 22,
          'shoulders': 15,
          'arms': 19,
          'core': 12,
        },
        {
          'chest': 50,
          'back': 50,
          'legs': 50,
          'shoulders': 50,
          'arms': 50,
          'core': 50,
        },
        {
          'chest': 99,
          'back': 99,
          'legs': 99,
          'shoulders': 99,
          'arms': 99,
          'core': 99,
        },
      ];
      for (final strengthRanks in combos) {
        final sixKeyLevel = characterLevel(strengthRanks);
        final withCardioRank1 = characterLevel({...strengthRanks, 'cardio': 1});
        expect(
          withCardioRank1,
          sixKeyLevel,
          reason:
              'pure-strength user (cardio rank 1) regressed for $strengthRanks',
        );
      }
    });

    // ---------------------------------------------------------------------------
    // Regression test — PR #252 character-level formula fix
    //
    // The buggy formula applied to character_level computation was:
    //   `rpg_rank_for_xp(SUM(total_xp_per_body_part))`
    //
    // This is wrong because `rpg_rank_for_xp` is the PER-body-part XP→rank
    // curve — applying it to a SUM across all body parts gives a result that
    // drifts wildly from the canonical formula.
    //
    // Canonical formula (spec §7 / character_state view in migration 00040 §9):
    //   character_level = GREATEST(1, FLOOR((SUM(rank) − COUNT(*)) / 4.0) + 1)
    //
    // This test pins a concrete divergence example so that if a future refactor
    // re-introduces the buggy formula, the test fails immediately with a
    // concrete signal. The test:
    //   (a) asserts the canonical formula returns 4 for 6 BPs at rank 3
    //   (b) asserts `rankForXp(sumXp)` returns 9 (the buggy result)
    //   (c) asserts the two formulas DIVERGE at this input — if someone were
    //       to use rankForXp(sumXp) for character_level the test would fail
    //       because the wrong formula would produce 9, not 4.
    // ---------------------------------------------------------------------------
    test('regression PR#252: canonical formula diverges from rankForXp(sumXp) '
        '— 6 BPs at rank 3 → char-level 4, NOT rankForXp(756) = 9', () {
      // 6 body parts, each at rank 3.
      // Canonical: floor((18 - 6) / 4) + 1 = floor(12/4) + 1 = 4.
      const ranks = {
        'chest': 3,
        'back': 3,
        'legs': 3,
        'shoulders': 3,
        'arms': 3,
        'core': 3,
      };
      expect(characterLevel(ranks), 4);

      // Per-BP XP at rank 3 = cumulativeXpForRank(3).
      // = 60 × (1.10² − 1) / 0.10 = 60 × 2.1 = 126.0
      final xpAtRank3 = RankCurve.cumulativeXpForRank(3);
      expect(xpAtRank3, closeTo(126.0, 1e-6));

      // SUM across 6 BPs → 756.0
      final sumXp = 6 * xpAtRank3;
      expect(sumXp, closeTo(756.0, 1e-6));

      // The BUGGY formula: rpg_rank_for_xp applied to the sum.
      // 756 is above cumulativeXpForRank(9) ≈ 685.7 and below
      // cumulativeXpForRank(10) ≈ 814.8 → rankForXp(756) = 9.
      final buggyLevel = RankCurve.rankForXp(sumXp);
      expect(buggyLevel, 9);

      // Critical assertion: the two formulas DISAGREE.
      // If someone reintroduces the buggy `rankForXp(sumXp)` formula, this
      // assertion would catch it (because rankForXp returns 9, not 4).
      expect(
        characterLevel(ranks),
        isNot(buggyLevel),
        reason:
            'characterLevel(6×rank3) must NOT equal rankForXp(sumXp). '
            'The canonical formula gives 4; rankForXp(756) gives 9. '
            'These must diverge — if they are equal, the regression '
            'from PR#252 has been reintroduced.',
      );
    });

    test('regression PR#252: high-rank single-BP skew — 1 BP at rank 10, '
        '5 at rank 1 → char-level 3 (not rankForXp-inflated)', () {
      // One specialist at rank 10, 5 beginners at rank 1.
      // Canonical: floor((10+1+1+1+1+1 - 6)/4) + 1 = floor(9/4) + 1 = 3.
      const ranks = {
        'chest': 10,
        'back': 1,
        'legs': 1,
        'shoulders': 1,
        'arms': 1,
        'core': 1,
      };
      expect(characterLevel(ranks), 3);

      // SUM(total_xp) ≈ cumulativeXpForRank(10) + 5×0 = 814.77
      final xpAtRank10 = RankCurve.cumulativeXpForRank(10);
      // rankForXp(814.77) → rank 10 (just crossed rank-10 threshold)
      final buggyLevel = RankCurve.rankForXp(xpAtRank10);
      expect(buggyLevel, 10);

      // Canonical must disagree with the inflated buggy result.
      expect(
        characterLevel(ranks),
        isNot(buggyLevel),
        reason:
            'characterLevel(chest=10, 5×rank1) must NOT equal '
            'rankForXp(sumXp). canonical=3, buggy=10.',
      );
    });
  });
}
