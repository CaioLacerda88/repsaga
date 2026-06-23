/// Unit tests for [CelebrationEventBuilder] (Phase 18c, spec §13.2 wiring).
///
/// The builder is the pure-function bridge between two RPG snapshots
/// (pre-finish + post-finish) and the [CelebrationEvent] list that
/// [CelebrationQueue] consumes. It owns three independent concerns the
/// orchestrator (`ActiveWorkoutNotifier.finishWorkout`) used to inline:
///
///   * rank-up detection: per-body-part `rank` increases in the post snapshot
///   * level-up detection: `characterState.characterLevel` increases
///   * first-awakening detection: lifetime XP transitions 0 → >0 for a body
///     part, throttled to one fire per workout via the
///     `suppressFirstAwakening` flag the notifier sets after the first overlay
///   * title-unlock detection: delegated to [TitleUnlockDetector] given the
///     same rank deltas and the pre-save earned-slug set
///
/// **Why a pure builder instead of putting all this in the notifier**: the
/// notifier owns side-effects (Hive, Supabase, analytics, navigation). Pure
/// diff logic with no side effects is unit-testable without a Riverpod
/// container or a Supabase mock — and the boundary survives refactors of the
/// notifier's save flow because the builder doesn't depend on any of it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart';
import 'package:repsaga/features/rpg/domain/celebration_event_builder.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/rpg/models/title.dart' as rpg;
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';

const _userId = 'user-1';
final _now = DateTime.utc(2026, 4, 26);

BodyPartProgress _row(
  BodyPart bodyPart, {
  required double totalXp,
  required int rank,
}) => BodyPartProgress(
  userId: _userId,
  bodyPart: bodyPart,
  totalXp: totalXp,
  rank: rank,
  vitalityEwma: 0,
  vitalityPeak: 0,
  vitalityRefPeak: 0,
  lastEventAt: null,
  updatedAt: _now,
);

RpgProgressSnapshot _snapshot({
  required Map<BodyPart, BodyPartProgress> rows,
  required int level,
}) {
  return RpgProgressSnapshot(
    byBodyPart: rows,
    characterState: CharacterState(
      userId: _userId,
      characterLevel: level,
      maxRank: rows.values.fold<int>(1, (m, r) => r.rank > m ? r.rank : m),
      minRank: rows.values.fold<int>(1, (m, r) => r.rank < m ? r.rank : m),
      lifetimeXp: rows.values.fold<double>(0, (s, r) => s + r.totalXp),
    ),
  );
}

const _chestR5 = rpg.Title.bodyPart(
  slug: 'chest_r5_initiate_of_the_forge',
  bodyPart: BodyPart.chest,
  rankThreshold: 5,
);
const _legsR5 = rpg.Title.bodyPart(
  slug: 'legs_r5_ground_walker',
  bodyPart: BodyPart.legs,
  rankThreshold: 5,
);
const _wandererL10 = rpg.Title.characterLevel(
  slug: 'wanderer',
  levelThreshold: 10,
);
const _ironBoundCrossBuild = rpg.Title.crossBuild(
  slug: 'iron_bound',
  triggerId: rpg.CrossBuildTriggerId.ironBound,
);
const _catalog = <rpg.Title>[_chestR5, _legsR5];
const _fullCatalog = <rpg.Title>[
  _chestR5,
  _legsR5,
  _wandererL10,
  _ironBoundCrossBuild,
];

