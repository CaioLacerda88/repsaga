/// Fill Remaining button visibility + label (Option C — First-Complete
/// Trigger).
///
/// The button must be:
/// - HIDDEN when ALL sets are incomplete (nothing to fill from).
/// - HIDDEN when ALL sets are complete (nothing left to fill).
/// - VISIBLE whenever at least one set is completed AND at least one is
///   incomplete — regardless of which set was completed (including the
///   out-of-order "only the last set is done" case that was broken before).
/// - Labeled "Fill remaining (N sets)" where N = the number of incomplete sets.
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

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Bench Press',
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

ExerciseSet _makeSet({
  required int setNumber,
  required bool isCompleted,
  double weight = 60.0,
  int reps = 10,
}) {
  return ExerciseSet(
    id: 'set-$setNumber',
    workoutExerciseId: 'we-001',
    setNumber: setNumber,
    reps: reps,
    weight: weight,
    isCompleted: isCompleted,
    setType: SetType.working,
    createdAt: DateTime.now().toUtc(),
  );
}

ActiveWorkoutState _makeState(List<ExerciseSet> sets) {
  return ActiveWorkoutState(
    workout: _testWorkout,
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-001',
          workoutId: 'workout-001',
          exerciseId: 'exercise-001',
          order: 1,
          exercise: _testExercise,
        ),
        sets: sets,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildWithSets(List<ExerciseSet> sets) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(_makeState(sets)),
      ),
      restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
      exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
      elapsedTimerProvider.overrideWith(
        (ref, startedAt) => Stream.value(const Duration(minutes: 5)),
      ),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const ActiveWorkoutScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Matches the parameterized label "Fill remaining (N set[s])" without pinning
// the exact count, so visibility tests stay decoupled from count assertions.
final _fillRemainingButton = find.textContaining('Fill remaining');

void main() {
  group('Fill remaining button visibility', () {
    testWidgets(
      'button is HIDDEN when no sets are completed (nothing to fill from)',
      (tester) async {
        final sets = [
          _makeSet(setNumber: 1, isCompleted: false),
          _makeSet(setNumber: 2, isCompleted: false),
          _makeSet(setNumber: 3, isCompleted: false),
        ];

        await tester.pumpWidget(_buildWithSets(sets));
        await tester.pump();
        await tester.pump();

        expect(_fillRemainingButton, findsNothing);
      },
    );

    testWidgets(
      'button is HIDDEN when all sets are completed (nothing left to fill)',
      (tester) async {
        final sets = [
          _makeSet(setNumber: 1, isCompleted: true),
          _makeSet(setNumber: 2, isCompleted: true),
          _makeSet(setNumber: 3, isCompleted: true),
        ];

        await tester.pumpWidget(_buildWithSets(sets));
        await tester.pump();
        await tester.pump();

        expect(_fillRemainingButton, findsNothing);
      },
    );

    testWidgets(
      'button is VISIBLE when only the LAST set is completed (out-of-order — '
      'the case that was broken before Option C)',
      (tester) async {
        // sets 1, 2 incomplete; set 3 (the last) is the only completed set.
        // The old directional check hid the button here; Option C surfaces it.
        final sets = [
          _makeSet(setNumber: 1, isCompleted: false),
          _makeSet(setNumber: 2, isCompleted: false),
          _makeSet(setNumber: 3, isCompleted: true),
        ];

        await tester.pumpWidget(_buildWithSets(sets));
        await tester.pump();
        await tester.pump();

        expect(_fillRemainingButton, findsOneWidget);
      },
    );

    testWidgets(
      'button is VISIBLE when the first set is completed and later sets are not',
      (tester) async {
        final sets = [
          _makeSet(setNumber: 1, isCompleted: true),
          _makeSet(setNumber: 2, isCompleted: false),
          _makeSet(setNumber: 3, isCompleted: false),
        ];

        await tester.pumpWidget(_buildWithSets(sets));
        await tester.pump();
        await tester.pump();

        expect(_fillRemainingButton, findsOneWidget);
      },
    );

    testWidgets(
      'button is VISIBLE when a MIDDLE set is completed (both sides pending)',
      (tester) async {
        final sets = [
          _makeSet(setNumber: 1, isCompleted: false),
          _makeSet(setNumber: 2, isCompleted: true),
          _makeSet(setNumber: 3, isCompleted: false),
        ];

        await tester.pumpWidget(_buildWithSets(sets));
        await tester.pump();
        await tester.pump();

        expect(_fillRemainingButton, findsOneWidget);
      },
    );

    testWidgets(
      'button is HIDDEN when only one completed set exists and no others',
      (tester) async {
        // A single completed set — nothing left to fill.
        final sets = [_makeSet(setNumber: 1, isCompleted: true)];

        await tester.pumpWidget(_buildWithSets(sets));
        await tester.pump();
        await tester.pump();

        expect(_fillRemainingButton, findsNothing);
      },
    );
  });

  group('Fill remaining button label count', () {
    testWidgets('label shows plural count when 2 sets are incomplete', (
      tester,
    ) async {
      // 1 done, 2 pending → "Fill remaining (2 sets)".
      final sets = [
        _makeSet(setNumber: 1, isCompleted: true),
        _makeSet(setNumber: 2, isCompleted: false),
        _makeSet(setNumber: 3, isCompleted: false),
      ];

      await tester.pumpWidget(_buildWithSets(sets));
      await tester.pump();
      await tester.pump();

      expect(find.text('Fill remaining (2 sets)'), findsOneWidget);
    });

    testWidgets('label shows singular count when 1 set is incomplete', (
      tester,
    ) async {
      // 1 done, 1 pending → "Fill remaining (1 set)".
      final sets = [
        _makeSet(setNumber: 1, isCompleted: true),
        _makeSet(setNumber: 2, isCompleted: false),
      ];

      await tester.pumpWidget(_buildWithSets(sets));
      await tester.pump();
      await tester.pump();

      expect(find.text('Fill remaining (1 set)'), findsOneWidget);
    });
  });
}
