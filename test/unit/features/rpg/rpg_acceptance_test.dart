/// End-to-end seam test for the §18 RPG v1 acceptance criteria.
///
/// **Why a single seam test instead of a forest of unit tests:** the unit
/// tests under `test/unit/features/rpg/` already pin every individual aggregator
/// (rank curve, class resolver, cross-build evaluator, title detector,
/// celebration event builder). What none of them prove is that the *composed*
/// pipeline — pre/post snapshot → builder → detector → catalog → events +
/// resolver — produces the §18 acceptance bullets when wired against the
/// **real shipped title catalog** and the canonical [activeBodyParts] order.
///
/// This test synthesises a deterministic fixture user with known per-body-part
/// rank distributions, runs the aggregation pipeline (including
/// `TitlesRepository.loadCatalog` against the real assets), and asserts every
/// §18 bullet that the Dart-side aggregation owns:
///
///   * **#3** Character sheet renders for zero-history users — empty snapshot
///            yields rank 1, 0 XP for every active body part, level 1,
///            class Initiate.
///   * **#5** Mid-workout rank-up fires on real XP math — a workout that crosses
///            a rank threshold produces a [RankUpEvent].
///   * **#7** Title unlocks fire on Rank crossings (all three kinds):
///            body-part rank threshold → [BodyPartTitle] unlock,
///            character-level threshold → [CharacterLevelTitle] unlock,
///            cross-build distribution → [CrossBuildTitle] unlock (Iron-Bound
///            and Saga-Forged paths).
///   * **#8** Class label updates immediately on rank changes —
///            [ClassResolver.resolve] returns Initiate / dominant / Ascendant
///            from the distributions.
///   * **#10** Permanent peak invariant (Dart side) — `BodyPartProgress.rank`
///             only increases across pre→post; the builder never fabricates a
///             rank decrease.
///
/// **Bullets covered elsewhere (intentionally not duplicated):**
///   * #1 schema migrated, #2 <50ms p95 XP, #6 vitality EWMA, #9 strength_mult,
///     #11 CI green, #12 hosted migration — these are server-side / pipeline
///     concerns asserted by `rpg_record_set_xp_test.dart`,
///     `rpg_save_workout_perf_test.dart`, `rpg_vitality_nightly_test.dart`,
///     and the CI workflow itself.
///   * #4 stats deep-dive UI rendering — covered by widget tests under
///     `test/widget/features/rpg/ui/`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:repsaga/features/rpg/domain/celebration_event_builder.dart';
import 'package:repsaga/features/rpg/domain/class_resolver.dart';
import 'package:repsaga/features/rpg/domain/cross_build_title_evaluator.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

const _userId = 'fixture-user';
final _now = DateTime.utc(2026, 4, 29);

/// Fixture row for a body-part progress entry. Vitality fields are zeroed —
/// the seam this test owns is rank/level/title/class aggregation, not the
/// vitality EWMA (which has its own integration test).
BodyPartProgress _row(BodyPart bp, {required int rank, required double xp}) {
  return BodyPartProgress(
    userId: _userId,
    bodyPart: bp,
    totalXp: xp,
    rank: rank,
    vitalityEwma: 0,
    vitalityPeak: 0,
    vitalityRefPeak: 0,
    lastEventAt: null,
    updatedAt: _now,
  );
}

RpgProgressSnapshot _snapshot({
  required Map<BodyPart, BodyPartProgress> rows,
  required int level,
}) {
  // Match the live shape from `RpgProgressNotifier._load`: byBodyPart is
  // exactly what the SELECT returned (no synthetic fills); characterState
  // is the view roll-up. We synthesise the view roll-up from the rows so
  // the fixture stays internally consistent.
  final rankValues = activeBodyParts
      .map((bp) => rows[bp]?.rank ?? 1)
      .toList(growable: false);
  return RpgProgressSnapshot(
    byBodyPart: rows,
    characterState: CharacterState(
      userId: _userId,
      characterLevel: level,
      maxRank: rankValues.reduce((a, b) => a > b ? a : b),
      minRank: rankValues.reduce((a, b) => a < b ? a : b),
      lifetimeXp: rows.values.fold<double>(0, (s, r) => s + r.totalXp),
    ),
  );
}

