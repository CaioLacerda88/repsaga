import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/workouts/domain/post_session_timing.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';

/// Pins the post-session reward-tier classifier against the four canonical
/// fixtures from mockup-v2 §2 (Day-zero, Baseline, Threshold-anticipatory,
/// Class-change-anticipatory) and the steady-state hold-duration mapping.
///
/// Steady-state behavior — no phase numbering in test labels per
/// `feedback_phase_agnostic_test_names`.
void main() {
  group('RewardTier.derive', () {
    test('returns dayZero when the user has zero prior workouts', () {
      const result = CelebrationQueueResult(queue: []);
      final tier = RewardTier.derive(
        queueResult: result,
        priorFinishedWorkoutCount: 0,
        hasPersonalRecord: false,
      );
      expect(tier, RewardTier.dayZero);
    });

    test(
      'returns baseline when the user has prior workouts and no reward events',
      () {
        const result = CelebrationQueueResult(queue: []);
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: false,
        );
        expect(tier, RewardTier.baseline);
      },
    );

    test(
      'returns thresholdAnticipatory when a personal record is present even without a queue event',
      () {
        // PR fires via the prResult path, separate from the celebration queue.
        const result = CelebrationQueueResult(queue: []);
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: true,
        );
        expect(tier, RewardTier.thresholdAnticipatory);
      },
    );

    test(
      'returns thresholdAnticipatory when the queue carries a rank-up but no class-change (rank-up-only session)',
      () {
        const result = CelebrationQueueResult(
          queue: [RankUpEvent(bodyPart: BodyPart.chest, newRank: 19)],
        );
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: false,
        );
        // Mockup §2 RewardTier.derive note: Threshold-anticipatory accepts
        // `hasPR || hasRankUp`. Rank-up-only must NOT fall through to baseline.
        expect(tier, RewardTier.thresholdAnticipatory);
      },
    );

    test(
      'returns thresholdAnticipatory when a personal record co-occurs with a rank-up',
      () {
        const result = CelebrationQueueResult(
          queue: [RankUpEvent(bodyPart: BodyPart.chest, newRank: 19)],
        );
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: true,
        );
        expect(tier, RewardTier.thresholdAnticipatory);
      },
    );

    test(
      'returns classChangeAnticipatory when a class-change event is present (max-combo and class-change-only both land here)',
      () {
        const result = CelebrationQueueResult(
          queue: [
            ClassChangeEvent(
              fromClass: CharacterClass.initiate,
              toClass: CharacterClass.bulwark,
            ),
          ],
        );
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: false,
        );
        expect(tier, RewardTier.classChangeAnticipatory);
      },
    );

    test(
      'returns classChangeAnticipatory when a level-up event is present (level folds into the max variant)',
      () {
        const result = CelebrationQueueResult(
          queue: [LevelUpEvent(newLevel: 23)],
        );
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: false,
        );
        // Mockup §2 + §5 State 7: level-up folds into B1 copy via the
        // class-change-anticipatory (Max) variant with 120ms pre-roll.
        expect(tier, RewardTier.classChangeAnticipatory);
      },
    );

    test(
      'class-change always wins over PR + rank-up + level-up (max-combo state)',
      () {
        const result = CelebrationQueueResult(
          queue: [
            ClassChangeEvent(
              fromClass: CharacterClass.initiate,
              toClass: CharacterClass.bulwark,
            ),
            RankUpEvent(bodyPart: BodyPart.chest, newRank: 20),
            LevelUpEvent(newLevel: 24),
          ],
        );
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 46,
          hasPersonalRecord: true,
        );
        expect(tier, RewardTier.classChangeAnticipatory);
      },
    );

    test(
      'dayZero wins over all reward events (a first-ever session that earns a rank-up still reads as Day-zero)',
      () {
        // First-step gravity beats any in-session threshold — Day-zero copy
        // is the most emotionally-loaded line in the catalog and only earns
        // its slot once per user-lifetime.
        const result = CelebrationQueueResult(
          queue: [RankUpEvent(bodyPart: BodyPart.chest, newRank: 2)],
        );
        final tier = RewardTier.derive(
          queueResult: result,
          priorFinishedWorkoutCount: 0,
          hasPersonalRecord: true,
        );
        expect(tier, RewardTier.dayZero);
      },
    );
  });

  group('RewardTier — b1Hold duration mapping', () {
    // The numeric ms values are intentionally NOT hardcoded in these
    // assertions — they're sourced from PostSessionTiming so a future
    // retune (UX-critic passes have already retuned them twice — see the
    // dartdoc on PostSessionTiming) only touches the constants file.
    test('dayZero routes through PostSessionTiming.b1HoldDayZero', () {
      expect(RewardTier.dayZero.b1Hold, PostSessionTiming.b1HoldDayZero);
    });

    test('baseline routes through PostSessionTiming.b1HoldBaseline', () {
      expect(RewardTier.baseline.b1Hold, PostSessionTiming.b1HoldBaseline);
    });

    test('thresholdAnticipatory routes through '
        'PostSessionTiming.b1HoldThresholdAnticipatory', () {
      expect(
        RewardTier.thresholdAnticipatory.b1Hold,
        PostSessionTiming.b1HoldThresholdAnticipatory,
      );
    });

    test('classChangeAnticipatory routes through the class-change hold + '
        'carries the 120ms dead-black pre-roll', () {
      expect(
        RewardTier.classChangeAnticipatory.b1Hold,
        PostSessionTiming.b1HoldClassChangeAnticipatory,
      );
      expect(
        RewardTier.classChangeAnticipatory.b1PreRoll,
        PostSessionTiming.b1PreRollClassChangeAnticipatory,
      );
      // The pre-roll is a structural cinematic primitive (Concept B
      // grammar §0), not a parse-time floor that floats with UX retunes
      // — pin the exact ms value here.
      expect(RewardTier.classChangeAnticipatory.b1PreRoll.inMilliseconds, 120);
    });

    test('only classChangeAnticipatory carries a non-zero pre-roll', () {
      expect(RewardTier.dayZero.b1PreRoll, Duration.zero);
      expect(RewardTier.baseline.b1PreRoll, Duration.zero);
      expect(RewardTier.thresholdAnticipatory.b1PreRoll, Duration.zero);
    });
  });

  group('RewardTier baseline copy alternation', () {
    test(
      'baseline tier alternates copy across session counts (deterministic from session number)',
      () {
        // Per WIP.md PR 30a Open question #3 — locked: session-number-modulo-2
        // alternation between "ENCERRADO. MAIS FORTE." (A) and
        // "CONSISTÊNCIA VENCE." (B).
        final aSession = RewardTier.baseline.baselineCopyVariant(
          priorFinishedWorkoutCount: 2,
        );
        final bSession = RewardTier.baseline.baselineCopyVariant(
          priorFinishedWorkoutCount: 3,
        );
        expect(aSession, isNot(bSession));
      },
    );

    test(
      'baseline copy alternation is deterministic — same input, same output',
      () {
        final first = RewardTier.baseline.baselineCopyVariant(
          priorFinishedWorkoutCount: 47,
        );
        final second = RewardTier.baseline.baselineCopyVariant(
          priorFinishedWorkoutCount: 47,
        );
        expect(first, second);
      },
    );

    test(
      'baselineCopyVariant on non-baseline tiers always returns the primary variant (defensive)',
      () {
        // Other tiers have their own dedicated copy; the helper still exists
        // on the enum but the caller should never read it for non-baseline.
        // Pin the defensive return so a future refactor doesn't accidentally
        // alternate non-baseline copy.
        expect(
          RewardTier.dayZero.baselineCopyVariant(priorFinishedWorkoutCount: 0),
          BaselineCopyVariant.a,
        );
        expect(
          RewardTier.thresholdAnticipatory.baselineCopyVariant(
            priorFinishedWorkoutCount: 47,
          ),
          BaselineCopyVariant.a,
        );
      },
    );
  });
}