void main() {
  group('CelebrationEventBuilder.build', () {
    test('emits no events when nothing changed', () {
      // Idempotency floor: if `record_set_xp` produced no rank/level/title
      // delta (e.g. a workout below the rank-up threshold), the builder must
      // return an empty event list. The orchestrator hands that to the
      // queue, which returns an empty queue and skips overlay playback.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4)},
        level: 2,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 220, rank: 4)},
        level: 2,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(events, isEmpty);
    });

    test('emits a RankUpEvent for each body part whose rank increased', () {
      // Rank monotonicity invariant: rank can only go up. Every body part
      // whose post.rank > pre.rank surfaces as a rank-up event. The queue
      // re-orders by highest rank first; the builder is order-agnostic.
      final pre = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 100, rank: 3),
        },
        level: 2,
      );
      final post = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 260, rank: 5),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 150, rank: 5),
        },
        level: 3,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: const <rpg.Title>[],
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      final ranks = events
          .whereType<RankUpEvent>()
          .map((e) => '${e.bodyPart.dbValue}:${e.newRank}')
          .toSet();
      expect(ranks, {'chest:5', 'legs:5'});
    });

    test('emits at most one LevelUpEvent when characterLevel rolled over', () {
      // Character level is a derived scalar — at most one level-up per
      // workout finish even if multiple body parts contributed. The
      // builder reads the post snapshot's character_state directly; it
      // does not recompute levels client-side.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4)},
        level: 2,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 260, rank: 5)},
        level: 3,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: const <rpg.Title>[],
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<LevelUpEvent>(), hasLength(1));
      expect(events.whereType<LevelUpEvent>().single.newLevel, 3);
    });

    test(
      'emits FirstAwakeningEvent when a body part transitions 0 → >0 XP',
      () {
        // Onboarding moment: the very first set logged for a body part fires
        // the 800ms compressed overlay. Detected as: pre row missing (or
        // totalXp == 0) AND post.totalXp > 0.
        final pre = _snapshot(rows: const {}, level: 1);
        final post = _snapshot(
          rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 12, rank: 1)},
          level: 1,
        );

        final events = CelebrationEventBuilder.build(
          pre: pre,
          post: post,
          catalog: const <rpg.Title>[],
          alreadyEarnedSlugs: const {},
          suppressFirstAwakening: false,
        );

        expect(events.whereType<FirstAwakeningEvent>(), hasLength(1));
        expect(
          events.whereType<FirstAwakeningEvent>().single.bodyPart,
          BodyPart.chest,
        );
      },
    );

    test(
      'emits at most one FirstAwakeningEvent even when multiple body parts wake',
      () {
        // Throttle (PO): one awakening overlay per session max — even when
        // the user logs a back set AND a chest set in their first workout,
        // only ONE overlay plays. Subsequent body parts surface silently in
        // the character sheet's rune state changes.
        final pre = _snapshot(rows: const {}, level: 1);
        final post = _snapshot(
          rows: {
            BodyPart.chest: _row(BodyPart.chest, totalXp: 12, rank: 1),
            BodyPart.back: _row(BodyPart.back, totalXp: 10, rank: 1),
          },
          level: 1,
        );

        final events = CelebrationEventBuilder.build(
          pre: pre,
          post: post,
          catalog: const <rpg.Title>[],
          alreadyEarnedSlugs: const {},
          suppressFirstAwakening: false,
        );

        expect(events.whereType<FirstAwakeningEvent>(), hasLength(1));
      },
    );

    test(
      'suppresses FirstAwakeningEvent when notifier already fired this session',
      () {
        // Session-throttle precedent (Phase 18b Blocker): the flag lives on
        // the notifier and is reset on workout START, set after first
        // overlay. The builder honours the flag — second workout in the
        // same session emits no awakening even if a fresh body part wakes.
        final pre = _snapshot(rows: const {}, level: 1);
        final post = _snapshot(
          rows: {BodyPart.legs: _row(BodyPart.legs, totalXp: 8, rank: 1)},
          level: 1,
        );

        final events = CelebrationEventBuilder.build(
          pre: pre,
          post: post,
          catalog: const <rpg.Title>[],
          alreadyEarnedSlugs: const {},
          suppressFirstAwakening: true,
        );

        expect(events.whereType<FirstAwakeningEvent>(), isEmpty);
      },
    );

    test('emits TitleUnlockEvent for each newly-earned title', () {
      // Crown-of-the-workout. Builder runs TitleUnlockDetector against the
      // rank deltas + already-earned slug set. Already-earned titles are
      // filtered upstream by the detector — the builder is just the
      // adapter between snapshots and detector input.
      final pre = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 100, rank: 4),
        },
        level: 2,
      );
      final post = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 260, rank: 5),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 150, rank: 5),
        },
        level: 3,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      final slugs = events
          .whereType<TitleUnlockEvent>()
          .map((e) => e.slug)
          .toSet();
      expect(slugs, {
        'chest_r5_initiate_of_the_forge',
        'legs_r5_ground_walker',
      });
    });

    test('skips TitleUnlockEvents for slugs already in alreadyEarnedSlugs', () {
      // Idempotency guard: if the user already earned this title in a
      // prior workout (and the rank-up event is re-emitted via a server
      // retry quirk), the builder must not re-fire the unlock half-sheet.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4)},
        level: 2,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 260, rank: 5)},
        level: 3,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _catalog,
        alreadyEarnedSlugs: const {'chest_r5_initiate_of_the_forge'},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<TitleUnlockEvent>(), isEmpty);
    });

    test('emits character-level TitleUnlockEvent on level-up (Phase 18e)', () {
      // The level-up overlay is one event; the title half-sheet for crossing
      // a character-level threshold is a SEPARATE event. Both fire when the
      // post snapshot crosses both thresholds in the same finish.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4)},
        level: 9,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 260, rank: 4)},
        level: 10,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _fullCatalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<LevelUpEvent>(), hasLength(1));
      expect(
        events.whereType<TitleUnlockEvent>().map((e) => e.slug).toSet(),
        contains('wanderer'),
      );
    });

    test('emits cross-build TitleUnlockEvent when post-save distribution fires '
        'a predicate (Phase 18e)', () {
      // Cross-build detection runs every finish, not just on rank-ups —
      // the predicate is a snapshot property of the post-save distribution.
      // Here a workout that doesn't change ranks (chest/back/legs already
      // at 60) but pushes legs from 59 → 60 must fire iron_bound.
      final pre = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 1000, rank: 60),
          BodyPart.back: _row(BodyPart.back, totalXp: 1000, rank: 60),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 950, rank: 59),
        },
        level: 30,
      );
      final post = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 1000, rank: 60),
          BodyPart.back: _row(BodyPart.back, totalXp: 1000, rank: 60),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 1010, rank: 60),
        },
        level: 30,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _fullCatalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(
        events.whereType<TitleUnlockEvent>().map((e) => e.slug).toSet(),
        contains('iron_bound'),
      );
    });

    test('cross-build idempotency: already-earned slugs do not re-emit on '
        'subsequent finishes (Phase 18e)', () {
      // The detector's idempotency guard must propagate through the
      // builder. A user whose post snapshot still satisfies the predicate
      // but who already owns the slug must not see it again.
      final pre = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 1000, rank: 60),
          BodyPart.back: _row(BodyPart.back, totalXp: 1000, rank: 60),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 1000, rank: 60),
        },
        level: 30,
      );
      final post = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 1100, rank: 60),
          BodyPart.back: _row(BodyPart.back, totalXp: 1100, rank: 60),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 1100, rank: 60),
        },
        level: 30,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _fullCatalog,
        alreadyEarnedSlugs: const {'iron_bound'},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<TitleUnlockEvent>(), isEmpty);
    });

    // -------------------------------------------------------------------------
    // BUG-011 (Cluster 3) — ClassChangeEvent detection
    // -------------------------------------------------------------------------
    test(
      'emits ClassChangeEvent on Initiate → Bulwark transition (BUG-011)',
      () {
        // Day-1 lifter completes their first chest workout. Pre snapshot:
        // every body part at rank 1 → ClassResolver returns Initiate.
        // Post snapshot: chest at rank 5, others at rank 1 → ClassResolver
        // returns Bulwark (chest-dominant, max=5≥5, spread=0.80>0.30).
        final pre = _snapshot(
          rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 200, rank: 4)},
          level: 1,
        );
        final post = _snapshot(
          rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 280, rank: 5)},
          level: 1,
        );

        final events = CelebrationEventBuilder.build(
          pre: pre,
          post: post,
          catalog: const <rpg.Title>[],
          alreadyEarnedSlugs: const {},
          suppressFirstAwakening: false,
        );

        final classChanges = events.whereType<ClassChangeEvent>().toList();
        expect(classChanges, hasLength(1));
        expect(classChanges.single.fromClass, CharacterClass.initiate);
        expect(classChanges.single.toClass, CharacterClass.bulwark);
      },
    );

    test('does NOT emit ClassChangeEvent when pre and post classes match', () {
      // Idempotency floor for class transitions. A workout that pushes
      // chest from rank 8 to rank 9 keeps the lifter in Bulwark — no
      // class-change overlay should fire.
      final pre = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 600, rank: 8)},
        level: 2,
      );
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 700, rank: 9)},
        level: 2,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: const <rpg.Title>[],
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<ClassChangeEvent>(), isEmpty);
    });

    test('emits ClassChangeEvent on a non-Initiate transition (Bulwark → '
        'Sentinel)', () {
      // Spec: every transition fires, not just from Initiate. A back
      // workout that pulls back's rank past chest's flips the dominant
      // class from chest (Bulwark) to back (Sentinel).
      final pre = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 1000, rank: 10),
          BodyPart.back: _row(BodyPart.back, totalXp: 100, rank: 5),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 100, rank: 5),
          BodyPart.shoulders: _row(BodyPart.shoulders, totalXp: 100, rank: 5),
          BodyPart.arms: _row(BodyPart.arms, totalXp: 100, rank: 5),
          BodyPart.core: _row(BodyPart.core, totalXp: 100, rank: 5),
        },
        level: 3,
      );
      final post = _snapshot(
        rows: {
          BodyPart.chest: _row(BodyPart.chest, totalXp: 1000, rank: 10),
          BodyPart.back: _row(BodyPart.back, totalXp: 1500, rank: 11),
          BodyPart.legs: _row(BodyPart.legs, totalXp: 100, rank: 5),
          BodyPart.shoulders: _row(BodyPart.shoulders, totalXp: 100, rank: 5),
          BodyPart.arms: _row(BodyPart.arms, totalXp: 100, rank: 5),
          BodyPart.core: _row(BodyPart.core, totalXp: 100, rank: 5),
        },
        level: 3,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: const <rpg.Title>[],
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      final classChanges = events.whereType<ClassChangeEvent>().toList();
      expect(classChanges, hasLength(1));
      expect(classChanges.single.fromClass, CharacterClass.bulwark);
      expect(classChanges.single.toClass, CharacterClass.sentinel);
    });

    test('handles missing pre snapshot row as oldRank=1 / 0 XP', () {
      // Brand-new user finishing their very first workout: the pre
      // snapshot has no row for the body part (the SQL default-row insert
      // happens server-side inside `record_set_xp`). The builder must
      // treat missing-row as `rank=1, totalXp=0` for both the rank delta
      // and the awakening detection — otherwise a first-set workout would
      // either crash or emit no rank-up event.
      final pre = _snapshot(rows: const {}, level: 1);
      final post = _snapshot(
        rows: {BodyPart.chest: _row(BodyPart.chest, totalXp: 320, rank: 5)},
        level: 2,
      );

      final events = CelebrationEventBuilder.build(
        pre: pre,
        post: post,
        catalog: _catalog,
        alreadyEarnedSlugs: const {},
        suppressFirstAwakening: false,
      );

      expect(events.whereType<RankUpEvent>(), hasLength(1));
      expect(events.whereType<RankUpEvent>().single.newRank, 5);
      expect(events.whereType<FirstAwakeningEvent>(), hasLength(1));
      expect(
        events.whereType<TitleUnlockEvent>().map((e) => e.slug),
        contains('chest_r5_initiate_of_the_forge'),
      );
    });
  });
}
