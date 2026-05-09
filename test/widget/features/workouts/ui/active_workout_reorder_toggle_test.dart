/// Identifier-reachability + pair-rule test for the reorder-toggle button
/// in the active-workout AppBar. Family 3 (AW-EX-C-BR1-01): the button was
/// previously addressable only via tooltip-text matching, which broke
/// across locales and icon swaps. This test pins the new
/// `workout-reorder-toggle` identifier and the `container: true,
/// explicitChildNodes: true` pair-rule (lessons.md PR #152).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/active_workout_screen.dart';

import '../../../../helpers/test_material_app.dart';

final _testWorkout = Workout(
  id: 'workout-001',
  userId: 'user-001',
  name: 'Push Day',
  startedAt: DateTime.now().toUtc(),
  isActive: true,
  createdAt: DateTime.now().toUtc(),
);

Exercise _exercise(String id, String name) => Exercise(
  id: id,
  name: name,
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

ActiveWorkoutExercise _activeEx(String suffix, {required int order}) {
  return ActiveWorkoutExercise(
    workoutExercise: WorkoutExercise(
      id: 'we-$suffix',
      workoutId: 'workout-001',
      exerciseId: 'exercise-$suffix',
      order: order,
      exercise: _exercise('exercise-$suffix', 'Exercise $suffix'),
    ),
    sets: [
      ExerciseSet(
        id: 'set-$suffix',
        workoutExerciseId: 'we-$suffix',
        setNumber: 1,
        reps: 10,
        weight: 60.0,
        isCompleted: false,
        setType: SetType.working,
        createdAt: DateTime.now().toUtc(),
      ),
    ],
  );
}

ActiveWorkoutState _stateWithMultipleExercises() {
  return ActiveWorkoutState(
    workout: _testWorkout,
    exercises: [_activeEx('a', order: 0), _activeEx('b', order: 1)],
  );
}

class _FixedActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _FixedActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  @override
  RestTimerState? build() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KgProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'u1', weightUnit: 'kg');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildScreen(ActiveWorkoutState state) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(state),
      ),
      restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
      exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const ActiveWorkoutScreen(),
    ),
  );
}

void main() {
  group('ActiveWorkoutScreen reorder toggle a11y (Family 3)', () {
    testWidgets(
      'reorder toggle exposes "workout-reorder-toggle" Semantics identifier when 2+ exercises present',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_buildScreen(_stateWithMultipleExercises()));
        await tester.pump(); // drain async build
        await tester.pump();

        expect(
          find.bySemanticsIdentifier('workout-reorder-toggle'),
          findsOneWidget,
          reason:
              'Family 3 (AW-EX-C-BR1-01): the reorder-toggle button must '
              'expose a stable Playwright selector via '
              'flt-semantics-identifier. Tooltip-text fallbacks break on '
              'every locale change.',
        );

        handle.dispose();
      },
    );

    testWidgets(
      'reorder toggle Semantics declares the container/explicitChildNodes pair-rule',
      (tester) async {
        await tester.pumpWidget(_buildScreen(_stateWithMultipleExercises()));
        await tester.pump();
        await tester.pump();

        final semWidgets = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((s) => s.properties.identifier == 'workout-reorder-toggle')
            .toList();
        expect(semWidgets, hasLength(1));
        expect(
          semWidgets.first.container,
          isTrue,
          reason:
              'workout-reorder-toggle Semantics MUST set container: true '
              '(pair-rule per lessons.md PR #152).',
        );
        expect(
          semWidgets.first.explicitChildNodes,
          isTrue,
          reason:
              'workout-reorder-toggle Semantics MUST set '
              'explicitChildNodes: true.',
        );
      },
    );
  });
}
