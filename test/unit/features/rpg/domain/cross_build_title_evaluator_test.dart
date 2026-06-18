/// Unit tests for [CrossBuildTitleEvaluator] (Phase 18e, spec §10.3).
///
/// The evaluator is a pure function that receives a body-part rank map and
/// returns the set of cross-build slugs that fire for that distribution.
/// Each of the five predicates is a different shape of structural condition
/// (ratio, sum, spread, floor) and the seams between "fires" and "doesn't
/// fire" are the exact rank values consumers will hit at the boundary.
///
/// These tests pin every predicate's fire/no-fire boundary so the SQL mirror
/// in `00043_cross_build_titles_backfill.sql` can be edited without quietly
/// drifting from the Dart contract — if a predicate changes here, the SQL
/// side must change in lockstep (and vice-versa). Each group locks one
/// trigger; the cross-cutting tests at the end pin "multiple fire at once"
/// and "cardio is silently ignored" for parity with the SQL `evaluate_*`
/// function.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/cross_build_title_evaluator.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';

/// Build a rank map for the six active body parts with named overrides.
/// Defaults to rank 1 — matches the SQL default-row contract and the
/// `evaluate` method's missing-entry projection.
Map<BodyPart, int> _ranks({
  int chest = 1,
  int back = 1,
  int legs = 1,
  int shoulders = 1,
  int arms = 1,
  int core = 1,
  int cardio = 1,
}) => {
  BodyPart.chest: chest,
  BodyPart.back: back,
  BodyPart.legs: legs,
  BodyPart.shoulders: shoulders,
  BodyPart.arms: arms,
  BodyPart.core: core,
  BodyPart.cardio: cardio,
};

