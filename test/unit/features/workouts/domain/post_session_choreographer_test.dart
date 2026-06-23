import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/workouts/domain/post_session_choreographer.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';

/// Pins the post-session cut sequence per the State 1-10 storyboards.
///
/// Mockup-locked cut counts (WIP.md PR 30a acceptance criteria #2):
///   S1=2 cuts (B1 + B2 single)
///   S2=2 cuts (B1 + B2 single)
///   S3=3 cuts (B1 + B2 single + B3 PR)
///   S4=3 cuts (B1 + B2 single + B3 PR)
///   S5=2 cuts (B1 + B2 elevated rank-up) — NOTE: WIP.md says 3 but mockup §5
///     shows B1 → B2 bar fill → B2 elevated rank slam → summary. The "B2 bar
///     fill" + "B2 rank slam" are one elevated cut animated in two phases;
///     count is 2 cinematic cuts pre-summary.
///   S6=3 cuts (B1 + B2 cascade + B2 elevated top rank-up)
///   S7=2 cuts (B1 max + B2 single — no B3, level folds into B1)
///   S8=3 cuts (B1 + B2 single + B3 title)
///   S9=2 cuts (B1 max + B3 class change — B2 skipped)
///   S10=4 cuts (B1 max + B2 elevated rank-up + B3 PR + B3 class change)
///
/// Cuts here are pre-summary; the summary panel is rendered separately.
void main() {
  PersonalRecord makePr({
    required String exerciseId,
    required double weight,
    required int reps,
  }) {
    return PersonalRecord(
      id: 'r-$exerciseId-$weight-$reps',
      userId: 'u1',
      exerciseId: exerciseId,
      recordType: RecordType.maxWeight,
      value: weight,
      achievedAt: DateTime.utc(2026, 5, 22),
      reps: reps,
    );
  }

  group('PostSessionChoreographer.build — state coverage', () {
    test(
      'State 1 (day-zero, single BP, first awakening) emits B1 + B2 single',
      () {
        final cuts = PostSessionChoreographer.build(
          tier: RewardTier.dayZero,
          queueResult: const CelebrationQueueResult(queue: []),
          bpXpDeltas: {BodyPart.chest: 118},
          bpRankAfter: {BodyPart.chest: 1},
          bpProgressFractionAfter: {BodyPart.chest: 0.12},
          bpFirstAwakening: {BodyPart.chest},
          prResult: null,
          exerciseNames: const {},
          newCharacterLevel: null,
          priorFinishedWorkoutCount: 0,
          totalXpEarned: 118,
        );
        expect(cuts, hasLength(2));
        expect(cuts[0], isA<B1XpCut>());
        expect((cuts[0] as B1XpCut).tier, RewardTier.dayZero);
        expect(cuts[1], isA<B2SingleBpCut>());
        final b2 = cuts[1] as B2SingleBpCut;
        expect(b2.bodyPart, BodyPart.chest);
        expect(b2.isFirstAwakening, isTrue);
        expect(b2.xpEarned, 118);
      },
    );

    test('State 2 (baseline, single BP) emits B1 + B2 single, no B3', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {BodyPart.chest: 412},
        bpRankAfter: {BodyPart.chest: 17},
        bpProgressFractionAfter: {BodyPart.chest: 0.47},
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 412,
      );
      expect(cuts, hasLength(2));
      expect(cuts[0], isA<B1XpCut>());
      expect(cuts[1], isA<B2SingleBpCut>());
    });

    test('State 3 (single PR) emits B1 + B2 single (PR muscle) + B3 PR', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {BodyPart.chest: 618},
        bpRankAfter: {BodyPart.chest: 17},
        bpProgressFractionAfter: {BodyPart.chest: 0.78},
        bpFirstAwakening: const {},
        prResult: PRDetectionResult(
          newRecords: [makePr(exerciseId: 'bench-press', weight: 95, reps: 5)],
          isFirstWorkout: false,
        ),
        exerciseNames: const {'bench-press': 'Supino'},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 618,
      );
      expect(cuts, hasLength(3));
      expect(cuts[0], isA<B1XpCut>());
      expect(cuts[1], isA<B2SingleBpCut>());
      expect(cuts[2], isA<B3PrCut>());
      final pr = cuts[2] as B3PrCut;
      expect(pr.heroExerciseName, 'Supino');
      expect(pr.heroWeightKg, 95);
      expect(pr.heroReps, 5);
      expect(pr.pillRows, isEmpty);
      expect(pr.truncatedPillCount, 0);
    });

    test(
      'State 4 (multi-PR, hero by weight×reps, pills max 3 + truncation pill)',
      () {
        final cuts = PostSessionChoreographer.build(
          tier: RewardTier.thresholdAnticipatory,
          queueResult: const CelebrationQueueResult(queue: []),
          bpXpDeltas: {BodyPart.chest: 340, BodyPart.legs: 280},
          bpRankAfter: {BodyPart.chest: 17, BodyPart.legs: 13},
          bpProgressFractionAfter: {BodyPart.chest: 0.88, BodyPart.legs: 0.50},
          bpFirstAwakening: const {},
          prResult: PRDetectionResult(
            newRecords: [
              makePr(exerciseId: 'bench', weight: 95, reps: 5), // score 475
              makePr(exerciseId: 'squat', weight: 120, reps: 3), // score 360
              makePr(exerciseId: 'row', weight: 70, reps: 8), // score 560
              makePr(exerciseId: 'curl', weight: 22, reps: 8), // score 176
              makePr(exerciseId: 'press', weight: 50, reps: 10), // score 500
            ],
            isFirstWorkout: false,
          ),
          exerciseNames: const {
            'bench': 'Supino',
            'squat': 'Agachamento',
            'row': 'Remada',
            'curl': 'Rosca',
            'press': 'Desenvolvimento',
          },
          newCharacterLevel: null,
          priorFinishedWorkoutCount: 46,
          totalXpEarned: 894,
        );
        expect(cuts, hasLength(3));
        final pr = cuts[2] as B3PrCut;
        // Hero is Remada (70×8 = 560, highest score).
        expect(pr.heroExerciseName, 'Remada');
        // 3 pills + 1 truncated (4 remaining after hero, cap at 3).
        expect(pr.pillRows, hasLength(3));
        expect(pr.truncatedPillCount, 1);
      },
    );

    test('State 5 (single rank-up, no PR) emits B1 + B2 elevated rank-up', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: const CelebrationQueueResult(
          queue: [RankUpEvent(bodyPart: BodyPart.chest, newRank: 19)],
        ),
        bpXpDeltas: {BodyPart.chest: 520},
        bpRankAfter: {BodyPart.chest: 19},
        bpProgressFractionAfter: {BodyPart.chest: 0.05},
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 520,
      );
      expect(cuts, hasLength(2));
      expect(cuts[0], isA<B1XpCut>());
      expect(cuts[1], isA<B2ElevatedRankUpCut>());
      final elevated = cuts[1] as B2ElevatedRankUpCut;
      expect(elevated.bodyPart, BodyPart.chest);
      expect(elevated.newRank, 19);
    });

    test(
      'State 6 (multi rank-up, 3 BPs) emits B1 + B2 cascade + B2 elevated top',
      () {
        final cuts = PostSessionChoreographer.build(
          tier: RewardTier.thresholdAnticipatory,
          queueResult: const CelebrationQueueResult(
            queue: [
              RankUpEvent(bodyPart: BodyPart.legs, newRank: 14),
              RankUpEvent(bodyPart: BodyPart.chest, newRank: 17),
            ],
          ),
          bpXpDeltas: {
            BodyPart.legs: 340,
            BodyPart.chest: 220,
            BodyPart.back: 150,
          },
          bpRankAfter: {
            BodyPart.legs: 14,
            BodyPart.chest: 17,
            BodyPart.back: 14,
          },
          bpProgressFractionAfter: {
            BodyPart.legs: 0.05,
            BodyPart.chest: 0.40,
            BodyPart.back: 0.30,
          },
          bpFirstAwakening: const {},
          prResult: null,
          exerciseNames: const {},
          newCharacterLevel: null,
          priorFinishedWorkoutCount: 46,
          totalXpEarned: 710,
        );
        expect(cuts, hasLength(3));
        expect(cuts[0], isA<B1XpCut>());
        expect(cuts[1], isA<B2CascadeCut>());
        expect(cuts[2], isA<B2ElevatedRankUpCut>());
        // Top rank-up: Legs (newRank 14 > Chest newRank 17? compare by newRank
        // descending; tie-break by dbValue. Chest has rank 17 > Legs rank 14;
        // so the top rank-up is Chest.) — Actually highest newRank wins.
        // Chest newRank = 17, Legs newRank = 14, so Chest is the top rank-up.
        final elevated = cuts[2] as B2ElevatedRankUpCut;
        expect(elevated.bodyPart, BodyPart.chest);
        expect(elevated.newRank, 17);
      },
    );

    test(
      'State 7 (level-up only, no PR, no rank-up) emits B1 max + B2, no B3',
      () {
        final cuts = PostSessionChoreographer.build(
          tier: RewardTier.classChangeAnticipatory,
          queueResult: const CelebrationQueueResult(
            queue: [LevelUpEvent(newLevel: 23)],
          ),
          bpXpDeltas: {BodyPart.chest: 540},
          bpRankAfter: {BodyPart.chest: 17},
          bpProgressFractionAfter: {BodyPart.chest: 0.62},
          bpFirstAwakening: const {},
          prResult: null,
          exerciseNames: const {},
          newCharacterLevel: 23,
          priorFinishedWorkoutCount: 46,
          totalXpEarned: 540,
        );
        expect(cuts, hasLength(2));
        expect(cuts[0], isA<B1XpCut>());
        expect((cuts[0] as B1XpCut).newCharacterLevel, 23);
        expect(cuts[1], isA<B2SingleBpCut>());
      },
    );

    test('State 8 (title unlocked, no PR) emits B1 + B2 single + B3 title', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: const CelebrationQueueResult(
          queue: [TitleUnlockEvent(slug: 'chest_r20_pilar_de_ferro')],
        ),
        bpXpDeltas: {BodyPart.chest: 580},
        bpRankAfter: {BodyPart.chest: 20},
        bpProgressFractionAfter: {BodyPart.chest: 0.05},
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 580,
      );
      expect(cuts, hasLength(3));
      expect(cuts[0], isA<B1XpCut>());
      expect(cuts[1], isA<B2SingleBpCut>());
      expect(cuts[2], isA<B3TitleCut>());
      final title = cuts[2] as B3TitleCut;
      expect(title.titleSlug, 'chest_r20_pilar_de_ferro');
      expect(title.variant, TitleCutVariant.bodyPartTyped);
    });

    test(
      'State 9 (class change only, no rank-up, no PR) emits B1 + B3 class change — B2 SKIPPED',
      () {
        final cuts = PostSessionChoreographer.build(
          tier: RewardTier.classChangeAnticipatory,
          queueResult: const CelebrationQueueResult(
            queue: [
              ClassChangeEvent(
                fromClass: CharacterClass.initiate,
                toClass: CharacterClass.bulwark,
              ),
            ],
          ),
          bpXpDeltas: {BodyPart.chest: 640},
          bpRankAfter: {BodyPart.chest: 17},
          bpProgressFractionAfter: {BodyPart.chest: 0.80},
          bpFirstAwakening: const {},
          prResult: null,
          exerciseNames: const {},
          newCharacterLevel: null,
          priorFinishedWorkoutCount: 46,
          totalXpEarned: 640,
        );
        expect(cuts, hasLength(2));
        expect(cuts[0], isA<B1XpCut>());
        // Critical: B2 is skipped — class-change without rank-up jumps
        // straight to B3.
        expect(cuts[1], isA<B3ClassChangeCut>());
        expect(cuts.whereType<B2SingleBpCut>(), isEmpty);
        expect(cuts.whereType<B2CascadeCut>(), isEmpty);
      },
    );

    test(
      'State 10 (max combo — PR + rank + level + class) emits B1 + B2 elevated + B3 PR + B3 class change',
      () {
        final cuts = PostSessionChoreographer.build(
          tier: RewardTier.classChangeAnticipatory,
          queueResult: const CelebrationQueueResult(
            queue: [
              ClassChangeEvent(
                fromClass: CharacterClass.initiate,
                toClass: CharacterClass.bulwark,
              ),
              RankUpEvent(bodyPart: BodyPart.chest, newRank: 20),
              LevelUpEvent(newLevel: 24),
            ],
          ),
          bpXpDeltas: {BodyPart.chest: 1042},
          bpRankAfter: {BodyPart.chest: 20},
          bpProgressFractionAfter: {BodyPart.chest: 0.10},
          bpFirstAwakening: const {},
          prResult: PRDetectionResult(
            newRecords: [makePr(exerciseId: 'bench', weight: 100, reps: 5)],
            isFirstWorkout: false,
          ),
          exerciseNames: const {'bench': 'Supino'},
          newCharacterLevel: 24,
          priorFinishedWorkoutCount: 46,
          totalXpEarned: 1042,
        );
        expect(cuts, hasLength(4));
        expect(cuts[0], isA<B1XpCut>());
        expect((cuts[0] as B1XpCut).newCharacterLevel, 24);
        // B2 is the elevated rank-up (rank-up co-occurs with PR — rank-up
        // gets B2 elevated; PR cuts are anchored to B3).
        // BUT mockup §5 State 10 script: "rank-up promotes to B2 elevated,
        // PR + class change are the two Beat 3 cuts". In our impl when PR
        // co-occurs with rank-up the rank-up still wins B2 elevated.
        // Implementation note: we gate B2 elevated on `!hasPr`. Re-read
        // mockup: when BOTH fire (max-combo) the rank-up DOES still take
        // B2 elevated. Adjust expected: cuts[1] = elevated rank-up.
        // (See test rationale below — implementation TBD; this test pins
        // the mockup-correct behavior.)
        expect(cuts[1], isA<B2ElevatedRankUpCut>());
        expect(cuts[2], isA<B3PrCut>());
        expect(cuts[3], isA<B3ClassChangeCut>());
      },
    );

    test('Title cut variant selection — character-level slug', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: const CelebrationQueueResult(
          queue: [TitleUnlockEvent(slug: 'level_25_veterano')],
        ),
        bpXpDeltas: {BodyPart.chest: 420},
        bpRankAfter: {BodyPart.chest: 17},
        bpProgressFractionAfter: {BodyPart.chest: 0.40},
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 420,
      );
      expect(cuts.last, isA<B3TitleCut>());
      expect((cuts.last as B3TitleCut).variant, TitleCutVariant.characterLevel);
    });

    test('Title cut variant selection — cross-build slug', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: const CelebrationQueueResult(
          queue: [TitleUnlockEvent(slug: 'pillar_walker_default')],
        ),
        bpXpDeltas: {BodyPart.legs: 420},
        bpRankAfter: {BodyPart.legs: 17},
        bpProgressFractionAfter: {BodyPart.legs: 0.40},
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 420,
      );
      expect(cuts.last, isA<B3TitleCut>());
      expect((cuts.last as B3TitleCut).variant, TitleCutVariant.crossBuild);
    });
  });

  group('PostSessionChoreographer — dominant BP selection', () {
    test('highest XP wins (single highest)', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {
          BodyPart.chest: 100,
          BodyPart.legs: 300,
          BodyPart.back: 200,
        },
        bpRankAfter: {BodyPart.chest: 10, BodyPart.legs: 10, BodyPart.back: 10},
        bpProgressFractionAfter: {
          BodyPart.chest: 0.3,
          BodyPart.legs: 0.3,
          BodyPart.back: 0.3,
        },
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 600,
      );
      expect(cuts[1], isA<B2CascadeCut>());
      expect((cuts[1] as B2CascadeCut).heroBodyPart, BodyPart.legs);
    });

    test('tied XP → highest rank wins', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {
          BodyPart.chest: 200,
          BodyPart.legs: 200,
          BodyPart.back: 200,
        },
        bpRankAfter: {
          BodyPart.chest: 5,
          BodyPart.legs: 15, // highest rank
          BodyPart.back: 10,
        },
        bpProgressFractionAfter: {
          BodyPart.chest: 0.3,
          BodyPart.legs: 0.3,
          BodyPart.back: 0.3,
        },
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 600,
      );
      expect((cuts[1] as B2CascadeCut).heroBodyPart, BodyPart.legs);
    });

    test('tied XP + tied rank → alphabetical dbValue wins', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {
          BodyPart.chest: 200,
          BodyPart.legs: 200,
          BodyPart.back: 200, // back < chest < legs alphabetically
        },
        bpRankAfter: {BodyPart.chest: 10, BodyPart.legs: 10, BodyPart.back: 10},
        bpProgressFractionAfter: {
          BodyPart.chest: 0.3,
          BodyPart.legs: 0.3,
          BodyPart.back: 0.3,
        },
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 600,
      );
      expect((cuts[1] as B2CascadeCut).heroBodyPart, BodyPart.back);
    });
  });

  group('PostSessionChoreographer — conditioning charge threading', () {
    test('single-BP hero carries charge fraction/max/delta from bpCharge', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {BodyPart.back: 340},
        bpRankAfter: {BodyPart.back: 9},
        bpProgressFractionAfter: {BodyPart.back: 0.64},
        bpFirstAwakening: const {},
        bpCharge: const {
          BodyPart.back: (
            afterPct: 0.64,
            isMax: false,
            isHeld: false,
            deltaPercent: 17,
          ),
        },
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 340,
      );
      final hero = cuts[1] as B2SingleBpCut;
      expect(hero.chargeFractionAfter, 0.64);
      expect(hero.isChargeMax, isFalse);
      expect(hero.chargeDeltaPercent, 17);
    });

    test('MÁX charge threads isChargeMax true', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {BodyPart.legs: 210},
        bpRankAfter: {BodyPart.legs: 14},
        bpProgressFractionAfter: {BodyPart.legs: 0.88},
        bpFirstAwakening: const {},
        bpCharge: const {
          BodyPart.legs: (
            afterPct: 1.0,
            isMax: true,
            isHeld: false,
            deltaPercent: 0,
          ),
        },
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 210,
      );
      final hero = cuts[1] as B2SingleBpCut;
      expect(hero.isChargeMax, isTrue);
      expect(hero.chargeFractionAfter, 1.0);
    });

    test('elevated rank-up hero carries charge from bpCharge', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: const CelebrationQueueResult(
          queue: [RankUpEvent(bodyPart: BodyPart.core, newRank: 12)],
        ),
        bpXpDeltas: {BodyPart.core: 480},
        bpRankAfter: {BodyPart.core: 12},
        bpProgressFractionAfter: {BodyPart.core: 0.04},
        bpFirstAwakening: const {},
        bpCharge: const {
          BodyPart.core: (
            afterPct: 0.55,
            isMax: false,
            isHeld: false,
            deltaPercent: 24,
          ),
        },
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 480,
      );
      final elevated = cuts[1] as B2ElevatedRankUpCut;
      expect(elevated.chargeFractionAfter, 0.55);
      expect(elevated.chargeDeltaPercent, 24);
    });

    test('cascade hero carries charge; rune rides hero only', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {
          BodyPart.core: 480,
          BodyPart.back: 220,
          BodyPart.arms: 150,
        },
        bpRankAfter: {BodyPart.core: 12, BodyPart.back: 9, BodyPart.arms: 8},
        bpProgressFractionAfter: {
          BodyPart.core: 0.04,
          BodyPart.back: 0.3,
          BodyPart.arms: 0.2,
        },
        bpFirstAwakening: const {},
        bpCharge: const {
          BodyPart.core: (
            afterPct: 0.55,
            isMax: false,
            isHeld: false,
            deltaPercent: 24,
          ),
          BodyPart.back: (
            afterPct: 0.4,
            isMax: false,
            isHeld: false,
            deltaPercent: 17,
          ),
        },
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 850,
      );
      final cascade = cuts[1] as B2CascadeCut;
      expect(cascade.heroBodyPart, BodyPart.core);
      expect(cascade.heroChargeFractionAfter, 0.55);
      expect(cascade.heroChargeDeltaPercent, 24);
    });

    test('sequential dominant carries charge; secondary stays rune-less', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {BodyPart.back: 340, BodyPart.arms: 120},
        bpRankAfter: {BodyPart.back: 9, BodyPart.arms: 6},
        bpProgressFractionAfter: {BodyPart.back: 0.64, BodyPart.arms: 0.3},
        bpFirstAwakening: const {},
        bpCharge: const {
          BodyPart.back: (
            afterPct: 0.64,
            isMax: false,
            isHeld: false,
            deltaPercent: 17,
          ),
          BodyPart.arms: (
            afterPct: 0.5,
            isMax: false,
            isHeld: false,
            deltaPercent: 12,
          ),
        },
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 460,
      );
      final dominant = cuts[1] as B2SequentialDominantCut;
      final secondary = cuts[2] as B2SequentialSecondaryCut;
      expect(dominant.chargeFractionAfter, 0.64);
      expect(dominant.chargeDeltaPercent, 17);
      // Secondary stays rune-less even though arms HAS charge data — the
      // cinematic rune rides the hero only.
      expect(secondary.chargeFractionAfter, isNull);
    });

    test('no bpCharge entry → hero cut has null charge (unchanged beat)', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {BodyPart.chest: 412},
        bpRankAfter: {BodyPart.chest: 17},
        bpProgressFractionAfter: {BodyPart.chest: 0.47},
        bpFirstAwakening: const {},
        // bpCharge omitted (defaults empty).
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 412,
      );
      final hero = cuts[1] as B2SingleBpCut;
      expect(hero.chargeFractionAfter, isNull);
      expect(hero.isChargeMax, isFalse);
      expect(hero.chargeDeltaPercent, 0);
    });
  });

  group('PostSessionChoreographer — cascade truncation', () {
    test('4 BPs cascade with 3 rows, no truncation', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {
          BodyPart.legs: 400,
          BodyPart.chest: 300,
          BodyPart.back: 200,
          BodyPart.shoulders: 100,
        },
        bpRankAfter: {
          BodyPart.legs: 10,
          BodyPart.chest: 10,
          BodyPart.back: 10,
          BodyPart.shoulders: 10,
        },
        bpProgressFractionAfter: {
          BodyPart.legs: 0.3,
          BodyPart.chest: 0.3,
          BodyPart.back: 0.3,
          BodyPart.shoulders: 0.3,
        },
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 1000,
      );
      final cascade = cuts[1] as B2CascadeCut;
      expect(cascade.cascadeRows, hasLength(3));
      expect(cascade.truncatedCount, 0);
    });

    test('6 BPs cascade truncates at 4 rows + "+1" pill', () {
      final cuts = PostSessionChoreographer.build(
        tier: RewardTier.baseline,
        queueResult: const CelebrationQueueResult(queue: []),
        bpXpDeltas: {
          BodyPart.legs: 600,
          BodyPart.chest: 500,
          BodyPart.back: 400,
          BodyPart.shoulders: 300,
          BodyPart.arms: 200,
          BodyPart.core: 100,
        },
        bpRankAfter: {
          BodyPart.legs: 10,
          BodyPart.chest: 10,
          BodyPart.back: 10,
          BodyPart.shoulders: 10,
          BodyPart.arms: 10,
          BodyPart.core: 10,
        },
        bpProgressFractionAfter: {
          BodyPart.legs: 0.3,
          BodyPart.chest: 0.3,
          BodyPart.back: 0.3,
          BodyPart.shoulders: 0.3,
          BodyPart.arms: 0.3,
          BodyPart.core: 0.3,
        },
        bpFirstAwakening: const {},
        prResult: null,
        exerciseNames: const {},
        newCharacterLevel: null,
        priorFinishedWorkoutCount: 46,
        totalXpEarned: 2100,
      );
      final cascade = cuts[1] as B2CascadeCut;
      expect(cascade.cascadeRows, hasLength(4));
      expect(cascade.truncatedCount, 1);
    });
  });
}
