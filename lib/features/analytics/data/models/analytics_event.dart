// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'analytics_event.freezed.dart';

/// Typed product analytics events. Fixed set — new events require adding
/// a factory here and a case in the `name` + `props` getters.
///
/// Prop keys are serialized to snake_case to match the `analytics_events`
/// table's `props jsonb` column convention.
@freezed
sealed class AnalyticsEvent with _$AnalyticsEvent {
  const AnalyticsEvent._();

  const factory AnalyticsEvent.onboardingCompleted({
    required String fitnessLevel,
    required int trainingFrequency,
  }) = _OnboardingCompleted;

  // NOTE: `had_active_workout_conflict` was intentionally removed in PR 5
  // review item 6. The app does not currently detect conflicts (both call
  // sites shipped `false` unconditionally), and shipping a permanently-
  // false column corrupts funnel analysis. Re-add the flag in a future
  // PR when the conflict-detection code path exists to populate it.
  //
  // GDPR note: this factory writes `routine_id` into the `props` jsonb
  // column alongside the row's `user_id` foreign key. A routine UUID is
  // not PII in isolation but it links a user to one of their routines
  // inside `analytics_events`. Erasure is handled by the existing FK
  // CASCADE on `auth.users` → `analytics_events.user_id`: the row
  // disappears along with its props payload, so no separate purge on
  // `props->>'routine_id'` is required. The same applies to the
  // `addToPlanPromptResponded` factory below.
  const factory AnalyticsEvent.workoutStarted({
    required String source,
    required String? routineId,
    required int exerciseCount,
  }) = _WorkoutStarted;

  const factory AnalyticsEvent.workoutDiscarded({
    required int elapsedSeconds,
    required int completedSets,
    required int exerciseCount,
    required String source,
  }) = _WorkoutDiscarded;

  const factory AnalyticsEvent.workoutFinished({
    required int durationSeconds,
    required int exerciseCount,
    required int totalSets,
    required int completedSets,
    required int incompleteSetsSkipped,
    required bool hadPr,
    required String source,
    required int workoutNumber,
  }) = _WorkoutFinished;

  const factory AnalyticsEvent.weekPlanSaved({
    required int routineCount,
    required bool atSoftCap,
    required bool usedAutofill,
    required bool replacedExisting,
  }) = _WeekPlanSaved;

  const factory AnalyticsEvent.weekComplete({
    required int sessionsCompleted,
    required int prCountThisWeek,
    required int planSize,
    required int weekNumber,
  }) = _WeekComplete;

  const factory AnalyticsEvent.addToPlanPromptResponded({
    required String action,
    required String trigger,
    required String routineId,
  }) = _AddToPlanPromptResponded;

  const factory AnalyticsEvent.workoutSyncQueued({required String actionType}) =
      _WorkoutSyncQueued;

  const factory AnalyticsEvent.workoutSyncSucceeded({
    required String actionType,
    required int retryCount,
    required int elapsedSecondsInQueue,
  }) = _WorkoutSyncSucceeded;

  const factory AnalyticsEvent.workoutSyncFailed({
    required String actionType,
    required int retryCount,
    required String errorClass,
    required int elapsedSecondsInQueue,
  }) = _WorkoutSyncFailed;

  // ─── Phase 32 PR 32d — RPG + share + churn events ──────────────────────
  //
  // Five new product-analytics events that round out the launch-phase
  // funnel. Paywall events (`paywall_shown`, `paywall_converted`,
  // `trial_started`) are explicitly deferred to Launch Phase 16b — they
  // ship with the paywall screen itself.
  //
  // No migration needed: `analytics_events.name` is free-form text and
  // `analytics_events.props` is jsonb (see migration 00015). New events
  // are surfaced by adding the factory + name/props cases here — no enum
  // alteration required.

  /// Fires once per (user, body_part) on the user's first ever rank-up for
  /// that body part. Idempotency is enforced by a Hive cache at the emit
  /// site (`firstRankUpEmittedBPs:<user_id>`); see
  /// `FinishWorkoutCoordinator.finish` for the cache check.
  const factory AnalyticsEvent.firstRankUp({
    required String bodyPart,
    required int newRank,
  }) = _FirstRankUp;

  /// Fires when the post-session screen mounts and the 3-beat cinematic
  /// begins. Guarded by `_analyticsFired` on the screen so Riverpod
  /// rebuilds can't double-fire.
  const factory AnalyticsEvent.postSessionCinematicShown({
    required int totalXp,
    required bool hadRankUp,
    required bool hadTitleUnlock,
    required bool hadClassChange,
  }) = _PostSessionCinematicShown;

  /// Fires on successful native share-sheet completion (not on dismissed
  /// or unavailable). [variant] is `discreet` when no photo is attached,
  /// `with_photo` otherwise — A vs B distinction is deferred until the
  /// signal proves load-bearing.
  const factory AnalyticsEvent.shareCardExported({
    required String variant,
    required bool hadCustomPhoto,
  }) = _ShareCardExported;

  /// Fires per unlocked title surfaced in the post-session pipeline. One
  /// emit per `TitleUnlockEvent` in the celebration queue — multiple
  /// titles in one session produce multiple events.
  const factory AnalyticsEvent.titleUnlocked({
    required String titleSlug,
    required int workoutNumber,
  }) = _TitleUnlocked;

