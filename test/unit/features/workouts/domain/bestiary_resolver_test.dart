import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/rpg/domain/body_part_hues.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/workouts/domain/beast_card.dart';
import 'package:repsaga/features/workouts/domain/bestiary_catalog.dart';
import 'package:repsaga/features/workouts/domain/bestiary_resolver.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_state.dart';

/// Reads the shipped bestiary JSON straight off disk and parses it with the
/// pure [BestiaryCatalog.parse] seam — no `rootBundle`, no async. This is the
/// real content the app ships, so the resolver tests assert against the
/// production catalog (catch a content drift, not a fixture's).
BestiaryCatalog loadRealCatalog() {
  String read(String name) => File('assets/bestiary/$name').readAsStringSync();
  return BestiaryCatalog.parse(
    baseRaw: read('bestiary.json'),
    epithetsRaw: read('epithets.json'),
    chimerasRaw: read('chimeras.json'),
    legendariesRaw: read('legendaries.json'),
    phrasesRaw: read('achievement_phrases.json'),
  );
}

PostSessionState buildState({
  required Map<BodyPart, int> bpXpDeltas,
  required Map<BodyPart, int> bpRankAfter,
  int totalXpEarned = 300,
  int sagaNumber = 1,
  PRDetectionResult? prResult,
  CelebrationQueueResult? queueResult,
}) {
  return PostSessionState(
    tier: RewardTier.baseline,
    queueResult: queueResult ?? CelebrationQueue.build(events: const []),
    prResult: prResult,
    cuts: const [],
    cutIndex: 0,
    showSummary: true,
    bodyPartLabels: const {},
    exerciseNames: const {},
    bpProgressFractionAfter: const {},
    bpXpDeltas: bpXpDeltas,
    bpRankAfter: bpRankAfter,
    bpRankBefore: const {},
    topLifts: const [],
    totalExercisesTrained: 0,
    totalXpEarned: totalXpEarned,
    priorFinishedWorkoutCount: sagaNumber - 1,
    sagaNumber: sagaNumber,
    durationMinutes: 0,
    setsCount: 0,
    tonnageTons: 0,
    dominantBodyPart: null,
    dominantXpToNextRank: null,
    dominantNextRank: null,
    ranksToNextLevel: null,
    nextLevel: null,
  );
}

PRDetectionResult prWith({required bool hasRecord}) {
  return PRDetectionResult(
    newRecords: hasRecord
        ? [
            PersonalRecord(
              id: 'pr1',
              userId: 'u1',
              exerciseId: 'bench',
              recordType: RecordType.maxWeight,
              value: 100,
              achievedAt: DateTime(2026, 1, 1),
              reps: 5,
            ),
          ]
        : const [],
    isFirstWorkout: false,
  );
}

CelebrationQueueResult rankUpQueue() {
  return CelebrationQueue.build(
    events: const [RankUpEvent(bodyPart: BodyPart.chest, newRank: 12)],
  );
}

