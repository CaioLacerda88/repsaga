import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_state.dart';

/// Pins the steady-state contract of `PostSessionStateX.hasShareCta`:
/// the SHARE button on the summary panel is visible for any session
/// that earned XP — regardless of PR / rank-up / title / class-change.
///
/// The pre-round-3 rule gated visibility on the event queue carrying a
/// "rare moment" (PR / RankUp / TitleUnlock / ClassChange). That rule
/// continues to drive WHICH share-card variant renders (see
/// `SharePayloadCta.hasShareCta` in `share_payload.dart`) but no longer
/// gates the panel button itself — a baseline rep-out is still a saga
/// worth sharing.
void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  PostSessionState buildState({
    required int totalXpEarned,
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
      bpXpDeltas: const {},
      bpRankAfter: const {},
      bpRankBefore: const {},
      topLifts: const [],
      totalExercisesTrained: 0,
      totalXpEarned: totalXpEarned,
      priorFinishedWorkoutCount: 0,
      sagaNumber: 1,
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

  // ---------------------------------------------------------------------------
  // hasShareCta — new rule (totalXpEarned > 0)
  // ---------------------------------------------------------------------------

  group('PostSessionStateX.hasShareCta', () {
    test('baseline session with XP earned shows share CTA', () {
      // The round-3 contract: a baseline rep-out (no PR, no rank-up, no
      // class-change, no title) is still shareable as long as it earned XP.
      // Locks the fix for the round-3 UX critique that hid the button on
      // most lifters' most-common session shape.
      expect(buildState(totalXpEarned: 1).hasShareCta, isTrue);
      expect(buildState(totalXpEarned: 340).hasShareCta, isTrue);
    });

    test('zero-XP session hides share CTA (defensive boundary)', () {
      // The pathological "no XP" case — a workout that registered no
      // working sets, or a sync edge-case where deltas resolved to zero.
      // The CTA stays hidden so we never surface an empty share card.
      expect(buildState(totalXpEarned: 0).hasShareCta, isFalse);
    });

    test('isPlayingCinematic stays driven by cut index, unaffected', () {
      // Smoke-check that the sibling extension getter is independent —
      // round-3 only touched `hasShareCta`.
      final state = buildState(totalXpEarned: 100);
      expect(state.isPlayingCinematic, isFalse); // cuts empty → not playing
    });
  });
}