  /// Fires when the user taps "Finish" with zero completed sets and the
  /// empty-session guard sheet is shown. Distinct from `workout_discarded`
  /// because the user has not yet made a discard/continue choice — this
  /// event captures the churn signal (intent to finish blocked by guard).
  const factory AnalyticsEvent.sessionZeroXp({
    required int exerciseCount,
    required int elapsedSeconds,
  }) = _SessionZeroXp;

  // NOTE: the `account_deleted` event is intentionally NOT in this sealed
  // class. It's written from inside the `delete-user` Edge Function to a
  // separate no-FK table (`account_deletion_events`) so the row survives
  // the CASCADE delete on `auth.users`. See that function for details.

  /// Event name as stored in the `name` column of `analytics_events`.
  String get name => switch (this) {
    _OnboardingCompleted() => 'onboarding_completed',
    _WorkoutStarted() => 'workout_started',
    _WorkoutDiscarded() => 'workout_discarded',
    _WorkoutFinished() => 'workout_finished',
    _WeekPlanSaved() => 'week_plan_saved',
    _WeekComplete() => 'week_complete',
    _AddToPlanPromptResponded() => 'add_to_plan_prompt_responded',
    _WorkoutSyncQueued() => 'workout_sync_queued',
    _WorkoutSyncSucceeded() => 'workout_sync_succeeded',
    _WorkoutSyncFailed() => 'workout_sync_failed',
    _FirstRankUp() => 'first_rank_up',
    _PostSessionCinematicShown() => 'post_session_cinematic_shown',
    _ShareCardExported() => 'share_card_exported',
    _TitleUnlocked() => 'title_unlocked',
    _SessionZeroXp() => 'session_zero_xp',
  };

  /// Props as stored in the `props` jsonb column. Keys are snake_case.
  /// Values are primitive JSON types only (String, int, double, bool, List).
  Map<String, Object?> get props => switch (this) {
    _OnboardingCompleted(:final fitnessLevel, :final trainingFrequency) => {
      'fitness_level': fitnessLevel,
      'training_frequency': trainingFrequency,
    },
    _WorkoutStarted(:final source, :final routineId, :final exerciseCount) => {
      'source': source,
      'routine_id': routineId,
      'exercise_count': exerciseCount,
    },
    _WorkoutDiscarded(
      :final elapsedSeconds,
      :final completedSets,
      :final exerciseCount,
      :final source,
    ) =>
      {
        'elapsed_seconds': elapsedSeconds,
        'completed_sets': completedSets,
        'exercise_count': exerciseCount,
        'source': source,
      },
    _WorkoutFinished(
      :final durationSeconds,
      :final exerciseCount,
      :final totalSets,
      :final completedSets,
      :final incompleteSetsSkipped,
      :final hadPr,
      :final source,
      :final workoutNumber,
    ) =>
      {
        'duration_seconds': durationSeconds,
        'exercise_count': exerciseCount,
        'total_sets': totalSets,
        'completed_sets': completedSets,
        'incomplete_sets_skipped': incompleteSetsSkipped,
        'had_pr': hadPr,
        'source': source,
        'workout_number': workoutNumber,
      },
    _WeekPlanSaved(
      :final routineCount,
      :final atSoftCap,
      :final usedAutofill,
      :final replacedExisting,
    ) =>
      {
        'routine_count': routineCount,
        'at_soft_cap': atSoftCap,
        'used_autofill': usedAutofill,
        'replaced_existing': replacedExisting,
      },
    _WeekComplete(
      :final sessionsCompleted,
      :final prCountThisWeek,
      :final planSize,
      :final weekNumber,
    ) =>
      {
        'sessions_completed': sessionsCompleted,
        'pr_count_this_week': prCountThisWeek,
        'plan_size': planSize,
        'week_number': weekNumber,
      },
    _AddToPlanPromptResponded(
      :final action,
      :final trigger,
      :final routineId,
    ) =>
      {'action': action, 'trigger': trigger, 'routine_id': routineId},
    _WorkoutSyncQueued(:final actionType) => {'action_type': actionType},
    _WorkoutSyncSucceeded(
      :final actionType,
      :final retryCount,
      :final elapsedSecondsInQueue,
    ) =>
      {
        'action_type': actionType,
        'retry_count': retryCount,
        'elapsed_seconds_in_queue': elapsedSecondsInQueue,
      },
    _WorkoutSyncFailed(
      :final actionType,
      :final retryCount,
      :final errorClass,
      :final elapsedSecondsInQueue,
    ) =>
      {
        'action_type': actionType,
        'retry_count': retryCount,
        'error_class': errorClass,
        'elapsed_seconds_in_queue': elapsedSecondsInQueue,
      },
    _FirstRankUp(:final bodyPart, :final newRank) => {
      'body_part': bodyPart,
      'new_rank': newRank,
    },
    _PostSessionCinematicShown(
      :final totalXp,
      :final hadRankUp,
      :final hadTitleUnlock,
      :final hadClassChange,
    ) =>
      {
        'total_xp': totalXp,
        'had_rank_up': hadRankUp,
        'had_title_unlock': hadTitleUnlock,
        'had_class_change': hadClassChange,
      },
    _ShareCardExported(:final variant, :final hadCustomPhoto) => {
      'variant': variant,
      'had_custom_photo': hadCustomPhoto,
    },
    _TitleUnlocked(:final titleSlug, :final workoutNumber) => {
      'title_slug': titleSlug,
      'workout_number': workoutNumber,
    },
    _SessionZeroXp(:final exerciseCount, :final elapsedSeconds) => {
      'exercise_count': exerciseCount,
      'elapsed_seconds': elapsedSeconds,
    },
  };
}
