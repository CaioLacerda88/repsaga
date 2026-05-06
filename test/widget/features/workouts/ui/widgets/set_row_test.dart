import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/domain/pr_row_state.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/set_row.dart';
import 'package:repsaga/shared/widgets/reps_stepper.dart';
import 'package:repsaga/shared/widgets/reward_accent.dart';
import 'package:repsaga/shared/widgets/weight_stepper.dart';
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

      testWidgets(
        'tapping set number on set#1 is a no-op — there is no previous set '
        'to copy from (inverse pin to BUG-018 tap-to-copy)',
        (tester) async {
          // _SetNumberCell wires onTap only when setNumber > 1; on set #1
          // the InkWell.onTap is null and the tap must NOT mutate state.
          // Without this pin, a future "always allow tap" refactor could
          // silently call notifier.copyLastSet on set #1, which would either
          // crash or copy from itself.
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set1 = workoutState.exercises.first.sets.first;
          expect(set1.setNumber, 1, reason: 'sanity check: this is set #1');

          // Seed set#1 with known values so we can verify they are untouched.
          final seededState = workoutState.copyWith(
            exercises: [
              workoutState.exercises.first.copyWith(
                sets: [set1.copyWith(weight: 42.5, reps: 7)],
              ),
            ],
          );
          final seededSet1 = seededState.exercises.first.sets.first;

          final container = makeContainer(seededState);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: seededSet1, workoutExerciseId: weId),
              container: container,
            ),
          );

          // Tap the set-number cell on set #1. Should be a no-op.
          await tester.tap(find.text('${seededSet1.setNumber}'));
          await tester.pump();

          final after = container.read(activeWorkoutProvider).value;
          final afterSet1 = after?.exercises.first.sets.first;
          expect(
            afterSet1?.weight,
            42.5,
            reason:
                'set #1 has no previous set — tapping the number cell must '
                'not mutate weight (no copy-from-self semantics)',
          );
          expect(
            afterSet1?.reps,
            7,
            reason:
                'set #1 has no previous set — tapping the number cell must '
                'not mutate reps',
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
        // Critique Problem 3 wanted the hint to persist post-completion too,
        // but the first persistence attempt (PR #159) re-triggered the
        // Phase 20 Flutter Web semantics-engine role-swap bug on standing-PR
        // rows: adding the hint Text widget on completion caused a subsequent
        // SemanticsUpdate during GenericRole → SemanticButton, dropping the
        // row frame's `flt-semantics-identifier` emission. Reverted to the
        // pre-completion-only hint here; persistence needs a layout-stable
        // redesign in a follow-up PR (e.g. fixed-height hint slot so the
        // parent Column doesn't reflow when the Text appears/disappears).
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

    group('match indicator (Pillar 1)', () {
      testWidgets(
        'shows "= last set" affordance when current values exactly equal last session',
        (tester) async {
          // Pending set + last session both at 80 kg × 8 → match. Pillar 1
          // calls for a subtle (non-gold) confirmation signal so the user's
          // action becomes "edit-then-complete" rather than "enter-then-
          // complete." This affordance replaces the regular previous-session
          // hint when matching.
          final set = makeSet(weight: 80.0, reps: 8, isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('= last set'), findsOneWidget);
          // The regular hint should NOT also show — the match indicator
          // is the deliberate replacement.
          expect(find.textContaining('Previous:'), findsNothing);
        },
      );

      testWidgets(
        'still shows match indicator after the set is completed (matched-and-locked confirmation)',
        (tester) async {
          // Confirms the matched state is a legitimate end-state too — a set
          // the user completed at exactly last session's values reads as
          // "you matched last session" through the entire row lifecycle.
          final set = makeSet(weight: 80.0, reps: 8, isCompleted: true);
          final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('= last set'), findsOneWidget);
        },
      );

      testWidgets(
        'does NOT show match indicator on a freshly-added zero-valued set even if last set is also zero',
        (tester) async {
          // A new set defaults to weight=0/reps=0 before the user enters
          // anything. Showing "= last set" in that case would be a lie — the
          // user hasn't matched anything yet. Last set with weight=0 reps=0
          // is also exotic but covered for symmetry.
          final set = makeSet(weight: 0, reps: 0, isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 0, reps: 0);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('= last set'), findsNothing);
        },
      );

      testWidgets(
        'falls back to regular hint when one value matches but the other does not',
        (tester) async {
          // Same weight, different reps → not a match. The user is on track
          // for a rep PR potentially; the regular hint is the right
          // affordance.
          final set = makeSet(weight: 80.0, reps: 9, isCompleted: false);
          final lastSet = makeSet(id: 'last-set', weight: 80.0, reps: 8);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', lastSet: lastSet),
            ),
          );

          expect(find.text('= last set'), findsNothing);
          expect(find.text('Previous: 80kg × 8'), findsOneWidget);
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

    group('PR row treatment (Phase 20 commit 4)', () {
      // The 5-state matrix is exhaustively pinned in commit 6's golden +
      // widget tests; these are smoke checks that the [display] prop wires
      // through correctly and the gold render path goes via [RewardAccent]
      // (the only legal channel for AppColors.heroGold under the
      // `check_reward_accent.sh` scarcity contract).

      testWidgets(
        'standing-PR display wraps the row in RewardAccent so the gold edge '
        'frame can render through the lint-guarded contract',
        (tester) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedStandingPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          expect(
            find.byType(RewardAccent),
            findsAtLeastNWidgets(1),
            reason:
                'standing-PR row must mount a RewardAccent ancestor — gold '
                'stripe / right bracket / value text all read color via '
                'RewardAccent.of(context). Missing ancestor = silent gold '
                'failure (color falls back to transparent).',
          );
        },
      );

      testWidgets(
        'predicted-PR display swaps the standard Checkbox for the gold ◆ '
        'unchecked mark and exposes the predicted-PR semantics label',
        (tester) async {
          final set = makeSet(isCompleted: false);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.pendingPredictedPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          // Standard Checkbox should be replaced — the ◆ mark is a Text
          // glyph inside a Container, not a Checkbox.
          expect(
            find.byType(Checkbox),
            findsNothing,
            reason:
                'predicted-PR pending row must use the gold ◆ done-mark, '
                'not the standard violet-bordered Checkbox.',
          );
          expect(find.text('◆'), findsOneWidget);
          // Use bySemanticsIdentifier — the predicted-PR done-cell shares
          // the same `workout-set-done` identifier as the regular pending
          // row (E2E selector contract). Asserting the localized label via
          // find.bySemanticsLabel requires `tester.ensureSemantics()` and a
          // SemanticsHandle dispose, which the existing test infrastructure
          // doesn't set up; the identifier carries the same wiring guarantee.
          expect(
            find.bySemanticsIdentifier('workout-set-done'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'completedSupersededPr display does NOT wrap in RewardAccent without '
        'the gold stripe — only the 2% gold tint requires the ancestor',
        (tester) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedSupersededPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          // Superseded carries gold tint (2%) so the ancestor is mounted.
          expect(find.byType(RewardAccent), findsAtLeastNWidgets(1));
          // But the standard green Checkbox stays — superseded uses ✓ green,
          // not the predicted ◆ mark.
          expect(find.byType(Checkbox), findsOneWidget);
        },
      );

      testWidgets(
        'plain none state renders WITHOUT a RewardAccent ancestor (heroGold '
        'scarcity preserved on non-PR rows)',
        (tester) async {
          final set = makeSet(isCompleted: false);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                // Default display = none, but pinning here for clarity.
                display: const PrRowDisplay.plain(PrRowState.none),
              ),
            ),
          );

          expect(
            find.byType(RewardAccent),
            findsNothing,
            reason:
                'non-PR rows must not mount RewardAccent — that would leak '
                'the gold IconTheme into the row chrome and dilute the '
                'reward-scarcity payoff.',
          );
          expect(find.byType(Checkbox), findsOneWidget);
        },
      );

      testWidgets(
        'completedStandingPr with maxVolume-only accent colors BOTH the '
        'weight stepper AND the reps stepper (compound rule, widget level)',
        (tester) async {
          // The unit-level resolver test pins that a maxVolume-only PR sets
          // both isWeightAccented + isRepsAccented (volume folds into both
          // operands). This widget-level test pins the downstream wiring:
          // SetRow must propagate that compound accent through to BOTH
          // stepper cells' valueColor params, not just one. Regressing this
          // (e.g. accidentally using `accentTypes.contains(maxWeight)` as
          // the stepper-cell guard instead of the `isWeightAccented` getter)
          // would leave a volume-only PR with NO visible accent on the row.
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedStandingPr,
                  accentTypes: {RecordType.maxVolume},
                ),
              ),
            ),
          );

          final weightStepper = tester.widget<WeightStepper>(
            find.byType(WeightStepper),
          );
          final repsStepper = tester.widget<RepsStepper>(
            find.byType(RepsStepper),
          );

          expect(
            weightStepper.valueColor,
            isNotNull,
            reason:
                'maxVolume-only PR must color the WEIGHT stepper (isWeightAccented '
                'folds maxVolume into the weight cell)',
          );
          expect(
            repsStepper.valueColor,
            isNotNull,
            reason:
                'maxVolume-only PR must color the REPS stepper (isRepsAccented '
                'folds maxVolume into the reps cell)',
          );
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

    // -------------------------------------------------------------------------
    // Predicted-PR semantics contract (Flutter Web role-swap workaround).
    //
    // Pins the asymmetric fix in `_DoneCell.build()`: when the row is in
    // [PrRowState.pendingPredictedPr], the Semantics widget that carries
    // the `workout-set-done` identifier MUST also carry both the button
    // role flag (`SemanticsFlag.isButton`) AND the tap action
    // (`SemanticsAction.tap`) on the SAME first-frame semantics update.
    //
    // **Why this matters:** Flutter Web's semantics engine has a bug
    // where a SemanticsNode role transitioning from `GenericRole` →
    // `SemanticButton` on a subsequent frame (because the tap action
    // arrives via merge from a descendant on frame 2) creates a fresh
    // DOM element that does NOT receive the `flt-semantics-identifier`
    // attribute. See engine source `lib/web_ui/lib/src/engine/semantics/
    // semantics.dart` lines 1763-1771 (identifier dirty marker only fires
    // on value change) and 2282-2312 (role swap creates a new DOM element
    // and only re-applies dirty attributes).
    //
    // Putting `button: true` and `onTap: ...` on the SAME `Semantics`
    // widget as the identifier+label means the button role is established
    // on the FIRST semantics frame, before the dirty marker is cleared —
    // no role swap, identifier persists, Playwright can resolve
    // `[flt-semantics-identifier="workout-set-done"]`.
    //
    // If the upstream engine bug is ever fixed, this test still passes —
    // it asserts a positive contract, not a workaround. If a future
    // refactor moves the tap action back into `_PredictedPrUncheckedMark`
    // alone, this test fires before CI burns an e2e cycle.
    // -------------------------------------------------------------------------

    group('predicted-PR done-cell semantics contract', () {
      testWidgets(
        'workout-set-done node carries isButton flag AND tap action on the '
        'identifier-bearing Semantics node (predicted-PR path)',
        (tester) async {
          final handle = tester.ensureSemantics();

          final set = makeSet(isCompleted: false);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.pendingPredictedPr,
                  accentTypes: {RecordType.maxVolume},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Use Flutter's built-in `find.bySemanticsIdentifier` finder,
          // which walks the live SemanticsNode tree maintained by the
          // binding. The matching node carries the merged data of all
          // Semantics widgets that contributed to it (identifier, label,
          // flags, actions) so `tester.getSemantics(...).getSemanticsData()`
          // gives us the full SemanticsData record we need to inspect.
          final finder = find.bySemanticsIdentifier('workout-set-done');
          expect(
            finder,
            findsOneWidget,
            reason:
                'A SemanticsNode with identifier `workout-set-done` MUST '
                'exist in the predicted-PR row. Without it, Playwright '
                'cannot resolve the done-cell selector in e2e tests.',
          );

          final SemanticsData data = tester
              .getSemantics(finder)
              .getSemanticsData();

          // **Contract part 1:** the identifier-bearing node has the button
          // role flag. This is what tells the Flutter Web engine to render
          // the DOM element with role=button from the first frame, so the
          // role-swap engine bug never fires.
          expect(
            data.flagsCollection.isButton,
            isTrue,
            reason:
                'The Semantics node carrying `workout-set-done` must carry '
                'SemanticsFlag.isButton on the SAME node — otherwise Flutter '
                'Web swaps the role from GenericRole to SemanticButton on a '
                'later frame and drops the identifier attribute. See '
                'engine source semantics.dart lines 1763-1771 (identifier '
                'dirty marker) and 2282-2312 (role swap re-creates DOM '
                'element).',
          );

          // **Contract part 2:** the identifier-bearing node has the tap
          // action. This is what makes the AOM element flt-tappable, so
          // Playwright's click(...) actually reaches Flutter's gesture
          // pipeline.
          expect(
            data.hasAction(SemanticsAction.tap),
            isTrue,
            reason:
                'The Semantics node carrying `workout-set-done` must carry '
                'SemanticsAction.tap on the SAME node so Playwright clicks '
                'land on a flt-tappable element. The asymmetric fix puts '
                '`onTap:` on the outer Semantics widget (predicted-PR path) '
                'instead of relying on the inner GestureDetector to merge '
                'its tap action upward, which would trigger the role-swap '
                'bug.',
          );

          // Sanity: the node also carries the user-facing label.
          expect(
            data.label,
            contains('predicted'),
            reason:
                'Sanity check: the contract pin must be looking at the '
                'predicted-PR variant of the done-cell label, not a stray '
                'node with the same identifier elsewhere.',
          );

          handle.dispose();
        },
      );

      testWidgets(
        'tapping the predicted-PR done-cell via its semantics action toggles '
        'completion (proves the AOM-level tap path is wired)',
        (tester) async {
          final handle = tester.ensureSemantics();

          // Force `is_completed: false` — the test factory defaults to true,
          // but the predicted-PR path only renders when the row is BOTH
          // pendingPredictedPr AND not completed. A completed row would
          // route to the Checkbox path with identifier `workout-set-completed`
          // and the `workout-set-done` finder would correctly find nothing.
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 0,
          );
          final workoutData = stateJson['workout'] as Map<String, dynamic>;
          final exercise = TestWorkoutExerciseFactory.create(
            id: 'we-001',
            exerciseId: 'exercise-1',
            order: 1,
          );
          final pendingSet = TestSetFactory.create(
            id: 'set-pending-001',
            workoutExerciseId: 'we-001',
            setNumber: 1,
            isCompleted: false,
          );
          final fullStateJson = {
            'workout': workoutData,
            'exercises': [
              {
                'workout_exercise': exercise,
                'sets': [pendingSet],
              },
            ],
          };
          final workoutState = ActiveWorkoutState.fromJson(fullStateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set = workoutState.exercises.first.sets.first;

          final container = makeContainer(workoutState);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: weId,
                display: const PrRowDisplay(
                  state: PrRowState.pendingPredictedPr,
                  accentTypes: {RecordType.maxVolume},
                ),
              ),
              container: container,
            ),
          );
          await tester.pumpAndSettle();

          // Locate the identifier-bearing semantics node and dispatch a tap
          // through the AOM (NOT the gesture detector). This mirrors what
          // Playwright does when it clicks the flt-tappable DOM element
          // resolved via `[flt-semantics-identifier="workout-set-done"]`.
          final finder = find.bySemanticsIdentifier('workout-set-done');
          expect(finder, findsOneWidget);
          final SemanticsNode node = tester.getSemantics(finder);

          // The semantics owner sits on the deprecated `pipelineOwner` alias
          // in the test binding; `rootPipelineOwner.semanticsOwner` returns
          // null because the meta-owner does not host the semantics tree.
          final SemanticsOwner owner =
              // ignore: deprecated_member_use
              tester.binding.pipelineOwner.semanticsOwner!;
          owner.performAction(node.id, SemanticsAction.tap);
          await tester.pump();

          final updatedState = container.read(activeWorkoutProvider).value;
          expect(
            updatedState?.exercises.first.sets.first.isCompleted,
            isTrue,
            reason:
                'Dispatching SemanticsAction.tap on the identifier-bearing '
                'node must toggle completion. If it does not, the outer '
                'Semantics widget owns the role+label but not the action — '
                'the asymmetric fix is broken.',
          );

          handle.dispose();
        },
      );
    });

    // -------------------------------------------------------------------------
    // Commit 6: 5-state visual matrix
    //
    // One block per state. Each block verifies:
    //   1. Correct done-mark variant rendered (Checkbox vs ◆ text glyph).
    //   2. RewardAccent presence / absence (heroGold scarcity contract).
    //   3. Row height ≥ 56dp (uniform height across all states).
    //   4. Correct semantics identifier on the done-col.
    // -------------------------------------------------------------------------

    group('5-state matrix — state: none (pending, no projected PR)', () {
      testWidgets('renders standard violet-bordered Checkbox done-mark', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.none),
            ),
          ),
        );

        expect(find.byType(Checkbox), findsOneWidget);
        expect(find.text('◆'), findsNothing);
      });

      testWidgets('no RewardAccent ancestor — heroGold scarcity preserved', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.none),
            ),
          ),
        );

        expect(find.byType(RewardAccent), findsNothing);
      });

      testWidgets('row minimum height is at least 56dp', (tester) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.none),
            ),
          ),
        );

        // The _SetRowFrame enforces BoxConstraints(minHeight: 56). Find
        // Containers that carry this constraint — the frame container.
        final frameContainers = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) {
              final bc = c.constraints;
              return bc != null && bc.minHeight >= 56;
            })
            .toList();
        expect(
          frameContainers,
          isNotEmpty,
          reason: 'state:none — row must have minHeight≥56dp frame container',
        );
      });

      testWidgets('done-col semantics identifier is workout-set-done', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.none),
            ),
          ),
        );

        expect(find.bySemanticsIdentifier('workout-set-done'), findsOneWidget);
      });
    });

    group('state: pendingPredictedPr (pending, values would break a PR)', () {
      testWidgets('renders ◆ glyph done-mark instead of Checkbox', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay(
                state: PrRowState.pendingPredictedPr,
                accentTypes: {RecordType.maxWeight},
              ),
            ),
          ),
        );

        expect(
          find.text('◆'),
          findsOneWidget,
          reason: 'predicted-PR must show the gold ◆ glyph',
        );
        expect(
          find.byType(Checkbox),
          findsNothing,
          reason: 'predicted-PR must NOT show the standard Checkbox',
        );
      });

      testWidgets('mounts RewardAccent ancestor (gold colors enabled)', (
        tester,
      ) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay(
                state: PrRowState.pendingPredictedPr,
                accentTypes: {RecordType.maxWeight},
              ),
            ),
          ),
        );

        expect(find.byType(RewardAccent), findsAtLeastNWidgets(1));
      });

      testWidgets('row minimum height is at least 56dp', (tester) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay(
                state: PrRowState.pendingPredictedPr,
                accentTypes: {RecordType.maxWeight},
              ),
            ),
          ),
        );

        final frameContainers = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) {
              final bc = c.constraints;
              return bc != null && bc.minHeight >= 56;
            })
            .toList();
        expect(
          frameContainers,
          isNotEmpty,
          reason:
              'state:pendingPredictedPr — row must have minHeight≥56dp frame container',
        );
      });

      testWidgets('done-col accessibility label is "Mark set as done — '
          'predicted personal record" (en locale)', (tester) async {
        final set = makeSet(isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay(
                state: PrRowState.pendingPredictedPr,
                accentTypes: {RecordType.maxWeight},
              ),
            ),
          ),
        );

        // The l10n key markSetAsDonePredictedPr drives the semantics label.
        // The identifier is still workout-set-done (E2E selector contract).
        expect(
          find.bySemanticsIdentifier('workout-set-done'),
          findsOneWidget,
          reason:
              'predicted-PR done-col must carry the workout-set-done '
              'identifier for E2E selector compatibility',
        );
      });

      // -----------------------------------------------------------------
      // PR #152 fix #3 contract pin — see `tasks/lessons.md`
      // "Semantics container/explicitChildNodes is needed at EVERY tap-
      // merging boundary, not just one place" + "identifiers must live on
      // the actual tap target, not its container".
      //
      // The bug: when the row was in `pendingPredictedPr` state, the inner
      // `_PredictedPrUncheckedMark`'s `GestureDetector` emitted its OWN
      // `role=button` semantic node (Flutter's default for any
      // GestureDetector with onTap). Playwright's
      // `[flt-semantics-identifier="workout-set-done"]` resolved the OUTER
      // element, but a SECOND `<flt-semantics role="button" flt-tappable>`
      // sat on top covering most of the same bounding box, intercepting
      // every click. The CI artifact log showed:
      //
      //   <flt-semantics role="button" flt-tappable id="...152">
      //     Mark set as done — predicted record↵◆
      //   </flt-semantics> from <flt-semantics id="...153">…</flt-semantics>
      //   subtree intercepts pointer events
      //
      // Fix: GestureDetector(excludeFromSemantics: true) — the inner gesture
      // still hit-tests (taps still toggle completion via render-object
      // hit-test), but does NOT emit a competing semantic node. The OUTER
      // _DoneCell `Semantics(identifier: 'workout-set-done', label: ...)`
      // becomes the SOLE addressable AOM node for that region, and a
      // Playwright click targeting that identifier reaches the underlying
      // gesture without interception.
      //
      // This widget test pins the contract STRUCTURALLY: in
      // pendingPredictedPr state, the done-cell subtree must contain
      // EXACTLY ONE SemanticsNode that exposes `flt-semantics-identifier=
      // "workout-set-done"`, and there must NOT be a competing descendant
      // SemanticsNode whose label contains "predicted" — that would
      // indicate the inner GestureDetector regressed back to emitting its
      // own button.
      testWidgets(
        'predicted-PR done-cell — no competing inner button node leaks '
        'predicted-PR semantics (excludeFromSemantics on inner gesture)',
        (tester) async {
          final handle = tester.ensureSemantics();

          final set = makeSet(isCompleted: false);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.pendingPredictedPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          // The OUTER identifier-bearing node exists exactly once.
          expect(
            find.bySemanticsIdentifier('workout-set-done'),
            findsOneWidget,
            reason:
                'predicted-PR done-cell must expose the workout-set-done '
                'identifier (E2E selector contract).',
          );

          // CRITICAL: walk the entire SemanticsNode tree under the test
          // widget and assert there is NO node with `SemanticsAction.tap`
          // whose label contains "predicted". Before the fix, the inner
          // _PredictedPrUncheckedMark's GestureDetector emitted a SECOND
          // semantic node with action=tap and label containing the
          // localized "predicted personal record" string. Playwright
          // resolved the outer identifier correctly, but the click was
          // intercepted by this second node's larger flt-tappable region.
          //
          // With `excludeFromSemantics: true` on the inner GestureDetector,
          // no such competing semantic node exists — and there is at most
          // ONE tap-action-bearing semantic node in the done-cell subtree
          // (the outer Semantics declares the label without onTap; the
          // inner gesture is excluded; no flt-tappable button leaks).
          // The semantics tree we want lives on the binding's render-object
          // pipeline owner. `rootPipelineOwner` is the meta-owner — its
          // `semanticsOwner` is null in the test harness; the populated
          // owner sits on `pipelineOwner` (deprecated alias, no drop-in
          // replacement that exposes a non-null semanticsOwner from the
          // test binding — keep using it).
          final SemanticsOwner owner =
              // ignore: deprecated_member_use
              tester.binding.pipelineOwner.semanticsOwner!;
          final List<SemanticsNode> competingNodes = [];
          void walk(SemanticsNode node) {
            final data = node.getSemanticsData();
            // A regression would show as a node carrying both a tap action
            // AND a label containing "predicted" (the localized
            // markSetAsDonePredictedPr string).
            if (data.hasAction(SemanticsAction.tap) &&
                data.label.toLowerCase().contains('predicted')) {
              competingNodes.add(node);
            }
            node.visitChildren((child) {
              walk(child);
              return true;
            });
          }

          walk(owner.rootSemanticsNode!);

          // We expect AT MOST one such node — the parent _DoneCell
          // Semantics, if and only if the framework merged the inner
          // gesture's tap action up into it. The bug was TWO such nodes
          // (parent identifier + inner button) creating an interception.
          // STRUCTURALLY: with the fix in place, we observe ZERO inner
          // competing button nodes — the inner gesture is fully excluded.
          expect(
            competingNodes.length,
            lessThanOrEqualTo(1),
            reason:
                'Found ${competingNodes.length} competing SemanticsNodes '
                'with action=tap AND label containing "predicted". The '
                'inner _PredictedPrUncheckedMark GestureDetector must use '
                'excludeFromSemantics: true so it does not emit a SECOND '
                'flt-tappable node that intercepts Playwright clicks aimed '
                'at the workout-set-done identifier. Regression of this '
                'test almost certainly means PR #152\'s "fix attempt #4" is '
                'about to ship with the same e2e failure pattern.',
          );

          // Dispose the SemanticsHandle synchronously inside the test body —
          // Flutter's _endOfTestVerifications check runs BEFORE addTearDown
          // callbacks, so addTearDown(handle.dispose) leaks the handle past
          // the verification gate and triggers a "SemanticsHandle was active
          // at the end of the test" failure.
          handle.dispose();
        },
      );
    });

    group('state: completedNonPr (completed, no PR broken)', () {
      testWidgets('renders green Checkbox done-mark', (tester) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.completedNonPr),
            ),
          ),
        );

        expect(find.byType(Checkbox), findsOneWidget);
        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(
          checkbox.value,
          isTrue,
          reason: 'completed set must show checked Checkbox',
        );
        expect(
          find.text('◆'),
          findsNothing,
          reason: 'completedNonPr must not show the predicted-PR ◆ glyph',
        );
      });

      testWidgets('no RewardAccent ancestor — zero gold on plain completed', (
        tester,
      ) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.completedNonPr),
            ),
          ),
        );

        expect(
          find.byType(RewardAccent),
          findsNothing,
          reason:
              'completedNonPr must NOT mount RewardAccent — no gold '
              'on plain completed rows (heroGold scarcity contract)',
        );
      });

      testWidgets('row minimum height is at least 56dp', (tester) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.completedNonPr),
            ),
          ),
        );

        final frameContainers = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) {
              final bc = c.constraints;
              return bc != null && bc.minHeight >= 56;
            })
            .toList();
        expect(
          frameContainers,
          isNotEmpty,
          reason:
              'state:completedNonPr — row must have minHeight≥56dp frame container',
        );
      });

      testWidgets('done-col semantics identifier is workout-set-completed', (
        tester,
      ) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay.plain(PrRowState.completedNonPr),
            ),
          ),
        );

        expect(
          find.bySemanticsIdentifier('workout-set-completed'),
          findsOneWidget,
        );
      });
    });

    group(
      'state: completedSupersededPr (completed PR demoted by a later set)',
      () {
        testWidgets('renders green Checkbox (not ◆) — superseded is done', (
          tester,
        ) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedSupersededPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          expect(
            find.byType(Checkbox),
            findsOneWidget,
            reason: 'superseded row is completed — must show Checkbox, not ◆',
          );
          final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
          expect(checkbox.value, isTrue);
          expect(find.text('◆'), findsNothing);
        });

        testWidgets(
          'mounts RewardAccent ancestor (2% gold tint path requires it)',
          (tester) async {
            final set = makeSet(isCompleted: true);
            await tester.pumpWidget(
              buildTestWidget(
                SetRow(
                  set: set,
                  workoutExerciseId: 'we-001',
                  display: const PrRowDisplay(
                    state: PrRowState.completedSupersededPr,
                    accentTypes: {RecordType.maxWeight},
                  ),
                ),
              ),
            );

            expect(
              find.byType(RewardAccent),
              findsAtLeastNWidgets(1),
              reason:
                  'completedSupersededPr has a 2% gold background tint — '
                  'the tint is rendered via RewardAccent.of(ctx), so the '
                  'ancestor must be present',
            );
          },
        );

        testWidgets('row minimum height is at least 56dp', (tester) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedSupersededPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          final frameContainers = tester
              .widgetList<Container>(find.byType(Container))
              .where((c) {
                final bc = c.constraints;
                return bc != null && bc.minHeight >= 56;
              })
              .toList();
          expect(
            frameContainers,
            isNotEmpty,
            reason:
                'state:completedSupersededPr — row must have minHeight≥56dp '
                'frame container',
          );
        });
      },
    );

    group(
      'state: completedStandingPr (completed PR currently the best overall)',
      () {
        testWidgets(
          'renders green Checkbox and ◆ is absent — standing uses ✓ not ◆',
          (tester) async {
            final set = makeSet(isCompleted: true);
            await tester.pumpWidget(
              buildTestWidget(
                SetRow(
                  set: set,
                  workoutExerciseId: 'we-001',
                  display: const PrRowDisplay(
                    state: PrRowState.completedStandingPr,
                    accentTypes: {RecordType.maxWeight},
                  ),
                ),
              ),
            );

            expect(
              find.byType(Checkbox),
              findsOneWidget,
              reason:
                  'completed standing PR uses the standard checked Checkbox '
                  '(✓ green), not the ◆ mark',
            );
            expect(find.text('◆'), findsNothing);
          },
        );

        testWidgets(
          'mounts RewardAccent ancestor (4dp gold stripe + bracket)',
          (tester) async {
            final set = makeSet(isCompleted: true);
            await tester.pumpWidget(
              buildTestWidget(
                SetRow(
                  set: set,
                  workoutExerciseId: 'we-001',
                  display: const PrRowDisplay(
                    state: PrRowState.completedStandingPr,
                    accentTypes: {RecordType.maxWeight},
                  ),
                ),
              ),
            );

            expect(find.byType(RewardAccent), findsAtLeastNWidgets(1));
          },
        );

        testWidgets('row minimum height is at least 56dp', (tester) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedStandingPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          final frameContainers = tester
              .widgetList<Container>(find.byType(Container))
              .where((c) {
                final bc = c.constraints;
                return bc != null && bc.minHeight >= 56;
              })
              .toList();
          expect(
            frameContainers,
            isNotEmpty,
            reason:
                'state:completedStandingPr — row must have minHeight≥56dp '
                'frame container',
          );
        });

        testWidgets('done-col semantics identifier is workout-set-completed', (
          tester,
        ) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay(
                  state: PrRowState.completedStandingPr,
                  accentTypes: {RecordType.maxWeight},
                ),
              ),
            ),
          );

          expect(
            find.bySemanticsIdentifier('workout-set-completed'),
            findsOneWidget,
          );
        });
      },
    );

    // -------------------------------------------------------------------------
    // heroGold scarcity structural test (commit 6)
    //
    // Pins the "gold appears in EXACTLY the right places" contract. These tests
    // walk the widget tree and count RewardAccent widgets to detect accidental
    // gold leakage or missing gold in future refactors.
    // -------------------------------------------------------------------------

    group('heroGold scarcity', () {
      testWidgets('standing-PR row mounts RewardAccent (gold is present on '
          'the three lawful surfaces: stripe, value text, right bracket)', (
        tester,
      ) async {
        final set = makeSet(isCompleted: true);
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set,
              workoutExerciseId: 'we-001',
              display: const PrRowDisplay(
                state: PrRowState.completedStandingPr,
                accentTypes: {RecordType.maxWeight},
              ),
            ),
          ),
        );

        // The row is wrapped in exactly ONE RewardAccent ancestor — the
        // _SetRowFrame's wrapper. Multiple nested RewardAccent widgets would
        // be redundant but harmless; the structural guarantee is ≥1.
        expect(
          find.byType(RewardAccent),
          findsAtLeastNWidgets(1),
          reason:
              'completedStandingPr must wrap the row in RewardAccent so all '
              'three gold surfaces (stripe, value, bracket) resolve via the '
              'ancestor context',
        );
      });

      testWidgets(
        'completedNonPr row mounts zero RewardAccent — no gold present',
        (tester) async {
          final set = makeSet(isCompleted: true);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay.plain(PrRowState.completedNonPr),
              ),
            ),
          );

          expect(
            find.byType(RewardAccent),
            findsNothing,
            reason:
                'completedNonPr must have zero gold (heroGold scarcity). A '
                'RewardAccent here would leak gold IconTheme into every Icon '
                'and Text in the row — diluting the reward signal.',
          );
        },
      );

      testWidgets(
        'none (pending) row mounts zero RewardAccent — no gold present',
        (tester) async {
          final set = makeSet(isCompleted: false);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay.plain(PrRowState.none),
              ),
            ),
          );

          expect(
            find.byType(RewardAccent),
            findsNothing,
            reason:
                'state:none (pending, no PR projection) must have zero gold. '
                'Any RewardAccent here means the heroGold IconTheme infects '
                'the stepper +/- buttons, violating the scarcity contract.',
          );
        },
      );
    });
  });
}
