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
  });
}
