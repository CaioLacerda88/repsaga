import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/set_row.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../../fixtures/test_factories.dart';
import '../../../../../helpers/test_material_app.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

/// Creates a minimal [ExerciseSet] using the test factory.
ExerciseSet makeSet({
  String id = 'set-001',
  String workoutExerciseId = 'we-001',
  int setNumber = 1,
  double weight = 60.0,
  int reps = 10,
  SetType setType = SetType.working,
  bool isCompleted = false,
}) {
  return ExerciseSet.fromJson(
    TestSetFactory.create(
      id: id,
      workoutExerciseId: workoutExerciseId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      setType: setType.name,
      isCompleted: isCompleted,
    ),
  );
}

/// Creates a [ProviderContainer] with mocked storage returning [initialState].
ProviderContainer makeContainer(ActiveWorkoutState? initialState) {
  final mockStorage = MockWorkoutLocalStorage();
  when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

  final container = ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
    ],
  );
  return container;
}

Widget buildTestWidget(Widget child, {ProviderContainer? container}) {
  return UncontrolledProviderScope(
    container: container ?? makeContainer(null),
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SizedBox(
          // SetRow has a WeightStepper + RepsStepper side by side inside an
          // Expanded column. 800px gives each stepper enough room to render
          // without overflow warnings in the test harness.
          width: 800,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeActiveWorkoutState());
  });

  group('SetRow', () {
    group('rendering', () {
      testWidgets('displays the set number', (tester) async {
        final set = makeSet(setNumber: 3);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        expect(find.text('3'), findsOneWidget);
      });

      // Phase 20 commit 2 (Direction B): the set-type abbreviation badge
      // ("W"/"WU"/"D"/"F") was removed from the set-number cell. The set
      // type is now communicated by the left rune-stripe color of the
      // [_SetRowFrame] (violet for working/warmup/dropset/failure pending,
      // green for completed). Long-press cycle behavior is preserved and
      // covered by `long-pressing set number cycles set type` below.

      testWidgets('displays "kg" label next to weight', (tester) async {
        final set = makeSet();
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        expect(find.text('kg'), findsOneWidget);
      });

      testWidgets('renders checkbox unchecked when isCompleted is false', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.value, isFalse);
      });

      testWidgets('renders checkbox checked when isCompleted is true', (
        tester,
      ) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.value, isTrue);
      });
    });

    group('interactions', () {
      testWidgets(
        'tapping checkbox toggles isCompleted on the notifier state',
        (tester) async {
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set = workoutState.exercises.first.sets.first;
          final initialCompleted = set.isCompleted;

          final container = makeContainer(workoutState);
          addTearDown(container.dispose);
          // Prime the notifier so it has loaded state.
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: weId),
              container: container,
            ),
          );

          await tester.tap(find.byType(Checkbox));
          await tester.pump();

          final updatedState = container.read(activeWorkoutProvider).value;
          expect(
            updatedState?.exercises.first.sets.first.isCompleted,
            isNot(initialCompleted),
          );
        },
      );

      testWidgets(
        'long-pressing set number cycles set type from working to warmup',
        (tester) async {
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          // The factory creates sets with type 'working'.
          final set = workoutState.exercises.first.sets.first;
          expect(set.setType, SetType.working);

          final container = makeContainer(workoutState);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: weId),
              container: container,
            ),
          );

          // Long-press the set number area to cycle set type.
          await tester.longPress(find.text('${set.setNumber}'));
          await tester.pump();

          final updatedState = container.read(activeWorkoutProvider).value;
          expect(
            updatedState?.exercises.first.sets.first.setType,
            SetType.warmup,
          );
        },
      );

      testWidgets(
        'tapping set number on set#2+ copies weight+reps from the previous set (BUG-018)',
        (tester) async {
          // Pin: onTap is only wired when setNumber > 1. Tapping set#2 must
          // copy the previous set's weight and reps into set#2. This confirms
          // the 48dp tap target is not just sized correctly but is also
          // functionally reachable: the InkWell registers the tap.
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 2,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set1 = workoutState.exercises.first.sets.first;
          final set2 = workoutState.exercises.first.sets[1];
          expect(set2.setNumber, 2, reason: 'sanity check: set2 is set #2');

          // Mutate set1 to have known weight/reps so we can assert the copy.
          final stateWithSet1Values = workoutState.copyWith(
            exercises: [
              workoutState.exercises.first.copyWith(
                sets: [set1.copyWith(weight: 80.0, reps: 8), set2],
              ),
            ],
          );

          final container = makeContainer(stateWithSet1Values);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set2, workoutExerciseId: weId),
              container: container,
            ),
          );

          // Tap the set-number cell on set #2.
          await tester.tap(find.text('${set2.setNumber}'));
          await tester.pump();

          final updatedState = container.read(activeWorkoutProvider).value;
          final updatedSet2 = updatedState?.exercises.first.sets[1];
          expect(
            updatedSet2?.weight,
            80.0,
            reason:
                'BUG-018 tap-to-copy: set#2 weight must be copied from set#1.',
          );
          expect(
            updatedSet2?.reps,
            8,
            reason:
                'BUG-018 tap-to-copy: set#2 reps must be copied from set#1.',
          );
        },
      );
    });

    group('ghost text (previous session hint)', () {
      testWidgets(
        'shows ghost text when lastSet is provided and set is not completed',
        (tester) async {
          final set = makeSet(isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('Previous: 80kg × 8'), findsOneWidget);
        },
      );

      testWidgets('hides ghost text when set is already completed', (
        tester,
      ) async {
        final set = makeSet(isCompleted: true);
        final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

        await tester.pumpWidget(
          buildTestWidget(
            SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
          ),
        );

        expect(find.text('Previous: 80kg × 8'), findsNothing);
      });

      testWidgets('hides ghost text when lastSet is null', (tester) async {
        final set = makeSet(isCompleted: false);

        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        // No hint text should appear when lastSet is null.
        expect(find.textContaining('Previous:'), findsNothing);
        expect(find.textContaining('Last:'), findsNothing);
      });

      testWidgets(
        'ghost text shows integer weight without decimal when weight is whole number',
        (tester) async {
          final set = makeSet(isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 100.0, reps: 5);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          // Whole-number weights should display without a decimal suffix.
          expect(find.text('Previous: 100kg × 5'), findsOneWidget);
        },
      );
    });

    group('isNew checkbox lock', () {
      testWidgets(
        'checkbox is non-interactive within 600ms when isNew is true',
        (tester) async {
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set = workoutState.exercises.first.sets.first;

          final container = makeContainer(workoutState);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: weId, isNew: true),
              container: container,
            ),
          );

          // Tap the checkbox immediately — still within the 600ms lock window.
          await tester.tap(find.byType(Checkbox));
          await tester.pump();

          // isCompleted should NOT have changed because the lock is active.
          final state = container.read(activeWorkoutProvider).value;
          expect(
            state?.exercises.first.sets.first.isCompleted,
            set.isCompleted,
          );
        },
      );

      testWidgets('checkbox becomes interactive after 600ms lock expires', (
        tester,
      ) async {
        final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
          exerciseCount: 1,
          setsPerExercise: 1,
        );
        final workoutState = ActiveWorkoutState.fromJson(stateJson);
        final weId = workoutState.exercises.first.workoutExercise.id;
        final set = workoutState.exercises.first.sets.first;
        final initialCompleted = set.isCompleted;

        final container = makeContainer(workoutState);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        await tester.pumpWidget(
          buildTestWidget(
            SetRow(set: set, workoutExerciseId: weId, isNew: true),
            container: container,
          ),
        );

        // Advance time past the 600ms lock duration.
        await tester.pump(const Duration(milliseconds: 601));

        // Now tap the checkbox — the lock should have expired.
        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        final state = container.read(activeWorkoutProvider).value;
        expect(
          state?.exercises.first.sets.first.isCompleted,
          isNot(initialCompleted),
        );
      });

      testWidgets(
        'checkbox is immediately interactive when isNew is false (default)',
        (tester) async {
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set = workoutState.exercises.first.sets.first;
          final initialCompleted = set.isCompleted;

          final container = makeContainer(workoutState);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              // isNew defaults to false — no lock should apply.
              SetRow(set: set, workoutExerciseId: weId),
              container: container,
            ),
          );

          await tester.tap(find.byType(Checkbox));
          await tester.pump();

          final state = container.read(activeWorkoutProvider).value;
          expect(
            state?.exercises.first.sets.first.isCompleted,
            isNot(initialCompleted),
          );
        },
      );
    });

    group('hint line suppression', () {
      testWidgets('hint line is hidden when set values match lastSet exactly', (
        tester,
      ) async {
        // Current set has the same weight/reps as lastSet — hint is redundant.
        final set = makeSet(weight: 80.0, reps: 8, isCompleted: false);
        final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

        await tester.pumpWidget(
          buildTestWidget(
            SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
          ),
        );

        // Hint should be fully suppressed — neither old nor new label present.
        expect(find.textContaining('Previous:'), findsNothing);
        expect(find.textContaining('Last:'), findsNothing);
      });

      testWidgets(
        'hint line is shown when current weight differs from lastSet',
        (tester) async {
          final set = makeSet(weight: 60.0, reps: 8, isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('Previous: 80kg × 8'), findsOneWidget);
        },
      );

      testWidgets('hint line is shown when current reps differ from lastSet', (
        tester,
      ) async {
        final set = makeSet(weight: 80.0, reps: 10, isCompleted: false);
        final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

        await tester.pumpWidget(
          buildTestWidget(
            SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
          ),
        );

        expect(find.text('Previous: 80kg × 8'), findsOneWidget);
      });

      testWidgets(
        'hint line is shown when both weight and reps differ from lastSet',
        (tester) async {
          final set = makeSet(weight: 60.0, reps: 10, isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('Previous: 80kg × 8'), findsOneWidget);
        },
      );
    });

    group('dismissible race guard', () {
      testWidgets('confirmDismiss returns false when set was already deleted', (
        tester,
      ) async {
        final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
          exerciseCount: 1,
          setsPerExercise: 2,
        );
        final workoutState = ActiveWorkoutState.fromJson(stateJson);
        final weId = workoutState.exercises.first.workoutExercise.id;
        // Use the first set for the widget but delete it from state before
        // the dismiss gesture completes.
        final set = workoutState.exercises.first.sets.first;

        final container = makeContainer(workoutState);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        await tester.pumpWidget(
          buildTestWidget(
            SetRow(set: set, workoutExerciseId: weId),
            container: container,
          ),
        );

        // Delete the set from state (simulating a concurrent swipe).
        container.read(activeWorkoutProvider.notifier).deleteSet(weId, set.id);

        // Attempt to dismiss — the Dismissible's confirmDismiss should
        // check state and return false since the set no longer exists.
        // We verify the Dismissible widget has a confirmDismiss callback.
        final dismissible = tester.widget<Dismissible>(
          find.byType(Dismissible),
        );
        expect(dismissible.confirmDismiss, isNotNull);

        // Invoke the confirmDismiss callback directly.
        final shouldDismiss = await dismissible.confirmDismiss!(
          DismissDirection.endToStart,
        );
        expect(shouldDismiss, isFalse);
      });

      testWidgets(
        'confirmDismiss returns true when set still exists in state',
        (tester) async {
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set = workoutState.exercises.first.sets.first;

          final container = makeContainer(workoutState);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: weId),
              container: container,
            ),
          );

          final dismissible = tester.widget<Dismissible>(
            find.byType(Dismissible),
          );
          final shouldDismiss = await dismissible.confirmDismiss!(
            DismissDirection.endToStart,
          );
          expect(shouldDismiss, isTrue);
        },
      );
    });

    group('tap target sizing', () {
      testWidgets(
        'set-number cell is at least 48x48 dp (BUG-018, Material tap min)',
        (tester) async {
          // Pin: the number cell's BoxConstraints must satisfy Material's 48dp
          // minimum so the tap-to-copy / long-press-to-cycle interaction lands
          // reliably mid-workout. Regressing below 48 would re-open BUG-018.
          final set = makeSet(setNumber: 1);
          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );

          // The number-cell Container is the unique one whose constraints
          // enforce the new tap-target floor. Find by predicate over Container
          // widgets so we don't accidentally match decorative or layout
          // containers in the row.
          final numberCells = tester
              .widgetList<Container>(find.byType(Container))
              .where((c) {
                final bc = c.constraints;
                return bc != null &&
                    bc.minWidth >= 48 &&
                    bc.minHeight >= 48 &&
                    bc.minWidth < 100 &&
                    bc.minHeight < 100;
              })
              .toList();

          expect(
            numberCells,
            isNotEmpty,
            reason:
                'Set-number cell BoxConstraints must be >=48dp on both axes '
                '(Material tap-target minimum). See BUG-018.',
          );
          final cell = numberCells.first;
          expect(cell.constraints!.minWidth, greaterThanOrEqualTo(48));
          expect(cell.constraints!.minHeight, greaterThanOrEqualTo(48));
        },
      );
    });

    group('accessibility semantics', () {
      testWidgets('set number has correct semantics label with type info', (
        tester,
      ) async {
        final set = makeSet(setType: SetType.working);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        expect(
          find.bySemanticsLabel(
            RegExp(r'Set 1.*Long press to change type: Working'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('uncompleted checkbox has "Mark set as done" semantics', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        expect(find.bySemanticsLabel('Mark set as done'), findsOneWidget);
      });

      testWidgets('completed checkbox has "Set completed" semantics', (
        tester,
      ) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );

        expect(find.bySemanticsLabel('Set completed'), findsOneWidget);
      });
    });
  });
}