/// Minimal stand-in for [supabase.SupabaseClient] used only to satisfy
/// [TitlesRepository]'s constructor — the catalog-load path we exercise
/// reads from `rootBundle`, never from the client. Any client method call
/// would surface as `noSuchMethod` and fail loudly, which is exactly what
/// we want if the test ever drifts toward DB access.
class _UnusedSupabaseClient implements supabase.SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError(
      'rpg_acceptance_test must not touch SupabaseClient — this test is a '
      'pure-Dart aggregation seam. Got: ${invocation.memberName}',
    );
  }
}

void main() {
  // Required so `rootBundle.loadString` resolves the shipped JSON catalogs.
  // The `flutter_test_config.dart` in this directory deliberately skips
  // binding init for the Postgres-hitting tests; we re-enable it locally
  // here because this test is asset-driven, not network-driven.
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<rpg.Title> catalog;

  setUpAll(() async {
    // Reset the process-wide cache so any prior test (titles_repository_test)
    // that primed it from a different bundle doesn't leak in. The real
    // shipped catalog is what we want to assert against.
    TitlesRepository.debugResetCatalogCache();
    final repo = TitlesRepository(_UnusedSupabaseClient());
    catalog = await repo.loadCatalog();
  });

  group('§18 acceptance — Dart aggregation seam', () {
    // -------------------------------------------------------------------------
    // Bullet #3 — character sheet renders for zero-history users
    // -------------------------------------------------------------------------

    test('zero-history user yields rank 1 / 0 XP / level 1 / class Initiate '
        '(bullet #3)', () {
      // The empty snapshot is what a brand-new account sees on first character
      // sheet render. Every rank must default to 1 (not 0 — rank 1 is the
      // floor), every XP to 0, character level to 1, and the class to
      // Initiate (max rank < initiate ceiling).
      const empty = RpgProgressSnapshot.empty;

      // progressFor must return a placeholder row for every active body part.
      for (final bp in activeBodyParts) {
        final row = empty.progressFor(bp);
        expect(row.rank, 1, reason: 'rank floor for $bp');
        expect(row.totalXp, 0, reason: 'XP floor for $bp');
      }
      expect(empty.characterState.characterLevel, 1);

      // Class resolution from an empty rank map → Initiate.
      final ranks = <BodyPart, int>{
        for (final bp in activeBodyParts) bp: empty.progressFor(bp).rank,
      };
      expect(ClassResolver.resolve(ranks), CharacterClass.initiate);
    });

    // -------------------------------------------------------------------------
    // Bullets #5 + #7 — rank-up + body-part title unlock at the rank-5 boundary
    // -------------------------------------------------------------------------

    test('crossing chest rank 4 → 5 fires RankUpEvent + body-part title unlock '
        '(bullets #5, #7)', () {
      // The first body-part title threshold sits at rank 5 (chest_r5_initiate
      // _of_the_forge). A workout that pushes chest from rank 4 to rank 5 must
      // produce both a RankUpEvent (overlay fires) and a TitleUnlockEvent for
      // the rank-5 chest slug.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, rank: 4, xp: 200)},
        level: 1,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, rank: 5, xp: 280)},
        level: 1,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      // Rank-up fires for chest.
      final rankUps = events.whereType<RankUpEvent>().toList();
      expect(rankUps, hasLength(1));
      expect(rankUps.single.bodyPart, BodyPart.chest);
      expect(rankUps.single.newRank, 5);

      // Body-part title unlock fires with the canonical slug.
      final titleSlugs = events
          .whereType<TitleUnlockEvent>()
          .map((e) => e.slug)
          .toSet();
      expect(titleSlugs, contains('chest_r5_initiate_of_the_forge'));
    });

    // -------------------------------------------------------------------------
    // Bullet #7 — body-part title at the high end of the ladder (rank 60)
    // -------------------------------------------------------------------------

    test(
      'crossing legs rank 59 → 60 fires the rank-60 legs title (bullet #7)',
      () {
        // The rank-60 entry is one of the iron_bound prerequisites; the
        // body-part ladder must fire its own title independently of the
        // cross-build path. Catalog slug: `legs_r60_*` (whatever the v1 entry).
        final pre = _snapshot(
          rows: {BodyPart.legs: _row(BodyPart.legs, rank: 59, xp: 100000)},
          level: 28,
        );
        final post = _snapshot(
          rows: {BodyPart.legs: _row(BodyPart.legs, rank: 60, xp: 170000)},
          level: 28,
        );

        final events = CelebrationEventBuilder.build(
          pre: pre,
          post: post,
          catalog: catalog,
          alreadyEarnedSlugs: const {},
          suppressFirstAwakening: false,
        );

        // Pull the legs rank-60 slug from the real catalog so this test
        // doesn't hard-code editorial copy — only the structural identity
        // (`body_part == legs && rankThreshold == 60`) is contract.
        final legsR60Slug = catalog
            .whereType<rpg.BodyPartTitle>()
            .firstWhere(
              (t) => t.bodyPart == BodyPart.legs && t.rankThreshold == 60,
            )
            .slug;
        final titleSlugs = events
            .whereType<TitleUnlockEvent>()
            .map((e) => e.slug)
            .toSet();
        expect(titleSlugs, contains(legsR60Slug));
      },
    );

    // -------------------------------------------------------------------------
    // Bullet #7 — character-level title (Phase 18e)
    // -------------------------------------------------------------------------

    test('crossing character level 9 → 10 fires the wanderer title '
        '(bullet #7)', () {
      // Character-level title threshold lowest entry is `wanderer @ level 10`.
      // A workout whose post snapshot has characterLevel == 10 must fire it
      // via the half-open `(oldLevel, newLevel]` interval semantics.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, rank: 33, xp: 25000)},
        level: 9,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, rank: 33, xp: 25500)},
        level: 10,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      // Level-up event itself.
      expect(events.whereType<LevelUpEvent>(), hasLength(1));
      expect(events.whereType<LevelUpEvent>().single.newLevel, 10);

      // Character-level title.
      final titleSlugs = events
          .whereType<TitleUnlockEvent>()
          .map((e) => e.slug)
          .toSet();
      expect(titleSlugs, contains('wanderer'));
    });

    // -------------------------------------------------------------------------
    // Bullet #7 — cross-build title (Iron-Bound: Chest+Back+Legs all >= 60)
    // -------------------------------------------------------------------------

    test('post distribution Chest=60, Back=60, Legs=60 fires iron_bound '
        '(bullet #7)', () {
      // Iron-Bound predicate is per-track AND, NOT a sum (validated against
      // Task 1's doc fix). Pre snapshot has legs at rank 59 (predicate fails),
      // post snapshot pushes legs to rank 60 (predicate fires).
      final pre = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, rank: 60, xp: 170000),
          BodyPart.back: _row(BodyPart.back, rank: 60, xp: 170000),
          BodyPart.legs: _row(BodyPart.legs, rank: 59, xp: 100000),
        },
        level: 30,
      );
      final post = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, rank: 60, xp: 170000),
          BodyPart.back: _row(BodyPart.back, rank: 60, xp: 170000),
          BodyPart.legs: _row(BodyPart.legs, rank: 60, xp: 170000),
        },
        level: 30,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      final titleSlugs = events
          .whereType<TitleUnlockEvent>()
          .map((e) => e.slug)
          .toSet();
      expect(titleSlugs, contains('iron_bound'));

      // Saga-Forged should NOT fire — only chest/back/legs reach 60, the
      // other three tracks are still at rank 1. Pins the per-track AND vs
      // big-three contract distinction.
      expect(titleSlugs, isNot(contains('saga_forged')));
    });

    // -------------------------------------------------------------------------
    // Bullet #7 — cross-build title (Saga-Forged: every active rank >= 60)
    // -------------------------------------------------------------------------

    test(
      'post distribution every rank >= 60 fires saga_forged (bullet #7)',
      () {
        // The end-game cross-build title. Pre has core at 59; the workout that
        // pushes core to 60 brings every active rank to the threshold and
        // saga_forged fires for the first time.
        final fullSet = <BodyPart, BodyPartProgress>{
          for (final bp in activeBodyParts) bp: _row(bp, rank: 60, xp: 170000),
        };
        final preRows = Map<BodyPart, BodyPartProgress>.from(fullSet);
        preRows[BodyPart.core] = _row(BodyPart.core, rank: 59, xp: 100000);

        final pre = _snapshot(rows: preRows, level: 88);
        final post = _snapshot(rows: fullSet, level: 89);

        final events = CelebrationEventBuilder.build(
          pre: pre,
          post: post,
          catalog: catalog,
          alreadyEarnedSlugs: const {},
          suppressFirstAwakening: false,
        );

        final titleSlugs = events
            .whereType<TitleUnlockEvent>()
            .map((e) => e.slug)
            .toSet();
        // Every active track (incl. cardio) is at rank 60. saga_forged (every
        // strength track >= 60) fires. Phase 38f: iron_bound does NOT fire
        // here — its low-cardio condition (cardio <= 10) is violated by the
        // cardio-60 distribution. The two cardio cross-build apex titles fire
        // instead: the_forged_wind (all six strength >= 60 AND cardio >= 60)
        // and storm_tempered (cardio >= 60 AND all six strength >= 30).
        expect(titleSlugs, contains('saga_forged'));
        expect(titleSlugs, isNot(contains('iron_bound')));
        expect(titleSlugs, contains('the_forged_wind'));
        expect(titleSlugs, contains('storm_tempered'));
      },
    );

    // -------------------------------------------------------------------------
    // Bullet #7 — already-earned guard suppresses re-fires
    // -------------------------------------------------------------------------

    test('alreadyEarnedSlugs suppresses every kind of title re-fire '
        '(bullet #7 idempotency)', () {
      // The §18 contract is "fire on Rank threshold crossing" — not "fire on
      // every workout where the predicate is true". The detector's
      // already-earned guard must hold for all three title kinds.
      final fullSet = <BodyPart, BodyPartProgress>{
        for (final bp in activeBodyParts) bp: _row(bp, rank: 60, xp: 170000),
      };

      // Pre and post are identical (same distribution, no rank deltas) —
      // body-part / character-level paths produce nothing structural; the
      // cross-build path runs every finish but is filtered by the guard.
      final pre = _snapshot(rows: fullSet, level: 89);
      final post = _snapshot(rows: fullSet, level: 89);

      // Every active track (incl. cardio) at rank 60 fires FOUR cross-build
      // predicates (Phase 38f): saga_forged (every active rank >= 60),
      // even_handed (every active rank >= 30 with zero spread), the_forged_wind
      // (all six strength >= 60 AND cardio >= 60), and storm_tempered (cardio
      // >= 60 AND all six strength >= 30). iron_bound does NOT fire (cardio 60
      // violates its <= 10 condition). The guard must suppress all four
      // candidates the distribution produces.
      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: catalog,
        alreadyEarnedSlugs: const {
          'saga_forged',
          'even_handed',
          'the_forged_wind',
          'storm_tempered',
        },
        suppressFirstAwakening: false,
      );

      // No rank deltas → no body-part title events, no character-level title
      // events. Cross-build candidates are filtered by alreadyEarnedSlugs.
      expect(events.whereType<TitleUnlockEvent>(), isEmpty);
    });

    // -------------------------------------------------------------------------
    // Bullet #8 — class label updates immediately on rank changes
    // -------------------------------------------------------------------------

    test('Initiate floor below rank 5 (bullet #8)', () {
      // Every track at or below rank 4 → Initiate, regardless of which body
      // part is highest. Mirrors §9.1: "All ranks ≤ 4".
      final ranks = <BodyPart, int>{
        BodyPart.chest: 4,
        BodyPart.back: 3,
        BodyPart.legs: 4,
        BodyPart.shoulders: 1,
        BodyPart.arms: 2,
        BodyPart.core: 1,
      };
      expect(ClassResolver.resolve(ranks), CharacterClass.initiate);
    });

    test('dominant lookup routes to Bulwark on chest-dominant build '
        '(bullet #8)', () {
      // Chest=20, others around 5-8 → max=20 (chest), min=5 (>= ascendantMinRank).
      // Spread = (20-5)/20 = 0.75 → exceeds 0.30 → falls through to dominant
      // lookup → chest → Bulwark.
      final ranks = <BodyPart, int>{
        BodyPart.chest: 20,
        BodyPart.back: 8,
        BodyPart.legs: 7,
        BodyPart.shoulders: 6,
        BodyPart.arms: 5,
        BodyPart.core: 5,
      };
      expect(ClassResolver.resolve(ranks), CharacterClass.bulwark);
    });

    test(
      'Ascendant when every rank >= 5 and spread within 30% (bullet #8)',
      () {
        // max=14, min=10 → (14-10)/14 = 0.286 ≤ 0.30 AND min >= 5 → Ascendant.
        // Takes precedence over the dominant lookup per §9.2 ordering.
        final ranks = <BodyPart, int>{
          BodyPart.chest: 14,
          BodyPart.back: 13,
          BodyPart.legs: 12,
          BodyPart.shoulders: 11,
          BodyPart.arms: 10,
          BodyPart.core: 10,
        };
        expect(ClassResolver.resolve(ranks), CharacterClass.ascendant);
      },
    );

    test('class flips Bulwark → Ascendant when distribution rebalances '
        '(bullet #8 — "updates immediately on rank changes")', () {
      // Pre: chest=20, others 5 → Bulwark (dominant).
      // Post: every track 14-15 → Ascendant.
      // The bullet specifies "updates immediately on Rank changes"; this
      // proves the resolver returns a strictly different class for the two
      // distributions, not a stale value.
      final pre = <BodyPart, int>{
        BodyPart.chest: 20,
        BodyPart.back: 5,
        BodyPart.legs: 5,
        BodyPart.shoulders: 5,
        BodyPart.arms: 5,
        BodyPart.core: 5,
      };
      final post = <BodyPart, int>{
        BodyPart.chest: 15,
        BodyPart.back: 14,
        BodyPart.legs: 15,
        BodyPart.shoulders: 14,
        BodyPart.arms: 14,
        BodyPart.core: 14,
      };
      expect(ClassResolver.resolve(pre), CharacterClass.bulwark);
      expect(ClassResolver.resolve(post), CharacterClass.ascendant);
    });

    // -------------------------------------------------------------------------
    // Bullet #10 — permanent peak invariant (Dart-side aggregator slice)
    // -------------------------------------------------------------------------

    test('builder emits no RankUpEvent on rank decrease — permanent peak '
        'invariant holds at the aggregator (bullet #10)', () {
      // Server-side enforces the invariant via `record_set_xp` (no path
      // decreases rank). The builder's contract here is the aggregator
      // contract: a (hypothetically corrupt) snapshot pair where post.rank
      // < pre.rank must NOT produce a RankUpEvent — the builder's
      // `newRank > oldRank` guard is the last line of defense before the
      // overlay queue. If this test ever fails, both the server invariant
      // is broken AND the aggregator is silently propagating the bug.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, rank: 10, xp: 1000)},
        level: 5,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, rank: 9, xp: 1000)},
        level: 5,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<RankUpEvent>(), isEmpty);
    });

    // -------------------------------------------------------------------------
    // Composite — full §18 pipeline on a single fixture user
    // -------------------------------------------------------------------------

    test('composite: a workout that simultaneously crosses rank, level, and '
        'cross-build thresholds emits the full event set in one build call '
        '(bullets #5, #7, #8)', () {
      // Synthetic "perfect storm" finish: pushes legs from 59 → 60 (which
      // satisfies iron_bound for the first time given chest=60, back=60),
      // crosses character level 24 → 25 (path_trodden title), and rank-ups
      // legs. A single `build` call must surface all of:
      //   - RankUpEvent(legs, 60)
      //   - LevelUpEvent(25)
      //   - TitleUnlockEvent(legs_r60_*)              (body-part)
      //   - TitleUnlockEvent('path_trodden')          (character-level)
      //   - TitleUnlockEvent('iron_bound')            (cross-build)
      //
      // Class resolution on the post distribution lands on Ascendant
      // (every track >= 5, spread within 30% — chest=60, back=60, legs=60,
      // shoulders=45, arms=45, core=45 → spread = 15/60 = 0.25 ≤ 0.30).
      final preRows = <BodyPart, BodyPartProgress>{
        BodyPart.chest: _row(BodyPart.chest, rank: 60, xp: 170000),
        BodyPart.back: _row(BodyPart.back, rank: 60, xp: 170000),
        BodyPart.legs: _row(BodyPart.legs, rank: 59, xp: 100000),
        BodyPart.shoulders: _row(BodyPart.shoulders, rank: 45, xp: 50000),
        BodyPart.arms: _row(BodyPart.arms, rank: 45, xp: 50000),
        BodyPart.core: _row(BodyPart.core, rank: 45, xp: 50000),
      };
      final postRows = <BodyPart, BodyPartProgress>{
        ...preRows,
        BodyPart.legs: _row(BodyPart.legs, rank: 60, xp: 170000),
      };

      final pre = _snapshot(rows: preRows, level: 24);
      final post = _snapshot(rows: postRows, level: 25);

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      // Rank-up — legs only.
      expect(events.whereType<RankUpEvent>().map((e) => e.bodyPart).toSet(), {
        BodyPart.legs,
      });

      // Level-up — single event at the post level.
      expect(events.whereType<LevelUpEvent>(), hasLength(1));
      expect(events.whereType<LevelUpEvent>().single.newLevel, 25);

      // Title unlocks — three slugs across all three kinds.
      final titleSlugs = events
          .whereType<TitleUnlockEvent>()
          .map((e) => e.slug)
          .toSet();
      final legsR60Slug = catalog
          .whereType<rpg.BodyPartTitle>()
          .firstWhere(
            (t) => t.bodyPart == BodyPart.legs && t.rankThreshold == 60,
          )
          .slug;
      expect(titleSlugs, contains(legsR60Slug));
      expect(titleSlugs, contains('path_trodden'));
      expect(titleSlugs, contains('iron_bound'));

      // Class on the post distribution — Ascendant. Class resolution reads
      // the six strength tracks (Phase 38e: cardio is excluded from class /
      // Ascendant), so build the rank map over strengthBodyParts.
      final postRanks = <BodyPart, int>{
        for (final bp in strengthBodyParts) bp: postRows[bp]!.rank,
      };
      expect(ClassResolver.resolve(postRanks), CharacterClass.ascendant);
    });

    // -------------------------------------------------------------------------
    // Cross-build evaluator sanity — all five predicate slugs are catalogued
    // -------------------------------------------------------------------------

    test('every cross-build trigger predicate has a matching catalog slug '
        '(bullet #7 — catalog/predicate parity)', () {
      // The detector matches the evaluator's slug output against the catalog.
      // If a predicate fires but no catalog entry matches, the title silently
      // never unlocks. This test pins the parity: every CrossBuildTriggerId
      // has exactly one CrossBuildTitle catalog entry whose slug equals the
      // trigger's dbValue (the JSON convention used by titles_cross_build.json).
      final catalogSlugs = catalog
          .whereType<rpg.CrossBuildTitle>()
          .map((t) => t.slug)
          .toSet();
      final triggerSlugs = rpg.CrossBuildTriggerId.values
          .map((t) => t.dbValue)
          .toSet();
      expect(catalogSlugs, equals(triggerSlugs));
    });

    test('CrossBuildTitleEvaluator.evaluate is consistent with the catalog '
        'on a known complete-athlete distribution', () {
      // Direct evaluator call — mirrors the seam the builder uses internally
      // but with no pre/post diff. Pins that a pure rank distribution
      // produces the expected slug set. Every active track (incl. cardio) at
      // rank 60.
      final ranks = <BodyPart, int>{for (final bp in activeBodyParts) bp: 60};
      final fired = CrossBuildTitleEvaluator.evaluate(ranks).toSet();
      // saga_forged fires (every active strength rank >= 60).
      // even_handed fires (every active rank >= 30 and spread = 0/60 = 0).
      // the_forged_wind fires (all six strength >= 60 AND cardio >= 60).
      // storm_tempered fires (cardio >= 60 AND all six strength >= 30).
      // iron_bound does NOT fire (Phase 38f: cardio 60 > 10 ceiling).
      // pillar_walker: legs=60 < 2×arms (2×60=120) → FALSE.
      // broad_shouldered: upper=180, lower=120 → 180 >= 240 is FALSE.
      expect(fired, contains('saga_forged'));
      expect(fired, contains('even_handed'));
      expect(fired, contains('the_forged_wind'));
      expect(fired, contains('storm_tempered'));
      expect(fired, isNot(contains('iron_bound')));
      expect(fired, isNot(contains('pillar_walker')));
      expect(fired, isNot(contains('broad_shouldered')));
    });
  });
}