void main() {
  final catalog = loadRealCatalog();
  final resolver = BestiaryResolver(catalog);

  // ───────────────────────────────────────────────────────────────────────────
  // Determinism
  // ───────────────────────────────────────────────────────────────────────────

  group('determinism', () {
    test('same session id yields the same beast', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
      );
      final a = resolver.resolve(state, sessionId: 'sess-abc', locale: 'en');
      final b = resolver.resolve(state, sessionId: 'sess-abc', locale: 'en');
      expect(a.slug, b.slug);
      expect(a.name, b.name);
      expect(a.tier, b.tier);
      expect(a.line, b.line);
    });

    test('different session ids can yield different variants', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
      );
      final slugs = <String>{};
      for (final id in ['s0', 's1', 's2', 's3', 's4', 's5']) {
        slugs.add(resolver.resolve(state, sessionId: id, locale: 'en').slug);
      }
      // C-league chest has 2 variants — across 6 ids both should appear.
      expect(slugs.length, greaterThan(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Rank-league boundaries (RANK-PRIMARY — tier = dominant line's rank league)
  // ───────────────────────────────────────────────────────────────────────────

  group('rank-league boundaries', () {
    BeastTier tierForRank(int rank) {
      final state = buildState(
        bpXpDeltas: const {BodyPart.legs: 300},
        bpRankAfter: {BodyPart.legs: rank},
      );
      return resolver.resolve(state, sessionId: 'fixed', locale: 'en').tier;
    }

    test('rank 4 -> E, 5 -> D', () {
      expect(tierForRank(4), BeastTier.e);
      expect(tierForRank(5), BeastTier.d);
    });

    test('rank 10 -> D, 11 -> C', () {
      expect(tierForRank(10), BeastTier.d);
      expect(tierForRank(11), BeastTier.c);
    });

    test('rank 20 -> C, 21 -> B', () {
      expect(tierForRank(20), BeastTier.c);
      expect(tierForRank(21), BeastTier.b);
    });

    test('rank 35 -> B, 36 -> A', () {
      expect(tierForRank(35), BeastTier.b);
      expect(tierForRank(36), BeastTier.a);
    });

    test('rank 55 -> A, 56 -> S', () {
      expect(tierForRank(55), BeastTier.a);
      expect(tierForRank(56), BeastTier.s);
    });

    test('tier reads the DOMINANT line rank, not session XP', () {
      // Huge XP but low dominant rank must NOT mint an S beast — the whole
      // point of RANK-PRIMARY (session-XP tiers invert over a career).
      final state = buildState(
        bpXpDeltas: const {BodyPart.legs: 4000},
        bpRankAfter: const {BodyPart.legs: 3},
        totalXpEarned: 4000,
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').tier,
        BeastTier.e,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Line selection (dominant body part)
  // ───────────────────────────────────────────────────────────────────────────

  group('line selection', () {
    test('line = body part with most session XP', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 100, BodyPart.back: 250},
        bpRankAfter: const {BodyPart.chest: 15, BodyPart.back: 15},
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').line,
        BodyPart.back,
      );
    });

    test('hue.first is the dominant line identity hue', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.arms: 300},
        bpRankAfter: const {BodyPart.arms: 15},
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.hues.first, BodyPartHues.hueFor(BodyPart.arms));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // trainedParts (B2 — the rail-widen / multi-hue-gradient source)
  // ───────────────────────────────────────────────────────────────────────────

  group('trainedParts', () {
    test('focused beast carries only the dominant line', () {
      // Two parts but only 1 above-threshold would still be focused; here a
      // single-part session: trainedParts is exactly the dominant line so the
      // rail widens only it (spec §2).
      final state = buildState(
        bpXpDeltas: const {BodyPart.legs: 300},
        bpRankAfter: const {BodyPart.legs: 15},
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.kind, BeastKind.base);
      expect(card.trainedParts, [BodyPart.legs]);
    });

    test('boss carries only the dominant line', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
        prResult: prWith(hasRecord: true),
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.kind, BeastKind.boss);
      expect(card.trainedParts, [BodyPart.chest]);
    });

    test('chimera trainedParts is dominant-first by descending XP', () {
      // back has the most XP → it's first even though chest is alphabetically
      // earlier; this is the order the rail + name gradient consume.
      final state = buildState(
        bpXpDeltas: const {
          BodyPart.chest: 100,
          BodyPart.back: 250,
          BodyPart.legs: 150,
        },
        bpRankAfter: const {
          BodyPart.chest: 15,
          BodyPart.back: 15,
          BodyPart.legs: 15,
        },
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.trainedParts.first, BodyPart.back);
      expect(card.trainedParts, [BodyPart.back, BodyPart.legs, BodyPart.chest]);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Rank sentinel unification (I1 — missing rank defaults to 0 everywhere)
  // ───────────────────────────────────────────────────────────────────────────

  group('rank sentinel', () {
    test('tie on XP with a missing rank floors to 0, not 1', () {
      // Two parts, equal XP, one with NO rank entry. The missing-rank part
      // must sort as rank 0 (lower), so the part WITH a rank wins the
      // tiebreak as dominant. Pre-I1 the missing rank defaulted to 1 in
      // `_dominantLine` (but 0 in `resolve`) — the inconsistency could flip
      // the dominant line vs the tier read.
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 200, BodyPart.back: 200},
        bpRankAfter: const {BodyPart.chest: 5}, // back has no rank entry → 0
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      // chest (rank 5) outranks back (rank 0) on the tie → chest dominant.
      expect(card.line, BodyPart.chest);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Kind precedence: legendary > boss > chimera > base
  // ───────────────────────────────────────────────────────────────────────────

  group('kind precedence', () {
    test('base session -> base kind', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').kind,
        BeastKind.base,
      );
    });

    test('PR -> boss kind, promoted one tier, named with epithet', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15}, // C league
        prResult: prWith(hasRecord: true),
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.kind, BeastKind.boss);
      expect(card.tier, BeastTier.b); // C promoted -> B
      expect(card.epithet, isNotNull);
      expect(card.name, contains(card.epithet!));
    });

    test('rank-up (no PR) -> boss kind', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 12},
        queueResult: rankUpQueue(),
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').kind,
        BeastKind.boss,
      );
    });

    test('3+ parts (no PR/rank-up) -> chimera kind', () {
      final state = buildState(
        bpXpDeltas: const {
          BodyPart.chest: 200,
          BodyPart.back: 150,
          BodyPart.legs: 100,
        },
        bpRankAfter: const {
          BodyPart.chest: 15,
          BodyPart.back: 15,
          BodyPart.legs: 15,
        },
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.kind, BeastKind.chimera);
      // Multi-hue rail: one hue per trained part.
      expect(card.hues.length, 3);
      // B2: trainedParts carries EVERY trained part, dominant-first, so the
      // chassis can widen all of them. hues stay index-aligned with parts.
      expect(card.trainedParts, [BodyPart.chest, BodyPart.back, BodyPart.legs]);
      expect(card.hues, card.trainedParts.map(BodyPartHues.hueFor).toList());
    });

    test('milestone session (sagaNumber 50) -> legendary, beats boss', () {
      // PR also set — legendary still wins by precedence.
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
        sagaNumber: 50,
        prResult: prWith(hasRecord: true),
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.kind, BeastKind.legendary);
      expect(card.slug, 'legend_gatekeeper');
    });

    test('legendary beats chimera', () {
      final state = buildState(
        bpXpDeltas: const {
          BodyPart.chest: 200,
          BodyPart.back: 150,
          BodyPart.legs: 100,
        },
        bpRankAfter: const {
          BodyPart.chest: 15,
          BodyPart.back: 15,
          BodyPart.legs: 15,
        },
        sagaNumber: 100,
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').kind,
        BeastKind.legendary,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Specimen band boundaries (flavor — session XP vs league reference median)
  // ───────────────────────────────────────────────────────────────────────────

  group('specimen bands', () {
    // C-league reference median = 420. notable >= 1.4x (588), fierce >= 2.2x (924).
    BeastSpecimen specimenForXp(int xp) {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 1},
        bpRankAfter: const {BodyPart.chest: 15}, // C league, median 420
        totalXpEarned: xp,
      );
      return resolver.resolve(state, sessionId: 'x', locale: 'en').specimen;
    }

    test('below 1.4x median -> base', () {
      expect(specimenForXp(587), BeastSpecimen.base); // 587/420 = 1.397
    });

    test('at/above 1.4x median -> notable', () {
      expect(specimenForXp(588), BeastSpecimen.notable); // 588/420 = 1.4
    });

    test('below 2.2x median -> notable', () {
      expect(specimenForXp(923), BeastSpecimen.notable); // 923/420 = 2.198
    });

    test('at/above 2.2x median -> fierce', () {
      expect(specimenForXp(924), BeastSpecimen.fierce); // 924/420 = 2.2
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // referenceMedianXp pin (the resolver dartdoc claims a pin exists — make it
  // real so a future content / calibration edit can't silently drift the
  // specimen bands). QA coverage hole 1c.
  // ───────────────────────────────────────────────────────────────────────────

  group('referenceMedianXp pin', () {
    test(
      'every BeastTier has a reference median (specimen lookup is total)',
      () {
        // _specimen does `referenceMedianXp[tier]!` — a missing tier throws a
        // null-check at resolve time. Every league must be present.
        for (final tier in BeastTier.values) {
          expect(
            BestiaryResolver.referenceMedianXp[tier],
            isNotNull,
            reason: 'no reference median for tier ${tier.label}',
          );
        }
      },
    );

    test('per-league median values match the calibration-locked map', () {
      // These are the FLAVOR thresholds the specimen band reads (sessionXP /
      // median → base/notable/fierce). They came from the persona simulation
      // (tasks/bestiary-tier-calibration.py per-rank-league p50, de-noised).
      // A content / calibration edit that moves any of them shifts which
      // sessions read as "fierce" vs "base" on the share card — a visible,
      // un-reviewed change. This pin forces such an edit to update the test
      // in the same diff.
      expect(BestiaryResolver.referenceMedianXp, {
        BeastTier.e: 220,
        BeastTier.d: 400,
        BeastTier.c: 420,
        BeastTier.b: 430,
        BeastTier.a: 470,
        BeastTier.s: 500,
      });
    });

    test('medians are monotonically non-decreasing E→S (no inversion)', () {
      // The bands climb (or hold) with the league — a higher league should
      // never demand LESS session XP to read as fierce. Guards against a
      // typo'd edit that inverts two adjacent leagues.
      var prev = 0.0;
      for (final tier in BeastTier.values) {
        final median = BestiaryResolver.referenceMedianXp[tier]!;
        expect(
          median,
          greaterThanOrEqualTo(prev),
          reason: 'median for ${tier.label} ($median) < previous ($prev)',
        );
        prev = median;
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Variant no-repeat guard (1-deep)
  // ───────────────────────────────────────────────────────────────────────────

  group('variant no-repeat guard', () {
    test('repeats are skipped to the next variant', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
      );
      // Resolve without a guard to learn which variant this hash lands on.
      final first = resolver.resolve(
        state,
        sessionId: 'repeat-id',
        locale: 'en',
      );
      // Same id again, but tell the resolver that's the last beast — it must
      // advance to a different variant of the same (line, tier).
      final guarded = resolver.resolve(
        state,
        sessionId: 'repeat-id',
        locale: 'en',
        lastBeastSlug: first.slug,
      );
      expect(guarded.slug, isNot(first.slug));
      expect(guarded.line, first.line);
      expect(guarded.tier, first.tier);
    });

    test('non-matching lastBeastSlug leaves the deterministic pick intact', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
      );
      final plain = resolver.resolve(state, sessionId: 'id', locale: 'en');
      final withGuard = resolver.resolve(
        state,
        sessionId: 'id',
        locale: 'en',
        lastBeastSlug: 'some_unrelated_slug',
      );
      expect(withGuard.slug, plain.slug);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Achievement phrase + locale resolution
  // ───────────────────────────────────────────────────────────────────────────

  group('achievement phrase + locale', () {
    test('PR phrase wins over the line fallback', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
        prResult: prWith(hasRecord: true),
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').achievementPhrase,
        'A new legend is forged.',
      );
    });

    test('S-rank phrase wins over the line fallback (no PR)', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 60}, // S league
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').achievementPhrase,
        'Few have felled its equal.',
      );
    });

    test('dominant-line fallback phrase (arms)', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.arms: 300},
        bpRankAfter: const {BodyPart.arms: 15},
      );
      expect(
        resolver.resolve(state, sessionId: 'x', locale: 'en').achievementPhrase,
        'Your sword arm sharpens.',
      );
    });

    test('pt locale resolves Portuguese content', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
      );
      final card = resolver.resolve(state, sessionId: 'x', locale: 'pt');
      expect(card.achievementPhrase, 'A muralha avança.');
      // Iron Golem / Golem de Ferro — pt name must differ from en.
      final en = resolver.resolve(state, sessionId: 'x', locale: 'en');
      expect(card.name, isNot(en.name));
    });

    test('boss name order differs by locale (en prefix, pt suffix)', () {
      final state = buildState(
        bpXpDeltas: const {BodyPart.chest: 300},
        bpRankAfter: const {BodyPart.chest: 15},
        prResult: prWith(hasRecord: true),
      );
      final en = resolver.resolve(state, sessionId: 'boss', locale: 'en');
      final pt = resolver.resolve(state, sessionId: 'boss', locale: 'pt');
      // en: "[Epithet], the [Creature]" -> epithet comes first.
      expect(en.name.indexOf(en.epithet!), 0);
      // pt: "[Creature], [Epítome]" -> epithet comes last.
      expect(pt.name.endsWith(pt.epithet!), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Generative chimera (non-curated top-2 pair) — QA coverage hole.
  //
  // ~14 of 21 BP pairs route through the generative fusion-lexicon path: a
  // 3-part session whose top-2 XP pair has NO curated override (every existing
  // chimera test used chest+back+legs, where back+chest IS curated, so the
  // generative branch never rendered). chest+legs is NOT in chimeras.json's
  // `curated` list — top-2 = (chest, legs) routes generative. We assert the
  // user-visible NAME shape (word order + spacing) and slug for both locales.
  // ───────────────────────────────────────────────────────────────────────────

  group('generative chimera (non-curated pair)', () {
    // chest (300) dominant, legs (200) secondary, arms (100) third.
    // top-2 = chest+legs (sorted) — absent from `curated` → generative path.
    // Lexicon: chest noun = "Golem"/"Golem"; legs adjectives =
    //   en ["Earthen","Trampling"], pt ["Telúrico","Esmagador"].
    // en shape: "The <legs-adj.en> Golem"  ·  pt shape: "O Golem <legs-adj.pt>"
    // slug: "chimera_gen_chest_legs".
    PostSessionState genState() => buildState(
      bpXpDeltas: const {
        BodyPart.chest: 300,
        BodyPart.legs: 200,
        BodyPart.arms: 100,
      },
      bpRankAfter: const {
        BodyPart.chest: 15,
        BodyPart.legs: 15,
        BodyPart.arms: 15,
      },
    );

    // The legs adjectives are the ONLY hash-variable token in the name; the
    // dominant noun + connective words are fixed. Asserting membership pins
    // the lexicon source while the prefix/suffix pins word order + spacing.
    const legsAdjsEn = ['Earthen', 'Trampling'];
    const legsAdjsPt = ['Telúrico', 'Esmagador'];

    test('routes to the generative path with the gen slug', () {
      final card = resolver.resolve(
        genState(),
        sessionId: 'gen-1',
        locale: 'en',
      );
      expect(card.kind, BeastKind.chimera);
      // Slug encodes the dominant+secondary dbValues, dominant first.
      expect(card.slug, 'chimera_gen_chest_legs');
      // NOT a curated/byCount named chimera (those have different slug shapes).
      expect(card.slug, startsWith('chimera_gen_'));
    });

    test('en name has the "The <2nd-adj> <dominant-noun>" shape', () {
      final card = resolver.resolve(
        genState(),
        sessionId: 'gen-1',
        locale: 'en',
      );
      // Word order: leading article, then the secondary line's adjective, then
      // the dominant line's noun. Exactly one space between each token (no
      // missing space, no doubled space).
      expect(card.name, startsWith('The '));
      expect(card.name, endsWith(' Golem'));
      final adj = card.name.substring(
        'The '.length,
        card.name.length - ' Golem'.length,
      );
      expect(legsAdjsEn, contains(adj));
      // Reconstruct the full string to prove spacing is exactly single-spaced.
      expect(card.name, 'The $adj Golem');
    });

    test('pt name has the "O <dominant-noun> <2nd-adj>" shape', () {
      final card = resolver.resolve(
        genState(),
        sessionId: 'gen-1',
        locale: 'pt',
      );
      // pt inverts: article, dominant noun, then the secondary adjective.
      expect(card.name, startsWith('O Golem '));
      final adj = card.name.substring('O Golem '.length);
      expect(legsAdjsPt, contains(adj));
      expect(card.name, 'O Golem $adj');
    });

    test('multi-hue rail carries every trained part, dominant-first', () {
      final card = resolver.resolve(
        genState(),
        sessionId: 'gen-1',
        locale: 'en',
      );
      expect(card.trainedParts, [BodyPart.chest, BodyPart.legs, BodyPart.arms]);
      expect(card.hues, card.trainedParts.map(BodyPartHues.hueFor).toList());
    });

    test('same session id yields the same generative name (deterministic)', () {
      final a = resolver.resolve(
        genState(),
        sessionId: 'gen-det',
        locale: 'en',
      );
      final b = resolver.resolve(
        genState(),
        sessionId: 'gen-det',
        locale: 'en',
      );
      expect(a.name, b.name);
      expect(a.slug, b.slug);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Curated 4-part and 5-part chimeras — QA coverage hole.
  //
  // The partCount→branch routing (5+ → full-body, 4 → fixed-4, 3 →
  // curated-or-generative) wasn't directly pinned: every prior chimera test
  // used exactly 3 parts. A 4-part session must resolve to a byCount[4] slug;
  // a 5-part session to a byCount[5] slug — NOT the 3-part fixed names.
  // ───────────────────────────────────────────────────────────────────────────

  group('chimera part-count routing', () {
    // chimeras.json byCount slugs (the expected pool per count):
    const fourPartSlugs = ['chimera_four_maw', 'chimera_tetra_beast'];
    const fivePartSlugs = [
      'chimera_primordial',
      'chimera_seven_fanged',
      'chimera_all_beast',
    ];
    const threePartSlugs = ['chimera_three_fanged', 'chimera_trident_beast'];

    test('4 trained parts -> a curated four-part chimera', () {
      final state = buildState(
        bpXpDeltas: const {
          BodyPart.chest: 200,
          BodyPart.back: 150,
          BodyPart.legs: 120,
          BodyPart.shoulders: 100,
        },
        bpRankAfter: const {
          BodyPart.chest: 15,
          BodyPart.back: 15,
          BodyPart.legs: 15,
          BodyPart.shoulders: 15,
        },
      );
      final card = resolver.resolve(state, sessionId: 'four', locale: 'en');
      expect(card.kind, BeastKind.chimera);
      expect(card.trainedParts.length, 4);
      // Lands in the four-part pool — not the three-part fixed names.
      expect(fourPartSlugs, contains(card.slug));
      expect(threePartSlugs, isNot(contains(card.slug)));
    });

    test('5 trained parts -> a full-body apex chimera', () {
      final state = buildState(
        bpXpDeltas: const {
          BodyPart.chest: 200,
          BodyPart.back: 150,
          BodyPart.legs: 120,
          BodyPart.shoulders: 100,
          BodyPart.arms: 80,
        },
        bpRankAfter: const {
          BodyPart.chest: 15,
          BodyPart.back: 15,
          BodyPart.legs: 15,
          BodyPart.shoulders: 15,
          BodyPart.arms: 15,
        },
      );
      final card = resolver.resolve(state, sessionId: 'five', locale: 'en');
      expect(card.kind, BeastKind.chimera);
      expect(card.trainedParts.length, 5);
      expect(fivePartSlugs, contains(card.slug));
      expect(fourPartSlugs, isNot(contains(card.slug)));
    });

    test('6 trained parts also routes to the 5+ full-body pool', () {
      // The 5+ branch is "5 OR MORE" — a 6-part session must not fall through
      // to a missing byCount[6] (which would NPE the chimerasByCount lookup).
      final state = buildState(
        bpXpDeltas: const {
          BodyPart.chest: 200,
          BodyPart.back: 150,
          BodyPart.legs: 120,
          BodyPart.shoulders: 100,
          BodyPart.arms: 80,
          BodyPart.core: 60,
        },
        bpRankAfter: const {
          BodyPart.chest: 15,
          BodyPart.back: 15,
          BodyPart.legs: 15,
          BodyPart.shoulders: 15,
          BodyPart.arms: 15,
          BodyPart.core: 15,
        },
      );
      final card = resolver.resolve(state, sessionId: 'six', locale: 'en');
      expect(card.kind, BeastKind.chimera);
      expect(card.trainedParts.length, 6);
      expect(fivePartSlugs, contains(card.slug));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Empty bpXpDeltas (no dominant line) fallback — QA coverage hole.
  //
  // Pathological state: no body part earned XP. `_dominantLine` returns null →
  // the resolver falls back to BodyPart.chest, rank floors to 0 → tier E. This
  // must NOT throw (a null line would NPE the hue / name lookups) and must
  // produce a valid base card.
  // ───────────────────────────────────────────────────────────────────────────

  group('empty bpXpDeltas fallback', () {
    test('null dominant -> valid chest/E/base card without throwing', () {
      final state = buildState(bpXpDeltas: const {}, bpRankAfter: const {});
      late final BeastCard card;
      expect(
        () => card = resolver.resolve(state, sessionId: 'empty', locale: 'en'),
        returnsNormally,
      );
      expect(card.line, BodyPart.chest);
      expect(card.tier, BeastTier.e);
      expect(card.kind, BeastKind.base);
      // A real creature was picked (non-empty name + slug) and the rail has the
      // single fallback line's hue — nothing rendered blank.
      expect(card.name, isNotEmpty);
      expect(card.slug, isNotEmpty);
      expect(card.trainedParts, [BodyPart.chest]);
      expect(card.hues, [BodyPartHues.hueFor(BodyPart.chest)]);
    });

    test('empty deltas pt locale also resolves a valid card', () {
      final state = buildState(bpXpDeltas: const {}, bpRankAfter: const {});
      final card = resolver.resolve(state, sessionId: 'empty', locale: 'pt');
      expect(card.line, BodyPart.chest);
      expect(card.tier, BeastTier.e);
      expect(card.name, isNotEmpty);
    });
  });
}
