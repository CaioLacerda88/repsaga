/// Unit tests for [ClassResolver] (Phase 18e, spec §9.2).
///
/// The resolver is a pure function: given a per-body-part rank distribution,
/// return the user's derived [CharacterClass]. Three precedence rules apply,
/// in this order:
///
///   1. `max < 5` → [CharacterClass.initiate] (no other branch can fire)
///   2. `min >= 5 AND (max - min) / max <= 0.30` → [CharacterClass.ascendant]
///      (overrides dominant lookup)
///   3. otherwise → `dominantClass[argmax(ranks)]`
///
/// These tests pin every branch + boundary so a future contributor changing
/// the spread fraction or the floor can't silently break the contract.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/class_resolver.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';

/// Build a rank map for the six active body parts with named overrides.
/// Defaults to rank 1 — matches the SQL default-row contract.
Map<BodyPart, int> _ranks({
  int chest = 1,
  int back = 1,
  int legs = 1,
  int shoulders = 1,
  int arms = 1,
  int core = 1,
}) => {
  BodyPart.chest: chest,
  BodyPart.back: back,
  BodyPart.legs: legs,
  BodyPart.shoulders: shoulders,
  BodyPart.arms: arms,
  BodyPart.core: core,
};

void main() {
  group('ClassResolver — Initiate floor', () {
    test('all ranks 1 → Initiate', () {
      // Default-row state for a brand-new user.
      expect(ClassResolver.resolve(_ranks()), CharacterClass.initiate);
    });

    test('every rank == 4 → Initiate (max < 5 floor)', () {
      // Boundary: the floor predicate is `max < initiateCeiling (5)`. Rank 4
      // across the board still routes to Initiate even though the spread is
      // perfect — Initiate wins over Ascendant when no track has crossed
      // the rank-5 threshold yet (spec §9.1 alignment with first title
      // unlock).
      expect(
        ClassResolver.resolve(
          _ranks(chest: 4, back: 4, legs: 4, shoulders: 4, arms: 4, core: 4),
        ),
        CharacterClass.initiate,
      );
    });

    test('one rank == 5 (others 1) → no longer Initiate', () {
      // Boundary: the very first rank-5 crossing kicks the user out of
      // Initiate. With chest=5 and everything else at 1, the spread is
      // (5-1)/5 = 0.80 — too high for Ascendant — so the dominant lookup
      // wins (chest → Bulwark).
      expect(ClassResolver.resolve(_ranks(chest: 5)), CharacterClass.bulwark);
    });

    test('empty input → Initiate', () {
      // Defensive: if a caller hands in an empty map, the resolver projects
      // every active body part to rank 1 → Initiate floor fires.
      expect(ClassResolver.resolve(const {}), CharacterClass.initiate);
    });
  });

  group('ClassResolver — Ascendant balance class', () {
    test('all ranks at exactly 5 → Ascendant', () {
      // Boundary: minRank == ascendantMinRank (5), spread == 0%. The first
      // perfectly-balanced lifter past the consolidation floor.
      expect(
        ClassResolver.resolve(
          _ranks(chest: 5, back: 5, legs: 5, shoulders: 5, arms: 5, core: 5),
        ),
        CharacterClass.ascendant,
      );
    });

    test('all ranks at 50, spread 0% → Ascendant', () {
      expect(
        ClassResolver.resolve(
          _ranks(
            chest: 50,
            back: 50,
            legs: 50,
            shoulders: 50,
            arms: 50,
            core: 50,
          ),
        ),
        CharacterClass.ascendant,
      );
    });

    test('spread exactly 30% → Ascendant (boundary inclusive)', () {
      // (10 - 7) / 10 = 0.30 — the spec locks <= so equality fires.
      expect(
        ClassResolver.resolve(
          _ranks(chest: 10, back: 7, legs: 7, shoulders: 7, arms: 7, core: 7),
        ),
        CharacterClass.ascendant,
      );
    });

    test('spread just over 30% → falls through to dominant lookup', () {
      // (10 - 6) / 10 = 0.40 — fails the 30% predicate; argmax = chest
      // (the only track at 10) → Bulwark.
      expect(
        ClassResolver.resolve(
          _ranks(chest: 10, back: 6, legs: 6, shoulders: 6, arms: 6, core: 6),
        ),
        CharacterClass.bulwark,
      );
    });

    test('min rank 4 (one body part below floor) → not Ascendant', () {
      // The Ascendant predicate gates on `minRank >= 5`. A balanced
      // distribution with one body part still under 5 routes to dominant
      // lookup instead. With the others at 6 and arms at 4, max is back/
      // chest/legs/shoulders/core = 6. Tie among five tracks — alphabetical
      // tie-break picks back over the others (back < chest < core < legs <
      // shoulders) → Sentinel.
      final result = ClassResolver.resolve(
        _ranks(chest: 6, back: 6, legs: 6, shoulders: 6, arms: 4, core: 6),
      );
      expect(result, CharacterClass.sentinel);
    });
  });

  group('ClassResolver — dominant-class lookup (spec §9.2)', () {
    test('arms-dominant → Berserker', () {
      // arms way out front, others below the spread threshold for Ascendant.
      expect(
        ClassResolver.resolve(_ranks(arms: 30, chest: 10)),
        CharacterClass.berserker,
      );
    });

    test('chest-dominant → Bulwark', () {
      expect(
        ClassResolver.resolve(_ranks(chest: 30, arms: 10)),
        CharacterClass.bulwark,
      );
    });

    test('back-dominant → Sentinel', () {
      expect(
        ClassResolver.resolve(_ranks(back: 30, arms: 10)),
        CharacterClass.sentinel,
      );
    });

    test('legs-dominant → Pathfinder', () {
      expect(
        ClassResolver.resolve(_ranks(legs: 30, arms: 10)),
        CharacterClass.pathfinder,
      );
    });

    test('shoulders-dominant → Atlas', () {
      expect(
        ClassResolver.resolve(_ranks(shoulders: 30, arms: 10)),
        CharacterClass.atlas,
      );
    });

    test('core-dominant → Anchor', () {
      expect(
        ClassResolver.resolve(_ranks(core: 30, arms: 10)),
        CharacterClass.anchor,
      );
    });
  });

  group('ClassResolver — tie-break determinism', () {
    test(
      'tied max ranks below the spread predicate → alphabetical tie-break',
      () {
        // chest and back both at 10, others at 5. Spread (10-5)/10 = 0.50,
        // exceeds 30% so Ascendant doesn't fire. Tie-break by alphabetical
        // body-part slug: back < chest → Sentinel wins.
        expect(
          ClassResolver.resolve(
            _ranks(
              chest: 10,
              back: 10,
              legs: 5,
              shoulders: 5,
              arms: 5,
              core: 5,
            ),
          ),
          CharacterClass.sentinel,
        );
      },
    );
  });

  group('ClassResolver — cardio excluded from class/Ascendant (Phase 38e)', () {
    test('cardio entry does not affect dominant classification', () {
      // Phase 38e: cardio IS in activeBodyParts (it counts toward Character
      // Level) but the resolver projects only over strengthBodyParts, so a
      // huge cardio rank is dropped — chest still dominates → Bulwark.
      final ranks = _ranks(chest: 30, arms: 10);
      ranks[BodyPart.cardio] = 99;
      expect(ClassResolver.resolve(ranks), CharacterClass.bulwark);
    });

    test('cardio cannot break the Ascendant balance check', () {
      // Six strength tracks perfectly balanced at rank 10 → Ascendant
      // (min≥5, spread 0). A cardio rank of 99 would, if it leaked into the
      // spread, blow (max−min)/max past 0.30 and demote to a dominant class.
      // Because cardio is excluded from the resolver input, Ascendant holds.
      final ranks = _ranks(
        chest: 10,
        back: 10,
        legs: 10,
        shoulders: 10,
        arms: 10,
        core: 10,
      );
      ranks[BodyPart.cardio] = 99;
      expect(ClassResolver.resolve(ranks), CharacterClass.ascendant);
    });

    test('no Wayfarer / cardio class exists', () {
      // Scope lock (Phase 38e): cardio recognition is via cardio TITLES, not
      // a class. There is no Wayfarer variant; a cardio-only "distribution"
      // (all strength at rank 1) resolves to Initiate, never a cardio class.
      expect(CharacterClass.values.any((c) => c.slug == 'wayfarer'), isFalse);
      final cardioOnly = _ranks();
      cardioOnly[BodyPart.cardio] = 80;
      expect(ClassResolver.resolve(cardioOnly), CharacterClass.initiate);
    });
  });

  // ---------------------------------------------------------------------------
  // BUG-011 (Cluster 3) — Class transition pinning
  //
  // The celebration builder calls `resolve(pre)` and `resolve(post)` to detect
  // class changes. Pinning the Initiate → Bulwark boundary here as a fixture
  // reference for the builder test makes the contract explicit at the resolver
  // level.
  // ---------------------------------------------------------------------------
  group('ClassResolver — Initiate → Bulwark boundary (BUG-011)', () {
    test(
      'pre snapshot at rank 4 across the board → Initiate, post with chest=5 '
      '→ Bulwark',
      () {
        // Pre: every track at rank 4 → Initiate floor fires.
        final pre = _ranks(
          chest: 4,
          back: 4,
          legs: 4,
          shoulders: 4,
          arms: 4,
          core: 4,
        );
        expect(ClassResolver.resolve(pre), CharacterClass.initiate);

        // Post: chest crosses to rank 5 — others unchanged. Max=5,
        // min=4, spread=(5-4)/5=0.20 ≤ 0.30 BUT minRank<5 so Ascendant
        // does NOT fire — falls through to dominant (chest → Bulwark).
        final post = _ranks(
          chest: 5,
          back: 4,
          legs: 4,
          shoulders: 4,
          arms: 4,
          core: 4,
        );
        expect(ClassResolver.resolve(post), CharacterClass.bulwark);
      },
    );
  });
}
