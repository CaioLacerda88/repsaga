import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';

void main() {
  group('AnalyticsEvent.name', () {
    test('onboardingCompleted → "onboarding_completed"', () {
      const event = AnalyticsEvent.onboardingCompleted(
        fitnessLevel: 'beginner',
        trainingFrequency: 3,
      );
      expect(event.name, 'onboarding_completed');
    });

    test('workoutStarted → "workout_started"', () {
      const event = AnalyticsEvent.workoutStarted(
        source: 'empty',
        routineId: null,
        exerciseCount: 0,
      );
      expect(event.name, 'workout_started');
    });

    test('workoutDiscarded → "workout_discarded"', () {
      const event = AnalyticsEvent.workoutDiscarded(
        elapsedSeconds: 120,
        completedSets: 2,
        exerciseCount: 3,
        source: 'routine_card',
      );
      expect(event.name, 'workout_discarded');
    });

    test('workoutFinished → "workout_finished"', () {
      const event = AnalyticsEvent.workoutFinished(
        durationSeconds: 3420,
        exerciseCount: 6,
        totalSets: 24,
        completedSets: 22,
        incompleteSetsSkipped: 2,
        hadPr: true,
        source: 'planned_bucket',
        workoutNumber: 5,
      );
      expect(event.name, 'workout_finished');
    });

    test('weekPlanSaved → "week_plan_saved"', () {
      const event = AnalyticsEvent.weekPlanSaved(
        routineCount: 4,
        atSoftCap: true,
        usedAutofill: false,
        replacedExisting: false,
      );
      expect(event.name, 'week_plan_saved');
    });

    test('weekComplete → "week_complete"', () {
      const event = AnalyticsEvent.weekComplete(
        sessionsCompleted: 4,
        prCountThisWeek: 1,
        planSize: 4,
        weekNumber: 3,
      );
      expect(event.name, 'week_complete');
    });

    test('addToPlanPromptResponded → "add_to_plan_prompt_responded"', () {
      const event = AnalyticsEvent.addToPlanPromptResponded(
        action: 'added',
        trigger: 'pr_celebration_continue',
        routineId: '00000000-0000-0000-0000-000000000000',
      );
      expect(event.name, 'add_to_plan_prompt_responded');
    });

    // ── Phase 32 PR 32d — RPG + share + churn events ──
    test('firstRankUp → "first_rank_up"', () {
      const event = AnalyticsEvent.firstRankUp(bodyPart: 'chest', newRank: 2);
      expect(event.name, 'first_rank_up');
    });

    test('postSessionCinematicShown → "post_session_cinematic_shown"', () {
      const event = AnalyticsEvent.postSessionCinematicShown(
        totalXp: 340,
        hadRankUp: true,
        hadTitleUnlock: false,
        hadClassChange: false,
      );
      expect(event.name, 'post_session_cinematic_shown');
    });

    test('shareCardExported → "share_card_exported"', () {
      const event = AnalyticsEvent.shareCardExported(
        variant: 'discreet',
        hadCustomPhoto: false,
      );
      expect(event.name, 'share_card_exported');
    });

    test('titleUnlocked → "title_unlocked"', () {
      const event = AnalyticsEvent.titleUnlocked(
        titleSlug: 'iron_sentinel',
        workoutNumber: 7,
      );
      expect(event.name, 'title_unlocked');
    });

    test('sessionZeroXp → "session_zero_xp"', () {
      const event = AnalyticsEvent.sessionZeroXp(
        exerciseCount: 3,
        elapsedSeconds: 42,
      );
      expect(event.name, 'session_zero_xp');
    });
  });

  group('AnalyticsEvent.props', () {
    test('onboardingCompleted produces snake_case prop keys', () {
      const event = AnalyticsEvent.onboardingCompleted(
        fitnessLevel: 'intermediate',
        trainingFrequency: 4,
      );
      expect(event.props, {
        'fitness_level': 'intermediate',
        'training_frequency': 4,
      });
    });

    test('workoutStarted omits null routine_id when source is empty', () {
      const event = AnalyticsEvent.workoutStarted(
        source: 'empty',
        routineId: null,
        exerciseCount: 0,
      );
      expect(event.props['routine_id'], null);
      expect(event.props['source'], 'empty');
      expect(event.props['exercise_count'], 0);
      // had_active_workout_conflict was intentionally removed in PR 5
      // review item 6 — app does not yet detect conflicts.
      expect(event.props.containsKey('had_active_workout_conflict'), false);
    });

    test('workoutFinished includes all props in snake_case', () {
      const event = AnalyticsEvent.workoutFinished(
        durationSeconds: 3420,
        exerciseCount: 6,
        totalSets: 24,
        completedSets: 22,
        incompleteSetsSkipped: 2,
        hadPr: true,
        source: 'planned_bucket',
        workoutNumber: 5,
      );
      expect(event.props, {
        'duration_seconds': 3420,
        'exercise_count': 6,
        'total_sets': 24,
        'completed_sets': 22,
        'incomplete_sets_skipped': 2,
        'had_pr': true,
        'source': 'planned_bucket',
        'workout_number': 5,
      });
    });

    // ── Phase 32 PR 32d — RPG + share + churn events ──
    test('firstRankUp produces snake_case prop keys', () {
      const event = AnalyticsEvent.firstRankUp(bodyPart: 'chest', newRank: 2);
      expect(event.props, {'body_part': 'chest', 'new_rank': 2});
    });

    test('postSessionCinematicShown carries all four flags', () {
      const event = AnalyticsEvent.postSessionCinematicShown(
        totalXp: 340,
        hadRankUp: true,
        hadTitleUnlock: false,
        hadClassChange: true,
      );
      expect(event.props, {
        'total_xp': 340,
        'had_rank_up': true,
        'had_title_unlock': false,
        'had_class_change': true,
      });
    });

    test(
      'shareCardExported reflects with_photo variant + had_custom_photo',
      () {
        const event = AnalyticsEvent.shareCardExported(
          variant: 'with_photo',
          hadCustomPhoto: true,
        );
        expect(event.props, {
          'variant': 'with_photo',
          'had_custom_photo': true,
        });
      },
    );

    test('titleUnlocked produces snake_case prop keys', () {
      const event = AnalyticsEvent.titleUnlocked(
        titleSlug: 'iron_sentinel',
        workoutNumber: 7,
      );
      expect(event.props, {'title_slug': 'iron_sentinel', 'workout_number': 7});
    });

    test('sessionZeroXp produces snake_case prop keys', () {
      const event = AnalyticsEvent.sessionZeroXp(
        exerciseCount: 3,
        elapsedSeconds: 42,
      );
      expect(event.props, {'exercise_count': 3, 'elapsed_seconds': 42});
    });
  });
}
