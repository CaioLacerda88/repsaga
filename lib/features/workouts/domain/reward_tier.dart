import '../../rpg/domain/celebration_queue.dart';
import '../../rpg/models/celebration_event.dart';
import 'post_session_timing.dart';

/// Discriminates the post-session cinematic's Beat 1 (XP cut) variant.
///
/// Each tier maps to a (copy line, hold duration, optional pre-roll) triple.
/// The derivation is a pure function of the workout-finish snapshot — no
/// Riverpod, no `BuildContext`, no IO — so unit tests pin the contract
/// without any harness setup. Maintenance hypothetical B (change baseline
/// copy alternation from `session % 2` to `weekly_session_count % 2`)
/// touches exactly this file.
///
/// **Path A pivot (2026-05-22).** Every cut on the post-session screen
/// carries first-exposure revelation weight (no mid-workout flash precedes
/// it). The hold durations below are minimum parse times — see
/// [PostSessionTiming] for the exact values + their rationale.
///
/// **Mockup §2 RewardTier.derive note (load-bearing):** the
/// `thresholdAnticipatory` variant fires for BOTH personal-record sessions
/// AND rank-up-only sessions (single OR multi rank-up) — i.e.
/// `hasPR || hasRankUp`. Gating on PR alone would silently drop rank-up-only
/// sessions to baseline copy ("ENCERRADO. MAIS FORTE.") and the rank-up
/// state would lose its narrative tension.
enum RewardTier {
  /// First session ever. Day-zero copy ("COMEÇO. O PIOR JÁ PASSOU."), no
  /// Beat 3, single body part. Mockup §2 Variant Day-Zero + §5 State 1.
  dayZero,

  /// No PR, no rank-up, no title, no class change. Baseline copy alternates
  /// between two variants seeded from the session number. Mockup §2 Variant
  /// Baseline + §5 State 2.
  baseline,

  /// PR-incoming OR rank-up-incoming OR title-incoming session. Copy
  /// ("NOVO LIMITE." / "CONQUISTA DESPERTADA.") primes the reveal without
  /// spoiling it. Mockup §2 Variant Threshold-anticipatory + §5 States 3,
  /// 4, 5, 6, 8.
  thresholdAnticipatory,

  /// Class-change or level-up incoming. Carries 120ms pre-roll + 1.5s hold
  /// + folds the level-up announcement into B1 copy ("NÍVEL 23. A SAGA
  /// CONTINUA."). Mockup §2 Variant Max-combo / Class-change + §5 States
  /// 7, 9, 10.
  classChangeAnticipatory;

  /// Classify a workout finish into a post-session reward tier.
  ///
  /// **Inputs (all snapshot data, no providers):**
  ///   * [queueResult] — the celebration queue from
  ///     `ActiveWorkoutNotifier.consumeLastCelebration()`.
  ///   * [priorFinishedWorkoutCount] — the number of finished workouts
  ///     BEFORE this one. A value of 0 means the just-finished workout is
  ///     the user's first ever.
  ///   * [hasPersonalRecord] — `prResult.hasNewRecords` from the workout
  ///     finish path. PR detection is separate from the celebration queue
  ///     (per Phase 18c spec the queue carries rank-up / level-up / title /
  ///     class-change / first-awakening; PR detection runs alongside).
  ///
  /// **Decision tree (precedence locked, mockup §5):**
  ///   1. `priorFinishedWorkoutCount == 0` → [dayZero]. Day-zero gravity
  ///      beats any reward event — a first-ever session that also earned
  ///      a rank-up still reads as Day-zero (the rank-up itself is
  ///      already implicit in the body-part awakening).
  ///   2. Any class-change OR level-up in [queueResult.queue] →
  ///      [classChangeAnticipatory]. These two events share B1 timing
  ///      because both demand the 120ms pre-roll + 1.5s parse window.
  ///   3. Any rank-up OR title-unlock in [queueResult.queue] OR
  ///      [hasPersonalRecord] → [thresholdAnticipatory]. The
  ///      `hasPR || hasRankUp || hasTitle` invariant comes from mockup §2
  ///      RewardTier.derive note.
  ///   4. Otherwise → [baseline].
  ///
  /// **Idempotency:** same input → same output. Pure function.
  static RewardTier derive({
    required CelebrationQueueResult queueResult,
    required int priorFinishedWorkoutCount,
    required bool hasPersonalRecord,
  }) {
    if (priorFinishedWorkoutCount <= 0) {
      return RewardTier.dayZero;
    }

    final queue = queueResult.queue;
    final hasClassChange = queue.any((e) => e is ClassChangeEvent);
    final hasLevelUp = queue.any((e) => e is LevelUpEvent);
    if (hasClassChange || hasLevelUp) {
      return RewardTier.classChangeAnticipatory;
    }

    final hasRankUp = queue.any((e) => e is RankUpEvent);
    final hasTitle = queue.any((e) => e is TitleUnlockEvent);
    if (hasPersonalRecord || hasRankUp || hasTitle) {
      return RewardTier.thresholdAnticipatory;
    }

    return RewardTier.baseline;
  }

  /// B1 hold duration (parse-time guarantee). See [PostSessionTiming]
  /// for the exact values.
  Duration get b1Hold {
    switch (this) {
      case RewardTier.dayZero:
        return PostSessionTiming.b1HoldDayZero;
      case RewardTier.baseline:
        return PostSessionTiming.b1HoldBaseline;
      case RewardTier.thresholdAnticipatory:
        return PostSessionTiming.b1HoldThresholdAnticipatory;
      case RewardTier.classChangeAnticipatory:
        return PostSessionTiming.b1HoldClassChangeAnticipatory;
    }
  }

  /// Pre-roll dead-black hold before the B1 XP slam lands. Only
  /// [classChangeAnticipatory] carries a non-zero pre-roll (120ms);
  /// every other tier returns [Duration.zero].
  Duration get b1PreRoll {
    switch (this) {
      case RewardTier.classChangeAnticipatory:
        return PostSessionTiming.b1PreRollClassChangeAnticipatory;
      case RewardTier.dayZero:
      case RewardTier.baseline:
      case RewardTier.thresholdAnticipatory:
        return Duration.zero;
    }
  }

  /// Pick the baseline B1 copy variant.
  ///
  /// Only meaningful when `this == RewardTier.baseline`. Returns
  /// [BaselineCopyVariant.a] on even session numbers, [BaselineCopyVariant.b]
  /// on odd. Maintenance hypothetical B (change the alternation seed
  /// from `session % 2` to `weekly_session_count % 2`) touches THIS line.
  ///
  /// **Defensive return for non-baseline tiers:** other tiers carry their
  /// own copy keys and never call this helper in production; the defensive
  /// fixed-to-`a` return prevents accidental alternation if a future caller
  /// invokes this on the wrong tier.
  BaselineCopyVariant baselineCopyVariant({
    required int priorFinishedWorkoutCount,
  }) {
    if (this != RewardTier.baseline) return BaselineCopyVariant.a;
    return priorFinishedWorkoutCount.isEven
        ? BaselineCopyVariant.a
        : BaselineCopyVariant.b;
  }
}

/// Two-variant alternation for [RewardTier.baseline] B1 copy.
///
/// `a` = "ENCERRADO. MAIS FORTE." (mockup §2 Variant Baseline default).
/// `b` = "CONSISTÊNCIA VENCE." (mockup §5 State 2 alternate).
///
/// Localized strings resolve at the screen layer via two distinct ARB keys
/// (`b1CopyBaselineA` / `b1CopyBaselineB`) per
/// `feedback_widget_l10n_parameterization`.
enum BaselineCopyVariant { a, b }