void main() {
  group('CrossBuildTitleEvaluator — pillar_walker', () {
    test('legs == 40 AND legs == 2 * arms (boundary) → fires', () {
      // legs at the floor (40) and at exactly 2x arms (40 vs 20). Both
      // conditions are inclusive — the predicate uses `>=` on both sides.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(legs: 40, arms: 20),
      );
      expect(result, contains('pillar_walker'));
    });

    test('legs == 39 (one below floor) → does not fire', () {
      // Boundary: legs < 40 short-circuits before the ratio check.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(legs: 39, arms: 19),
      );
      expect(result, isNot(contains('pillar_walker')));
    });

    test('legs == 40, arms == 21 (ratio fails) → does not fire', () {
      // 40 < 2 * 21 = 42 → ratio breaks even though legs cleared the floor.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(legs: 40, arms: 21),
      );
      expect(result, isNot(contains('pillar_walker')));
    });

    test('legs == 60, arms == 1 (default rank) → fires', () {
      // Default-row arms (rank 1) trivially satisfies the 2x condition.
      // This is the common shape: a leg-day-only lifter early in their saga.
      expect(
        CrossBuildTitleEvaluator.evaluate(_ranks(legs: 60)),
        contains('pillar_walker'),
      );
    });
  });

  group('CrossBuildTitleEvaluator — broad_shouldered', () {
    test(
      'upper-body floor + ratio at exact 1.6x boundary → fires (BUG-015)',
      () {
        // BUG-015 rebalance (2026-05-02): the predicate is now
        // `upper * 10 >= lower * 16` (i.e. upper >= 1.6 * lower). At the exact
        // boundary upper = 96, lower = 60 → 96 * 10 = 960, 60 * 16 = 960 →
        // equality fires (the predicate uses `>=`). Each upper track also
        // clears the per-track floor of 30.
        final result = CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 32, back: 32, shoulders: 32, legs: 30, core: 30),
        );
        expect(result, contains('broad_shouldered'));
      },
    );

    test('chest below 30 (others above) → does not fire', () {
      // The per-track upper-body floor short-circuits before the ratio.
      // chest=29 fails the floor even though the sum (29+30+30=89) still
      // beats 1.6 * (20+10=30) = 48.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(chest: 29, back: 30, shoulders: 30, legs: 20, core: 10),
      );
      expect(result, isNot(contains('broad_shouldered')));
    });

    test(
      'all upper tracks at 30 but ratio just under 1.6x → does not fire (BUG-015)',
      () {
        // upper = 90, lower = 57 → 90 * 10 = 900, 57 * 16 = 912 → 900 < 912.
        // 1.5789...× is just under 1.6×, so the predicate fails by a hair
        // while every upper track still clears the rank-30 floor.
        final result = CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 30, back: 30, shoulders: 30, legs: 30, core: 27),
        );
        expect(result, isNot(contains('broad_shouldered')));
      },
    );

    test(
      'ratio just over 1.6x (1.61x) → fires (BUG-015 boundary upper bound)',
      () {
        // upper = 96, lower = 59 → 96 * 10 = 960, 59 * 16 = 944 → 960 >= 944.
        // Slightly above 1.6× (1.6271...×) — predicate fires.
        final result = CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 32, back: 32, shoulders: 32, legs: 30, core: 29),
        );
        expect(result, contains('broad_shouldered'));
      },
    );

    test('realistic upper-specialist build (PO target) → fires (BUG-015)', () {
      // PO scenario: typical Brazilian academy lifter who pushes/pulls
      // 3-4×/week and legs 1×/week. With chest/back/shoulders at 50 each
      // (upper = 150) and legs at 60 + core at 30 (lower = 90), the old
      // 2× predicate failed (2*90 = 180 > 150) while 1.6× passes
      // (1.6*90 = 144 < 150). This is the realistic-build case the
      // rebalance was specifically chosen to admit.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(chest: 50, back: 50, shoulders: 50, legs: 60, core: 30),
      );
      expect(result, contains('broad_shouldered'));
    });
  });

  group('CrossBuildTitleEvaluator — even_handed', () {
    test('every track exactly 30, spread 0% → fires', () {
      // Boundary: every track at the floor (30) and the spread is zero.
      // The predicate's `evenHandedMinRank == 30` is inclusive.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 30,
          back: 30,
          legs: 30,
          shoulders: 30,
          arms: 30,
          core: 30,
        ),
      );
      expect(result, contains('even_handed'));
    });

    test('one track below floor (rank 29), others 30+ → does not fire', () {
      // Boundary: even at perfect balance among the rest, a single track at
      // 29 short-circuits before the spread is computed. This mirrors
      // ClassResolver's Ascendant floor at a higher rank value.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 30,
          back: 30,
          legs: 30,
          shoulders: 30,
          arms: 30,
          core: 29,
        ),
      );
      expect(result, isNot(contains('even_handed')));
    });

    test('spread exactly 30% → fires (boundary inclusive)', () {
      // (50 - 35) / 50 = 0.30. Both endpoints clear the rank-30 floor; the
      // predicate uses `<=` so equality fires.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 50,
          back: 35,
          legs: 35,
          shoulders: 35,
          arms: 35,
          core: 35,
        ),
      );
      expect(result, contains('even_handed'));
    });

    test('spread just over 30% → does not fire', () {
      // (50 - 34) / 50 = 0.32 > 0.30. The predicate fails by a hair while
      // every track still clears the rank-30 floor.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 50,
          back: 34,
          legs: 34,
          shoulders: 34,
          arms: 34,
          core: 34,
        ),
      );
      expect(result, isNot(contains('even_handed')));
    });
  });

  group('CrossBuildTitleEvaluator — iron_bound', () {
    test('chest, back, legs all 60 + cardio default (low) → fires', () {
      // Boundary: every big-three track at the inclusive floor (60) AND cardio
      // at the default rank 1 (≤ 10). Phase 38f restored the low-cardio
      // condition — a strength-pure powerlifter still fires.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(chest: 60, back: 60, legs: 60),
      );
      expect(result, contains('iron_bound'));
    });

    test('cardio == 10 (boundary, inclusive) → still fires', () {
      // The low-cardio condition is `cardio <= 10` — rank 10 is the inclusive
      // ceiling.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(chest: 60, back: 60, legs: 60, cardio: 10),
      );
      expect(result, contains('iron_bound'));
    });

    test(
      'cardio == 11 (one above the ceiling) → does not fire (Phase 38f)',
      () {
        // A powerlifter who also built cardio past rank 10 is no longer
        // strength-pure — they route to the_forged_wind / storm_tempered
        // instead. iron_bound's low-cardio condition gates them out of FUTURE
        // awards (already-earned rows are never revoked — SQL-side concern).
        final result = CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 60, back: 60, legs: 60, cardio: 11),
        );
        expect(result, isNot(contains('iron_bound')));
      },
    );

    test('one of (chest, back, legs) at 59 → does not fire', () {
      // The predicate is AND-of-three; a single track below the floor
      // short-circuits.
      expect(
        CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 59, back: 60, legs: 60),
        ),
        isNot(contains('iron_bound')),
      );
      expect(
        CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 60, back: 59, legs: 60),
        ),
        isNot(contains('iron_bound')),
      );
      expect(
        CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 60, back: 60, legs: 59),
        ),
        isNot(contains('iron_bound')),
      );
    });

    test('upper-body-only: chest+back at 60 but legs 30 → does not fire', () {
      // Defensive: the spec specifically requires the big-three (squat-row-
      // bench heuristic). A user who skips legs cannot earn it.
      expect(
        CrossBuildTitleEvaluator.evaluate(
          _ranks(chest: 60, back: 60, legs: 30, shoulders: 60, arms: 60),
        ),
        isNot(contains('iron_bound')),
      );
    });
  });

  group('CrossBuildTitleEvaluator — saga_forged', () {
    test('every active track at 60 (boundary) → fires', () {
      // Boundary: every track at the inclusive floor (60). All five other
      // predicates fire too in this distribution — the result list is
      // dense.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 60,
          core: 60,
        ),
      );
      expect(result, contains('saga_forged'));
    });

    test('one track at 59 → does not fire', () {
      // Single sub-floor entry breaks the AND-of-six predicate.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 60,
          core: 59,
        ),
      );
      expect(result, isNot(contains('saga_forged')));
    });

    test('all five strength tracks at 99 except arms at 1 → does not fire', () {
      // Defensive: even a heroic 99/99/99/99/99 distribution fails if a
      // single body part is left untrained. saga_forged is "every track has
      // done the work" not "most tracks have done the work".
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(chest: 99, back: 99, legs: 99, shoulders: 99, arms: 1, core: 99),
      );
      expect(result, isNot(contains('saga_forged')));
    });
  });

  group('CrossBuildTitleEvaluator — the_forged_wind (Phase 38f)', () {
    test('all six strength tracks 60 AND cardio 60 (boundary) → fires', () {
      // The complete-athlete apex: saga_forged PLUS a fully-forged cardio
      // engine. Every track (incl. cardio) at the inclusive floor 60.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 60,
          core: 60,
          cardio: 60,
        ),
      );
      expect(result, contains('the_forged_wind'));
    });

    test('all six strength 60 but cardio 59 → does not fire', () {
      // One below the cardio floor breaks the predicate even with a complete
      // strength build. saga_forged still fires (cardio is not its concern).
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 60,
          core: 60,
          cardio: 59,
        ),
      );
      expect(result, isNot(contains('the_forged_wind')));
      expect(result, contains('saga_forged'));
    });

    test('cardio 60 but one strength track 59 → does not fire', () {
      // A fully-forged cardio engine without complete strength is
      // storm_tempered territory, not the_forged_wind.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 59,
          core: 60,
          cardio: 60,
        ),
      );
      expect(result, isNot(contains('the_forged_wind')));
    });
  });

  group('CrossBuildTitleEvaluator — storm_tempered (Phase 38f)', () {
    test('cardio 60 AND all six strength tracks 30 (boundary) → fires', () {
      // The cardio-led counterpart to iron_bound: a fully-forged cardio engine
      // with broad-but-not-elite strength. Cardio at floor 60, strength at
      // the inclusive floor 30.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 30,
          back: 30,
          legs: 30,
          shoulders: 30,
          arms: 30,
          core: 30,
          cardio: 60,
        ),
      );
      expect(result, contains('storm_tempered'));
    });

    test('cardio 59 (below floor) → does not fire', () {
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 30,
          back: 30,
          legs: 30,
          shoulders: 30,
          arms: 30,
          core: 30,
          cardio: 59,
        ),
      );
      expect(result, isNot(contains('storm_tempered')));
    });

    test('cardio 60 but one strength track 29 → does not fire', () {
      // "Tempered, not narrowed" — letting a single strength track wither
      // below rank 30 disqualifies the title.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 30,
          back: 30,
          legs: 30,
          shoulders: 30,
          arms: 29,
          core: 30,
          cardio: 60,
        ),
      );
      expect(result, isNot(contains('storm_tempered')));
    });

    test('complete athlete (all 60 incl. cardio) fires BOTH cardio titles', () {
      // At all-60 the_forged_wind fires (strength ≥ 60 + cardio ≥ 60) AND
      // storm_tempered fires (cardio ≥ 60 + strength ≥ 30). Both are valid
      // structural distinctions at the apex.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 60,
          core: 60,
          cardio: 60,
        ),
      );
      expect(result, containsAll(['the_forged_wind', 'storm_tempered']));
    });
  });

  group('CrossBuildTitleEvaluator — multi-fire & catalog order', () {
    test('every track at 60 fires every predicate in catalog order', () {
      // Saturation point — every predicate is structurally satisfied.
      // The list order must match `CrossBuildTriggerId.values` so the
      // celebration queue can rely on a stable presentation order.
      final result = CrossBuildTitleEvaluator.evaluate(
        _ranks(
          chest: 60,
          back: 60,
          legs: 60,
          shoulders: 60,
          arms: 30,
          core: 60,
        ),
      );
      // legs 60 >= 2 * arms 30 → pillar_walker
      // chest+back+shoulders = 180 >= 2 * (60+60 = 120) = 240? 180 < 240
      //   → broad_shouldered NO
      // even_handed: arms 30 within 30% of max 60? (60-30)/60 = 0.50 NO
      // iron_bound: chest, back, legs >= 60 YES
      // saga_forged: arms < 60 NO
      expect(result, ['pillar_walker', 'iron_bound']);
    });

    test('rank 1 default-row distribution → empty result', () {
      // A brand-new user fires nothing. Every predicate has at least a
      // rank-30 floor.
      expect(CrossBuildTitleEvaluator.evaluate(_ranks()), isEmpty);
    });

    test('high cardio does not perturb the strength-only predicates', () {
      // saga_forged + the strength predicates are cardio-independent: a huge
      // cardio value cannot disqualify saga_forged. (Phase 38f: high cardio
      // DOES gate iron_bound out and turns the_forged_wind on — pinned in the
      // dedicated groups above; here we only assert the strength-only
      // distinctions are unaffected.)
      final ranks = _ranks(
        chest: 60,
        back: 60,
        legs: 60,
        shoulders: 60,
        arms: 60,
        core: 60,
        cardio: 99,
      );
      final result = CrossBuildTitleEvaluator.evaluate(ranks);
      expect(result, contains('saga_forged'));
      // cardio 99 > 10 → iron_bound no longer fires; the_forged_wind does.
      expect(result, isNot(contains('iron_bound')));
      expect(result, contains('the_forged_wind'));
    });

    // -------------------------------------------------------------------------
    // BUG-014 (Cluster 3) — gapHintFor cross-build progress hints
    // -------------------------------------------------------------------------
    group('gapHintFor — cross-build progress hints (BUG-014)', () {
      test('pillar_walker: surfaces gap to legs floor 40', () {
        final hint = CrossBuildTitleEvaluator.gapHintFor(
          'pillar_walker',
          _ranks(legs: 32),
        );
        expect(hint, isNotNull);
        expect(hint!.bodyPart, BodyPart.legs);
        expect(hint.gap, 8);
      });

      test(
        'pillar_walker: returns null when legs already clears the floor',
        () {
          // legs >= 40 → predicate satisfied along this axis. UI falls back
          // to "predicate satisfied" copy.
          expect(
            CrossBuildTitleEvaluator.gapHintFor(
              'pillar_walker',
              _ranks(legs: 50, arms: 1),
            ),
            isNull,
          );
        },
      );

      test(
        'broad_shouldered: surfaces smallest gap among chest/back/shoulders',
        () {
          // chest=20 (gap 10), back=15 (gap 15), shoulders=29 (gap 1). The
          // smallest gap is shoulders at 1.
          final hint = CrossBuildTitleEvaluator.gapHintFor(
            'broad_shouldered',
            _ranks(chest: 20, back: 15, shoulders: 29),
          );
          expect(hint, isNotNull);
          expect(hint!.bodyPart, BodyPart.shoulders);
          expect(hint.gap, 1);
        },
      );

      test(
        'broad_shouldered: returns null when all three upper guards clear floor',
        () {
          // All three >= 30. Even if the ratio fails, the gap-along-floor
          // axis is satisfied → no body-part-floor hint to surface.
          expect(
            CrossBuildTitleEvaluator.gapHintFor(
              'broad_shouldered',
              _ranks(chest: 30, back: 30, shoulders: 30),
            ),
            isNull,
          );
        },
      );

      test('even_handed: surfaces single body part furthest from floor 30', () {
        // arms=10 (gap 20), core=29 (gap 1), others=35. The largest gap
        // is arms at 20.
        final hint = CrossBuildTitleEvaluator.gapHintFor(
          'even_handed',
          _ranks(
            chest: 35,
            back: 35,
            legs: 35,
            shoulders: 35,
            arms: 10,
            core: 29,
          ),
        );
        expect(hint, isNotNull);
        expect(hint!.bodyPart, BodyPart.arms);
        expect(hint.gap, 20);
      });

      test('iron_bound: surfaces smallest gap among chest/back/legs to 60', () {
        // chest=50 (gap 10), back=40 (gap 20), legs=58 (gap 2). Smallest
        // gap is legs at 2.
        final hint = CrossBuildTitleEvaluator.gapHintFor(
          'iron_bound',
          _ranks(chest: 50, back: 40, legs: 58),
        );
        expect(hint, isNotNull);
        expect(hint!.bodyPart, BodyPart.legs);
        expect(hint.gap, 2);
      });

      test('saga_forged: surfaces single body part furthest from floor 60', () {
        // arms=20 (gap 40), others=60. arms is furthest.
        final hint = CrossBuildTitleEvaluator.gapHintFor(
          'saga_forged',
          _ranks(
            chest: 60,
            back: 60,
            legs: 60,
            shoulders: 60,
            arms: 20,
            core: 60,
          ),
        );
        expect(hint, isNotNull);
        expect(hint!.bodyPart, BodyPart.arms);
        expect(hint.gap, 40);
      });

      test('unknown slug → returns null (defensive)', () {
        expect(
          CrossBuildTitleEvaluator.gapHintFor('not_a_real_slug', _ranks()),
          isNull,
        );
      });

      test(
        'empty ranks map → defaults all body parts to rank 1, hints compute correctly',
        () {
          // Brand-new user: the ranks map may be empty (no rows in
          // body_part_progress yet). The evaluator uses `ranks[bp] ?? 1`
          // so every missing entry projects to rank 1 — matching the SQL
          // default-row contract. The hints must still return a meaningful
          // gap rather than crashing or returning null.
          //
          // pillar_walker: legs defaults to 1, floor=40 → gap=39.
          final hint = CrossBuildTitleEvaluator.gapHintFor('pillar_walker', {});
          expect(hint, isNotNull);
          expect(hint!.bodyPart, BodyPart.legs);
          expect(hint.gap, 39); // 40 - 1

          // iron_bound: chest defaults to 1, back to 1, legs to 1.
          // Smallest gap = 59 (60 - 1) for all three — first-found
          // tie-break selects chest (first in the iteration order of the
          // `parts` list: [chest, back, legs]).
          final ironHint = CrossBuildTitleEvaluator.gapHintFor(
            'iron_bound',
            {},
          );
          expect(ironHint, isNotNull);
          expect(ironHint!.bodyPart, BodyPart.chest);
          expect(ironHint.gap, 59); // 60 - 1
        },
      );

      test('rank=0 explicit entry → treated as 0, gap computed correctly', () {
        // Defensive: the domain never produces rank 0 (SQL default is 1)
        // but if the caller explicitly passes 0 the function must not
        // crash. `_smallestGapAmong` does NOT use the ?? 1 fallback —
        // it reads directly from the passed `ranks` map (which may
        // contain an explicit 0). gap = floor - 0 = floor.
        final hint = CrossBuildTitleEvaluator.gapHintFor('pillar_walker', {
          BodyPart.legs: 0,
        });
        expect(hint, isNotNull);
        expect(hint!.bodyPart, BodyPart.legs);
        // floor is 40, rank is 0 → gap is 40.
        expect(hint.gap, 40);
      });

      test('value-equal hints compare equal (toString + hashCode)', () {
        const a = CrossBuildHint(bodyPart: BodyPart.chest, gap: 5);
        const b = CrossBuildHint(bodyPart: BodyPart.chest, gap: 5);
        const c = CrossBuildHint(bodyPart: BodyPart.chest, gap: 6);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
        expect(a, isNot(equals(c)));
        expect(a.toString(), contains('chest'));
        expect(a.toString(), contains('5'));
      });
    });

    test('missing entries default to rank 1', () {
      // Defensive: if a body part is absent from the ranks map, the
      // evaluator projects rank 1 (matches the SQL COALESCE default and
      // RpgProgressSnapshot.progressFor). With chest/back/legs at 60 and
      // shoulders/arms/core absent, the strength predicates fire:
      //   * pillar_walker: legs 60 >= 2 * arms (defaulted to 1) → fires
      //   * iron_bound: chest/back/legs all 60 → fires
      // saga_forged + even_handed need shoulders/arms/core too, so they
      // do not fire.
      final ranks = {BodyPart.chest: 60, BodyPart.back: 60, BodyPart.legs: 60};
      expect(CrossBuildTitleEvaluator.evaluate(ranks), [
        'pillar_walker',
        'iron_bound',
      ]);
    });
  });
}
