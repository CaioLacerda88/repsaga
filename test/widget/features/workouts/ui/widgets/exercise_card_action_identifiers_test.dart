/// Identifier-reachability + pair-rule tests for the swap and remove
/// IconButtons inside [ExerciseCard]. Family 3 (AW-EX-C-BR1-02): Playwright
/// could only target these via flaky text/coordinate selectors because the
/// AOM had no `flt-semantics-identifier` on either button. Pinning both
/// identifiers — and the `container: true, explicitChildNodes: true`
/// pair-rule per `lessons.md` PR #152 — prevents the silent-merge regression
/// that bit PR #152.
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
import 'package:repsaga/features/workouts/ui/widgets/exercise_card.dart';

import '../../../../../helpers/test_material_app.dart';

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Barbell Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

final _testWorkout = Workout(
  id: 'workout-001',
  userId: 'user-001',
  name: 'Push Day',
  startedAt: DateTime.now().toUtc(),
  isActive: true,
  createdAt: DateTime.now().toUtc(),
);

ExerciseSet _makeSet({required int setNumber}) => ExerciseSet(
  id: 'set-$setNumber',
  workoutExerciseId: 'we-001',
  setNumber: setNumber,
  reps: 10,
  weight: 60.0,
  isCompleted: false,
  setType: SetType.working,
  createdAt: DateTime.now().toUtc(),
);

ActiveWorkoutExercise _makeActiveExercise({int setCount = 2}) {
  return ActiveWorkoutExercise(
    workoutExercise: WorkoutExercise(
      id: 'we-001',
      workoutId: 'workout-001',
      exerciseId: 'exercise-001',
      order: 1,
      exercise: _testExercise,
    ),
    sets: List.generate(setCount, (i) => _makeSet(setNumber: i + 1)),
  );
}

ActiveWorkoutState _makeState(ActiveWorkoutExercise activeExercise) {
  return ActiveWorkoutState(workout: _testWorkout, exercises: [activeExercise]);
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

Widget _buildExerciseCard(ActiveWorkoutExercise activeExercise) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(_makeState(activeExercise)),
      ),
      restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
      exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: ExerciseCard(
            activeExercise: activeExercise,
            reorderMode: false,
            isFirst: true,
            isLast: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ExerciseCard action button identifiers (Family 3)', () {
    testWidgets(
      'swap button is reachable via Semantics identifier "workout-swap-exercise"',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        expect(
          find.bySemanticsIdentifier('workout-swap-exercise'),
          findsOneWidget,
          reason:
              'Family 3 (AW-EX-C-BR1-02): the swap IconButton must expose '
              'a stable Playwright selector via flt-semantics-identifier. '
              'Without it tests fall back to text/coords and break on '
              'every locale or icon swap.',
        );

        handle.dispose();
      },
    );

    testWidgets(
      'remove button is reachable via Semantics identifier "workout-remove-exercise"',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        expect(
          find.bySemanticsIdentifier('workout-remove-exercise'),
          findsOneWidget,
        );

        handle.dispose();
      },
    );

    testWidgets(
      'swap identifier wrapper declares the container/explicitChildNodes pair-rule',
      (tester) async {
        // PR #152 regression risk: a bare Semantics(identifier: ...) without
        // `container: true` AND `explicitChildNodes: true` silently merges
        // its node into ancestor Semantics. The pair is non-negotiable.
        // (`container` and `explicitChildNodes` are widget-level fields on
        // the `Semantics` constructor, not on `SemanticsProperties`.)
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        final semWidgets = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((s) => s.properties.identifier == 'workout-swap-exercise')
            .toList();
        expect(semWidgets, hasLength(1));
        expect(
          semWidgets.first.container,
          isTrue,
          reason:
              'workout-swap-exercise Semantics MUST set container: true. '
              'Without it the identifier node merges silently — see '
              'lessons.md PR #152.',
        );
        expect(
          semWidgets.first.explicitChildNodes,
          isTrue,
          reason:
              'workout-swap-exercise Semantics MUST set '
              'explicitChildNodes: true (pair-rule).',
        );
      },
    );

    testWidgets(
      'remove identifier wrapper declares the container/explicitChildNodes pair-rule',
      (tester) async {
        await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
        await tester.pump();

        final semWidgets = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((s) => s.properties.identifier == 'workout-remove-exercise')
            .toList();
        expect(semWidgets, hasLength(1));
        expect(semWidgets.first.container, isTrue);
        expect(semWidgets.first.explicitChildNodes, isTrue);
      },
    );
  });
}
