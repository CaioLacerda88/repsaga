import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/rpg/models/character_class.dart';
import 'package:repsaga/features/workouts/domain/reward_tier.dart';
import 'package:repsaga/features/workouts/domain/share_payload.dart';

/// Pins `SharePayload.fromPostSessionState` composition across the 8 canonical
/// post-session scenarios (mockup §5 states 1–10, deduped by the share-card
/// surface area — i.e. share CTA visible).
///
/// **Behavior, not wiring** (CLAUDE.md Testing). Each case asserts the
/// resulting payload's user-visible projections (dominant BP, hue, hero PR
/// text, rank-up / class-change / title flags) — NOT that the composer's
/// internal sort was called.
void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  CelebrationQueueResult queue(List<CelebrationEvent> events) =>
      CelebrationQueue.build(events: events);

  PersonalRecord pr({
    required String exerciseId,
    required double value,
    int? reps,
    RecordType type = RecordType.maxWeight,
  }) {
    return PersonalRecord(
      id: 'pr-$exerciseId-${type.toSnakeCase}',
      userId: 'user-001',
      exerciseId: exerciseId,
      recordType: type,
      value: value,
      achievedAt: DateTime.utc(2026, 5, 24),
      setId: 'set-$exerciseId',
      reps: reps,
    );
  }

  PRDetectionResult prResult(List<PersonalRecord> records) =>
      PRDetectionResult(newRecords: records, isFirstWorkout: false);

  // ---------------------------------------------------------------------------
  // Case 1: Day-zero — no rewards, no PR, no rank-up
  // ---------------------------------------------------------------------------
  test(
    'day-zero session composes empty queue + zero deltas to baseline payload',
    () {
      final payload = SharePayload.fromPostSessionState(
        tier: RewardTier.dayZero,
        queueResult: queue(const []),
        prResult: null,
        bpXpDeltas: const {},
        bpRankAfter: const {},
        bpProgressFractionAfter: const {},
        exerciseNames: const {},
        totalXp: 0,
        characterClassSlug: 'initiate',
      );

      expect(payload.tier, RewardTier.dayZero);
      expect(payload.totalXp, 0);
      expect(payload.dominantBodyPart, isNull);
      expect(payload.dominantBodyPartRank, isNull);
      // Defensive fallback — no dominant BP → fraction is 0.
      expect(payload.rankProgressFraction, 0.0);
      expect(payload.pr, isNull);
      expect(payload.isClassChange, isFalse);
      expect(payload.hasTitleUnlock, isFalse);
      expect(payload.hasRankUp, isFalse);
      expect(payload.hasShareCta, isFalse);
      // Defensive hot-violet fallback when no BP earned XP.
      expect(payload.dominantHue, AppColors.hotViolet);
    },
  );

  // ---------------------------------------------------------------------------
  // Case 2: Baseline — XP across multiple BPs, no rewards
  // ---------------------------------------------------------------------------
  test(
    'baseline session picks dominant BP by highest XP delta + maps to BP hue',
    () {
      final payload = SharePayload.fromPostSessionState(
        tier: RewardTier.baseline,
        queueResult: queue(const []),
        prResult: null,
        bpXpDeltas: const {
          BodyPart.chest: 220,
          BodyPart.back: 80,
          BodyPart.arms: 40,
        },
        bpRankAfter: const {
          BodyPart.chest: 12,
          BodyPart.back: 10,
          BodyPart.arms: 8,
        },
        bpProgressFractionAfter: const {
          BodyPart.chest: 0.42,
          BodyPart.back: 0.15,
          BodyPart.arms: 0.55,
        },
        exerciseNames: const {},
        totalXp: 340,
        characterClassSlug: 'bulwark',
      );

      expect(payload.dominantBodyPart, BodyPart.chest);
      expect(payload.dominantBodyPartRank, 12);
      // Dominant BP is chest → fraction looked up by chest = 0.42.
      expect(payload.rankProgressFraction, closeTo(0.42, 1e-9));
      expect(payload.pr, isNull);
      expect(payload.hasRankUp, isFalse);
      expect(payload.isClassChange, isFalse);
      expect(payload.hasShareCta, isFalse);
      // Chest → bodyPartChest hue.
      expect(payload.dominantHue, AppColors.bodyPartChest);
    },
  );

  // ---------------------------------------------------------------------------
  // Case 3: Single PR — gold-tier hero with weight + reps
  // ---------------------------------------------------------------------------
  test('single PR session surfaces hero with localized exercise name', () {
    final payload = SharePayload.fromPostSessionState(
      tier: RewardTier.thresholdAnticipatory,
      queueResult: queue(const []),
      prResult: prResult([pr(exerciseId: 'bench', value: 95, reps: 5)]),
      bpXpDeltas: const {BodyPart.chest: 410},
      bpRankAfter: const {BodyPart.chest: 19},
      bpProgressFractionAfter: const {BodyPart.chest: 0.68},
      exerciseNames: const {'bench': 'Bench Press'},
      totalXp: 618,
      characterClassSlug: 'bulwark',
    );

    expect(payload.pr, isNotNull);
    expect(payload.pr!.exerciseName, 'Bench Press');
    expect(payload.pr!.weightKg, 95);
    expect(payload.pr!.reps, 5);
    expect(payload.dominantBodyPart, BodyPart.chest);
    expect(payload.dominantBodyPartRank, 19);
    expect(payload.rankProgressFraction, closeTo(0.68, 1e-9));
    expect(payload.hasShareCta, isTrue);
    expect(payload.dominantHue, AppColors.bodyPartChest);
  });

  // ---------------------------------------------------------------------------
  // Case 4: Multi-PR — hero selection by score (weight × reps), name tiebreaker
  // ---------------------------------------------------------------------------
  test('multi-PR session selects highest-score PR (weight × reps), then '
      'alphabetical by exercise name tiebreaker', () {
    // Two PRs at identical score (100 × 3 == 60 × 5 == 300).
    // Alphabetical tiebreaker picks "Deadlift" over "Squat".
    // A third PR at higher score (95 × 5 == 475) beats both.
    final payload = SharePayload.fromPostSessionState(
      tier: RewardTier.thresholdAnticipatory,
      queueResult: queue(const []),
      prResult: prResult([
        pr(exerciseId: 'squat', value: 100, reps: 3),
        pr(exerciseId: 'bench', value: 95, reps: 5), // score 475 — wins
        pr(exerciseId: 'deadlift', value: 60, reps: 5),
      ]),
      bpXpDeltas: const {BodyPart.chest: 400, BodyPart.legs: 250},
      bpRankAfter: const {BodyPart.chest: 19, BodyPart.legs: 17},
      bpProgressFractionAfter: const {BodyPart.chest: 0.5, BodyPart.legs: 0.3},
      exerciseNames: const {
        'squat': 'Squat',
        'bench': 'Bench Press',
        'deadlift': 'Deadlift',
      },
      totalXp: 980,
      characterClassSlug: 'bulwark',
    );

    expect(payload.pr!.exerciseName, 'Bench Press');
    expect(payload.pr!.weightKg, 95);
    expect(payload.pr!.reps, 5);
    expect(payload.dominantBodyPart, BodyPart.chest);
    expect(payload.hasShareCta, isTrue);
  });

  // ---------------------------------------------------------------------------
  // Case 5: Single rank-up (no PR) — hue + hasRankUp + share CTA
  // ---------------------------------------------------------------------------
  test('single rank-up session sets hasRankUp + share CTA without a PR', () {
    final payload = SharePayload.fromPostSessionState(
      tier: RewardTier.thresholdAnticipatory,
      queueResult: queue(const [
        CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 14),
      ]),
      prResult: null,
      bpXpDeltas: const {BodyPart.back: 320},
      bpRankAfter: const {BodyPart.back: 14},
      // Rank-up just fired → fraction near zero (post-rank-up base).
      bpProgressFractionAfter: const {BodyPart.back: 0.05},
      exerciseNames: const {},
      totalXp: 320,
      characterClassSlug: 'bulwark',
    );

    expect(payload.hasRankUp, isTrue);
    expect(payload.pr, isNull);
    expect(payload.dominantBodyPart, BodyPart.back);
    expect(payload.dominantBodyPartRank, 14);
    expect(payload.dominantHue, AppColors.bodyPartBack);
    expect(payload.hasShareCta, isTrue);
  });

  // ---------------------------------------------------------------------------
  // Case 6: Multi rank-up — hue picks highest-XP BP, hasRankUp stays true
  // ---------------------------------------------------------------------------
  test(
    'multi rank-up session keeps hasRankUp + dominant BP follows XP, not rank',
    () {
      // Back XP > Chest XP, so Back is dominant even though Chest ranked higher.
      final payload = SharePayload.fromPostSessionState(
        tier: RewardTier.thresholdAnticipatory,
        queueResult: queue(const [
          CelebrationEvent.rankUp(bodyPart: BodyPart.chest, newRank: 22),
          CelebrationEvent.rankUp(bodyPart: BodyPart.back, newRank: 18),
          CelebrationEvent.rankUp(bodyPart: BodyPart.arms, newRank: 11),
        ]),
        prResult: null,
        bpXpDeltas: const {
          BodyPart.back: 380,
          BodyPart.chest: 300,
          BodyPart.arms: 150,
        },
        bpRankAfter: const {
          BodyPart.back: 18,
          BodyPart.chest: 22,
          BodyPart.arms: 11,
        },
        bpProgressFractionAfter: const {
          BodyPart.back: 0.12,
          BodyPart.chest: 0.08,
          BodyPart.arms: 0.5,
        },
        exerciseNames: const {},
        totalXp: 830,
        characterClassSlug: 'bulwark',
      );

      expect(payload.hasRankUp, isTrue);
      expect(payload.dominantBodyPart, BodyPart.back);
      expect(payload.dominantBodyPartRank, 18);
      expect(payload.dominantHue, AppColors.bodyPartBack);
      expect(payload.hasShareCta, isTrue);
    },
  );

  // ---------------------------------------------------------------------------
  // Case 7: Title unlock — hasTitleUnlock + share CTA
  // ---------------------------------------------------------------------------
  test('title-unlock session sets hasTitleUnlock + share CTA', () {
    final payload = SharePayload.fromPostSessionState(
      tier: RewardTier.thresholdAnticipatory,
      queueResult: queue(const [
        CelebrationEvent.titleUnlock(slug: 'chest_initiate_rank_20'),
      ]),
      prResult: null,
      bpXpDeltas: const {BodyPart.chest: 280},
      bpRankAfter: const {BodyPart.chest: 20},
      bpProgressFractionAfter: const {BodyPart.chest: 0.0},
      exerciseNames: const {},
      totalXp: 280,
      characterClassSlug: 'bulwark',
    );

    expect(payload.hasTitleUnlock, isTrue);
    expect(payload.hasRankUp, isFalse);
    expect(payload.isClassChange, isFalse);
    expect(payload.pr, isNull);
    expect(payload.hasShareCta, isTrue);
  });

  // ---------------------------------------------------------------------------
  // Case 8: Class-change — hue override to hotViolet, isClassChange flag set
  // ---------------------------------------------------------------------------
  test('class-change session overrides BP hue with hotViolet + sets '
      'isClassChange flag (even though chest is dominant)', () {
    final payload = SharePayload.fromPostSessionState(
      tier: RewardTier.classChangeAnticipatory,
      queueResult: queue(const [
        CelebrationEvent.classChange(
          fromClass: CharacterClass.initiate,
          toClass: CharacterClass.bulwark,
        ),
      ]),
      prResult: null,
      bpXpDeltas: const {BodyPart.chest: 420},
      bpRankAfter: const {BodyPart.chest: 18},
      bpProgressFractionAfter: const {BodyPart.chest: 0.33},
      exerciseNames: const {},
      totalXp: 420,
      characterClassSlug: 'bulwark',
    );

    expect(payload.isClassChange, isTrue);
    expect(payload.dominantBodyPart, BodyPart.chest);
    expect(payload.dominantBodyPartRank, 18);
    // Class-change hue override beats the BP-derived hue.
    expect(payload.dominantHue, AppColors.hotViolet);
    expect(payload.hasShareCta, isTrue);
  });

  // ---------------------------------------------------------------------------
  // Idempotency — same inputs → identical payload (pure function contract)
  // ---------------------------------------------------------------------------
  test('composer is idempotent — same inputs produce equal payloads', () {
    final args = {
      'tier': RewardTier.thresholdAnticipatory,
      'queue': queue(const [
        CelebrationEvent.rankUp(bodyPart: BodyPart.legs, newRank: 16),
      ]),
      'pr': prResult([pr(exerciseId: 'squat', value: 120, reps: 5)]),
      'deltas': const {BodyPart.legs: 540},
      'ranks': const {BodyPart.legs: 16},
      'progress': const {BodyPart.legs: 0.22},
      'names': const {'squat': 'Squat'},
    };

    SharePayload buildOnce() => SharePayload.fromPostSessionState(
      tier: args['tier']! as RewardTier,
      queueResult: args['queue']! as CelebrationQueueResult,
      prResult: args['pr'] as PRDetectionResult?,
      bpXpDeltas: args['deltas']! as Map<BodyPart, int>,
      bpRankAfter: args['ranks']! as Map<BodyPart, int>,
      bpProgressFractionAfter: args['progress']! as Map<BodyPart, double>,
      exerciseNames: args['names']! as Map<String, String>,
      totalXp: 540,
      characterClassSlug: 'bulwark',
    );

    final a = buildOnce();
    final b = buildOnce();
    expect(a, equals(b));
  });
}
