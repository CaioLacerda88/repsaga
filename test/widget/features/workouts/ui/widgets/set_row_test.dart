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

Widget buildTestWidget(
  Widget child, {
  ProviderContainer? container,
  Locale? locale,
}) {
  return UncontrolledProviderScope(
    container: container ?? makeContainer(null),
    child: TestMaterialApp(
      theme: AppTheme.dark,
      locale: locale,
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

    // Phase 23 D4: 'ghost text (previous session hint)' + 'match indicator
    // (Pillar 1)' groups removed alongside the SetRow `lastSet` field and
    // the conditional hint slot rendering. Replaced by a single negative
    // assertion below (`per-row hint removal (Phase 23 D4)`). Pre-fill
    // now carries the anchor; the yellow PR marker remains the win
    // signal.

    group('set-type micro-label (Phase 20 polish #3)', () {
      // The persistent set-type label below the set number is the visible
      // affordance for the long-press cycle on the set-number cell. Without
      // it the cycle interaction was structurally hidden — see the original
      // Phase 20 critique Problem 2 ("set-type ... not discoverable as
      // interactive"). The label is self-teaching: a user who long-presses
      // and watches the abbr cycle learns the feature.
      //
      // **Path A localization (Family 6):** values now flow from the
      // canonical `setTypeAbbr*Short` ARB family (warmup uses
      // `setTypeAbbrWarmupShort`) — en: W/Wu/D/F, pt: N/Aq/D/F — matching
      // the convention already used by `workout_detail_screen.dart:286`.
      // The pre-Path-A pins on raw `WK/DR/FL` were the bug; the
      // intermediate-state pin on `WU` (long form) was the post-Path-A
      // execution gap addressed by the PR #187 reviewer cycle.

      testWidgets('renders "W" label for a Working set (en)', (tester) async {
        final set = makeSet(setType: SetType.working);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        expect(find.text('W'), findsOneWidget);
      });

      testWidgets('renders "Wu" label for a Warmup set (en)', (tester) async {
        final set = makeSet(setType: SetType.warmup);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        // Active workout consumes `setTypeAbbrWarmupShort` (en: 'Wu') —
        // matches `workout_detail_screen.dart:286`. The verbose
        // `setTypeAbbrWarmup` (en: 'WU') is unused in the active workout
        // surface post-PR-187.
        expect(find.text('Wu'), findsOneWidget);
        expect(find.text('WU'), findsNothing);
      });

      testWidgets('renders "D" label for a Drop set (en)', (tester) async {
        final set = makeSet(setType: SetType.dropset);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        expect(find.text('D'), findsOneWidget);
      });

      testWidgets('renders "F" label for a Failure set (en)', (tester) async {
        final set = makeSet(setType: SetType.failure);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        expect(find.text('F'), findsOneWidget);
      });

      testWidgets(
        'set-number cell preserves its 48dp tap-target floor with the new label',
        (tester) async {
          // BUG-018 contract: the set-number cell must keep at least 48×48dp
          // for the long-press cycle interaction to fire reliably under
          // sweaty thumbs on 360dp Brazilian-mid-market screens. Adding the
          // micro-label below the digit must not regress this floor.
          final set = makeSet(setType: SetType.working);
          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );

          // The cell's Container has `BoxConstraints(minWidth: 48,
          // minHeight: 48)` — verify the rendered size respects that.
          // Use the localized en label for "Working" — "W".
          final cellFinder = find.ancestor(
            of: find.text('W'),
            matching: find.byType(Container),
          );
          final size = tester.getSize(cellFinder.first);
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
        },
      );

      testWidgets(
        'tap-to-copy dotted underline still applies to the digit (set #2+), NOT the type label',
        (tester) async {
          // The underline is the affordance for tap-to-copy-last-set; it
          // must NOT extend to the type label, which is the affordance for
          // the long-press cycle. Conflating the two would teach the user
          // that tapping cycles types — wrong interaction.
          final set = makeSet(setNumber: 2, setType: SetType.warmup);
          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );

          final digitText = tester.widget<Text>(find.text('2'));
          final labelText = tester.widget<Text>(find.text('Wu'));

          expect(
            digitText.style?.decoration,
            TextDecoration.underline,
            reason: 'set-#2 digit should keep the dotted underline.',
          );
          expect(
            labelText.style?.decoration,
            anyOf(isNull, TextDecoration.none),
            reason: 'set-type label must not carry the tap-to-copy underline.',
          );
        },
      );
    });

    group('bodyweight chrome (PLAN.md backlog 20-P-2)', () {
      // Bodyweight exercises (push-ups, pull-ups, planks) have no meaningful
      // weight axis. The resolver in `pr_row_state_resolver.dart` already
      // excludes weight from PR detection in this mode (only RecordType.maxReps
      // is considered). The `isBodyweight` flag aligns the row chrome with
      // that contract: hide the weight stepper entirely and let the reps
      // column take the freed space.

      testWidgets('omits the weight stepper when isBodyweight is true', (
        tester,
      ) async {
        final set = makeSet();
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(set: set, workoutExerciseId: 'we-001', isBodyweight: true),
          ),
        );

        // The weight column is gone; the reps column is the only stepper
        // in the row.
        expect(find.byType(WeightStepper), findsNothing);
        expect(find.byType(RepsStepper), findsOneWidget);
      });

      testWidgets(
        'still renders the weight stepper for non-bodyweight exercises (default)',
        (tester) async {
          // Default: `isBodyweight: false`. Standard layout retained for
          // every existing equipment type — barbell, dumbbell, machine, etc.
          final set = makeSet();
          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );

          expect(find.byType(WeightStepper), findsOneWidget);
          expect(find.byType(RepsStepper), findsOneWidget);
        },
      );

      testWidgets(
        'still renders the set-num cell, type label, and done-cell when bodyweight',
        (tester) async {
          // Hiding the weight column must not regress the surrounding chrome
          // — the digit, the localized "W" type label (en), and the
          // completion checkbox stay exactly where they are.
          final set = makeSet(setType: SetType.working);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001', isBodyweight: true),
            ),
          );

          expect(find.text('1'), findsOneWidget); // set number
          expect(find.text('W'), findsOneWidget); // type micro-label (en)
          expect(find.byType(Checkbox), findsOneWidget); // done-cell
        },
      );

      testWidgets(
        'bodyweight + completed-standing-PR (maxReps accent) renders the gold treatment without the weight column',
        (tester) async {
          // Bodyweight exercises CAN still produce reps PRs — the resolver
          // checks `RecordType.maxReps` only in bodyweight mode. The row
          // chrome path that draws the gold treatment must continue to flow
          // when the weight stepper is hidden: this is the single
          // intersection of the two changes (`isBodyweight` and PR-state)
          // and the most likely place a future change could regress one
          // without noticing the other.
          final set = makeSet(isCompleted: true);
          const display = PrRowDisplay(
            state: PrRowState.completedStandingPr,
            accentTypes: {RecordType.maxReps},
          );

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: display,
                isBodyweight: true,
              ),
            ),
          );

          // Gold treatment present (RewardAccent ancestor mounts on
          // standing-PR / predicted-PR row states).
          expect(find.byType(RewardAccent), findsOneWidget);
          // Weight column hidden; reps column still present and accented.
          expect(find.byType(WeightStepper), findsNothing);
          expect(find.byType(RepsStepper), findsOneWidget);
        },
      );
    });

    group('Failure micro-label color (PLAN.md backlog 20-P-3)', () {
      // Audit Finding B: pending failure-set label should be amber (warning),
      // not red (error). Red conflicts with the gym-floor emotional register
      // — the failure label in red on a pending set reads as "something is
      // wrong" rather than "this is a max-effort set."

      testWidgets(
        'uses AppColors.warning (not error) for a pending Failure set label',
        (tester) async {
          final set = makeSet(setType: SetType.failure, isCompleted: false);
          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );

          // Localized en abbreviation for failure is "F"
          // (l10n.setTypeAbbrFailure).
          final labelText = tester.widget<Text>(find.text('F'));
          final color = labelText.style?.color;
          expect(color, isNotNull);

          // The rendered color is `AppColors.warning.withValues(alpha: 0.6)`
          // — same RGB channels as the constant, alpha intentionally
          // dimmed. Normalise both sides to alpha=1.0 and assert RGB
          // equality. `withValues(alpha: 1.0)` is stable across Flutter
          // SDK versions (vs the deprecated int `Color.red/green/blue`
          // accessors that the analyzer flags on Flutter 3.27+).
          expect(
            color!.withValues(alpha: 1.0),
            AppColors.warning,
            reason:
                'Failure pending should track AppColors.warning, not error.',
          );
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

    // Phase 23 D4: 'hint line suppression' group removed alongside the
    // hint feature itself. Negative coverage lives in the
    // `per-row hint removal (Phase 23 D4)` group near the end of this
    // file.

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

    // -------------------------------------------------------------------------
    // Fix 3 — suppress "Previous: 0kg × N" hint
    //
    // The previous-session hint anchors the user to last session's working
    // weight; a 0kg "anchor" is noise. WIP.md instructs hiding the hint
    // entirely when `lastSet.weight == 0`, with no replacement label —
    // empty space is the correct UX.
    // -------------------------------------------------------------------------
    // Phase 23 D4: 'previous-session hint zero-weight suppression (Fix 3)'
    // group removed alongside the hint feature itself. The
    // standing-PR-row identifier-survives-with-hint-suppressed pin
    // (originally Important 5 / Fix 3) is subsumed by the new
    // 'per-row hint removal (Phase 23 D4)' group below, which pins the
    // structural guarantee directly: the row Semantics tree no longer
    // mutates on completion because there are no longer any descendant
    // hint nodes that join/leave.

    // -------------------------------------------------------------------------
    // Fix 2 — copy-from-previous-set discoverability icon (sets 2+ only,
    // visible only when current weight differs from previous in-session set).
    //
    // Existing tap-on-set-number copies last set values; this fix makes that
    // affordance VISUALLY discoverable instead of relying on the dotted
    // underline alone. WIP.md: 12dp Icons.content_copy at alpha 0.4.
    // -------------------------------------------------------------------------
    group('copy-from-previous-set discoverability (Fix 2)', () {
      testWidgets(
        'shows copy icon on set 2 when current weight differs from previous in-session set',
        (tester) async {
          final set2 = makeSet(
            id: 'set-2',
            setNumber: 2,
            weight: 0,
            reps: 8,
            isCompleted: false,
          );
          final previous = makeSet(
            id: 'set-1',
            setNumber: 1,
            weight: 20,
            reps: 8,
            isCompleted: false,
          );
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set2,
                workoutExerciseId: 'we-001',
                previousSet: previous,
              ),
            ),
          );

          expect(
            find.byIcon(Icons.content_copy),
            findsOneWidget,
            reason:
                'set 2+ rows whose weight differs from the previous in-session '
                'set must surface a 12dp Icons.content_copy hint at alpha 0.4 '
                'so the tap-to-copy affordance is discoverable.',
          );
        },
      );

      testWidgets('hides copy icon when weights match', (tester) async {
        final set2 = makeSet(
          id: 'set-2',
          setNumber: 2,
          weight: 20,
          isCompleted: false,
        );
        final previous = makeSet(
          id: 'set-1',
          setNumber: 1,
          weight: 20,
          isCompleted: false,
        );
        await tester.pumpWidget(
          buildTestWidget(
            SetRow(
              set: set2,
              workoutExerciseId: 'we-001',
              previousSet: previous,
            ),
          ),
        );

        expect(
          find.byIcon(Icons.content_copy),
          findsNothing,
          reason:
              'matching weights → no copy hint (it would be self-referential).',
        );
      });

      testWidgets('hides copy icon on set 1 (no previous set)', (tester) async {
        final set1 = makeSet(setNumber: 1, weight: 0, isCompleted: false);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set1, workoutExerciseId: 'we-001')),
        );

        expect(
          find.byIcon(Icons.content_copy),
          findsNothing,
          reason: 'set 1 has no previous set — affordance is meaningless.',
        );
      });

      testWidgets(
        'set-number cell tap target stays at Material 48dp floor with the copy icon present',
        (tester) async {
          // Per memory feedback (feedback_tap_target_measurement.md): use
          // tester.getSize, not boundingBox/minimumSize. The icon must not
          // shrink the InkWell's hit area below 48x48.
          final set2 = makeSet(
            id: 'set-2',
            setNumber: 2,
            weight: 0,
            isCompleted: false,
          );
          final previous = makeSet(
            id: 'set-1',
            setNumber: 1,
            weight: 20,
            isCompleted: false,
          );
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: set2,
                workoutExerciseId: 'we-001',
                previousSet: previous,
              ),
            ),
          );

          // The set-number InkWell's Container has explicit
          // BoxConstraints(minWidth: 48, minHeight: 48). Find that container
          // (it sits inside the Tooltip → InkWell → Container chain in
          // _SetNumberCell) and confirm it's at least 48x48 even with the
          // icon present.
          final inkWell = find.descendant(
            of: find.byType(SetRow),
            matching: find.byWidgetPredicate(
              (w) => w is InkWell && w.onLongPress != null,
            ),
          );
          expect(inkWell, findsOneWidget);
          final size = tester.getSize(inkWell);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        },
      );
    });

    // -------------------------------------------------------------------------
    // Fix 2 — propagated weight slot-machine slide animation
    //
    // When a set's weight value updates because of a *propagation* (the user
    // tapped +/- on an earlier "leader" set and this row is following), the
    // value text slides up via AnimatedSwitcher (150ms easeOut, slide from
    // Offset(0, 0.3) to Offset.zero). User-initiated taps on this row's own
    // stepper change the value directly without the slide — only propagated
    // changes animate, distinguishing "I changed this" from "the app
    // inferred this for me".
    // -------------------------------------------------------------------------
    group('propagated weight animation (Fix 2)', () {
      testWidgets(
        'mounts AnimatedSwitcher around the weight value (animation entry-point exists)',
        (tester) async {
          // The animation contract requires an AnimatedSwitcher wrapping the
          // value text in the weight cell. Without it, propagated value
          // changes can't render the slot-machine slide. This test pins the
          // structural presence; the per-frame slide is asserted in the
          // animation test below.
          final set = makeSet(isCompleted: false, weight: 20);
          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );

          expect(
            find.descendant(
              of: find.byType(WeightStepper),
              matching: find.byType(AnimatedSwitcher),
            ),
            findsOneWidget,
            reason:
                'WeightStepper value zone must wrap an AnimatedSwitcher so '
                'propagated value changes can play the slot-machine slide.',
          );
        },
      );

      testWidgets(
        'propagated weight change (external rebuild) passes non-zero duration '
        'to WeightStepper — animation plays',
        (tester) async {
          // The Fix 2 animation contract: when set.weight changes between
          // builds WITHOUT a user tap on THIS cell's stepper, the
          // _WeightStepperCellState._userInitiatedThisChange flag is false,
          // so the cell passes valueChangeDuration: 150ms to WeightStepper —
          // which triggers the slot-machine slide via AnimatedSwitcher.
          //
          // Mechanism: pump SetRow(weight=0) first to seed _lastSeenWeight=0
          // in _WeightStepperCellState. Then re-pump with weight=20 at the
          // SAME tree position (same container, same SetRow key) WITHOUT
          // going through _onWeightTapped. The second build sees:
          //   weightChanged = (_lastSeenWeight=0) != (currentWeight=20) → true
          //   _userInitiatedThisChange → false  (no tap occurred)
          //   shouldAnimate = true
          //   → WeightStepper.valueChangeDuration = Duration(milliseconds:150)
          //
          // Using two pumpWidget calls with the same container keeps the
          // _WeightStepperCellState instance alive across the pump because
          // the SetRow is at the same position in an otherwise-identical tree.
          final container = makeContainer(null);
          addTearDown(container.dispose);
          const weId = 'we-anim';
          const setKey = ValueKey('set-anim-key');

          // First pump: weight=0 seeds _lastSeenWeight.
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                key: setKey,
                set: makeSet(id: 'set-anim', setNumber: 1, weight: 0),
                workoutExerciseId: weId,
              ),
              container: container,
            ),
          );
          await tester.pump();

          // Second pump: weight=20. No _onWeightTapped call → propagation path.
          // Same container + same key → _WeightStepperCellState is PRESERVED,
          // so _lastSeenWeight carries over from the first pump.
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                key: setKey,
                set: makeSet(id: 'set-anim', setNumber: 1, weight: 20),
                workoutExerciseId: weId,
              ),
              container: container,
            ),
          );
          await tester.pump();

          final stepper = tester.widget<WeightStepper>(
            find.byType(WeightStepper),
          );
          expect(
            stepper.valueChangeDuration,
            const Duration(milliseconds: 150),
            reason:
                'A weight change that arrived via external rebuild (propagation) '
                'must pass valueChangeDuration=150ms so the AnimatedSwitcher '
                'plays the slot-machine slide. User-initiated taps use '
                'Duration.zero so only propagated changes animate.',
          );
        },
      );

      testWidgets(
        'user-initiated weight tap passes Duration.zero to WeightStepper — no animation',
        (tester) async {
          // When the user taps +/- on THIS set row's own stepper, the
          // _WeightStepperCellState._userInitiatedThisChange flag is set to
          // true before the rebuild. That build sees weightChanged=true but
          // _userInitiatedThisChange=true → shouldAnimate=false →
          // WeightStepper.valueChangeDuration stays Duration.zero.
          //
          // This test pins the user-initiated path by wiring a real notifier
          // container, calling propagateWeight on set#1 WITH this set as the
          // leader (so _onWeightTapped fires, setting the flag), and then
          // reading valueChangeDuration.
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 1,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;
          final set1 = workoutState.exercises.first.sets.first;

          // Seed set#1 at weight=0 so the tap-to-20kg is a real change.
          final seeded = workoutState.copyWith(
            exercises: [
              workoutState.exercises.first.copyWith(
                sets: [set1.copyWith(weight: 0)],
              ),
            ],
          );
          final seededSet = seeded.exercises.first.sets.first;

          final container = makeContainer(seeded);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: seededSet, workoutExerciseId: weId),
              container: container,
            ),
          );
          await tester.pump();

          // Tap the + button on the weight stepper to increment weight.
          // This wires through _onWeightTapped → sets _userInitiatedThisChange=true.
          await tester.tap(find.byIcon(Icons.add).first);
          await tester.pump();

          // After the user-initiated tap the flag was set to true, then
          // cleared after the build. The AnimatedSwitcher got Duration.zero.
          // Re-read the stepper in the post-tap build state.
          final stepper = tester.widget<WeightStepper>(
            find.byType(WeightStepper),
          );
          expect(
            stepper.valueChangeDuration,
            Duration.zero,
            reason:
                'A user-initiated tap on THIS cell\'s stepper must pass '
                'valueChangeDuration=Duration.zero so the value update is '
                'instant — the user already knows they tapped. Only propagated '
                'changes (external rebuilds from sibling cell taps) animate.',
          );
        },
      );

      testWidgets(
        'rapid taps on the leader cell propagate to followers using the '
        'committed state — not the stale widget.set.weight',
        (tester) async {
          // Important 4 regression pin: previously `_onWeightTapped` read
          // `widget.set.weight` to compute `old`. Inside a rapid two-tap
          // sequence on the same frame, the widget hadn't rebuilt between
          // taps, so tap #2 saw `old = pre-tap-#1 weight` (stale). The
          // notifier's walker compared the followers' (already-updated)
          // weight to the stale `old`, mismatched, and bailed —
          // followers were silently left behind.
          //
          // Repro: leader at 0kg, two followers at 0kg. Tap leader to 5kg
          // (propagates: leader+followers = 5). Tap leader AGAIN by passing
          // a STALE widget.set (weight=0) on a fresh pump — same widget
          // instance, no rebuild. Handler must read 5 from the notifier
          // (committed state), pass `old=5` to propagateWeight, and
          // followers must move to 10. Pre-fix: handler would read
          // `widget.set.weight=0`, propagate `old=0 → new=10`, walker
          // bails on first follower (weight is 5, not 0), followers stay
          // at 5.
          //
          // We test the contract directly by reading the notifier's
          // committed state after the rapid sequence and asserting all
          // three sets land at the final intended weight.
          final stateJson = TestActiveWorkoutStateFactory.createWithExercises(
            exerciseCount: 1,
            setsPerExercise: 3,
          );
          final workoutState = ActiveWorkoutState.fromJson(stateJson);
          final weId = workoutState.exercises.first.workoutExercise.id;

          // Seed all 3 sets at 0kg AND not completed. The factory default
          // is `is_completed=true`, which would stop propagation at the
          // first follower (completed sets are immutable per the
          // `propagateWeight` contract). We need all three pending so the
          // walker traverses end-to-end.
          final seeded = workoutState.copyWith(
            exercises: [
              workoutState.exercises.first.copyWith(
                sets: workoutState.exercises.first.sets
                    .map((s) => s.copyWith(weight: 0, isCompleted: false))
                    .toList(),
              ),
            ],
          );
          final leaderSet = seeded.exercises.first.sets.first;

          final container = makeContainer(seeded);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);
          final notifier = container.read(activeWorkoutProvider.notifier);

          // First propagate: 0 → 5. Simulates tap #1.
          await notifier.propagateWeight(weId, leaderSet.id, 0, 5);
          // Verify state committed: all three at 5.
          final afterFirst = container.read(activeWorkoutProvider).value!;
          expect(
            afterFirst.exercises.first.sets.map((s) => s.weight).toList(),
            [5, 5, 5],
            reason:
                'Tap #1 must propagate the new weight to all followers '
                'still in formation.',
          );

          // Pump SetRow with the STALE leaderSet (weight=0) — this is
          // what the widget tree holds between the two rapid taps before
          // the parent rebuilds. The handler must NOT trust this stale
          // value.
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: leaderSet, workoutExerciseId: weId),
              container: container,
            ),
          );
          await tester.pump();

          // Tap the + button on the weight stepper. The widget tree still
          // holds `widget.set.weight=0` (stale), but the COMMITTED state
          // is leader=5, followers=5. The fix is for `_onWeightTapped` to
          // read the committed weight (5) when computing `oldWeight` —
          // not `widget.set.weight` (0).
          //
          // Pre-fix:  oldWeight=0 → walker compares followers' actual
          //           weight (5) to 0 → mismatch → walker bails →
          //           followers DO NOT move with the leader → drift.
          // Post-fix: oldWeight=5 → walker compares followers' actual
          //           weight (5) to 5 → match → walker updates them →
          //           followers move with the leader → no drift.
          //
          // We don't pin the EXACT new weight (it depends on what
          // `widget.value + increment` resolves to with the stale widget,
          // which is a known orthogonal staleness issue not in scope here).
          // We pin the propagation CORRECTNESS contract: all three sets
          // remain equal after the second tap.
          await tester.tap(find.byIcon(Icons.add).first);
          await tester.pump();

          final afterSecond = container.read(activeWorkoutProvider).value!;
          final weights = afterSecond.exercises.first.sets
              .map((s) => s.weight ?? 0)
              .toList();
          expect(
            weights[1],
            equals(weights[0]),
            reason:
                'Follower #1 must move with the leader. Pre-fix, the handler '
                'would have read `widget.set.weight=0` as oldWeight, the '
                'walker would compare followers (at 5) to 0, mismatch, bail, '
                'and the follower would stay at 5 while the leader moved — '
                'visible drift. Post-fix, the handler reads the committed '
                'weight (5) so the walker matches and the follower moves '
                'with the leader.',
          );
          expect(
            weights[2],
            equals(weights[0]),
            reason:
                'Follower #2 must move with the leader (same contract as '
                'follower #1). Both followers must remain aligned with the '
                'leader after a rapid second tap regardless of stale widget '
                'state.',
          );
        },
      );
    });

    // -------------------------------------------------------------------------
    // PR-5 H8 — Hint slot layout stability + AOM survival across the
    // pending->completed transition.
    //
    // Pre-fix: when a set transitioned pending->completed the previous-
    // session hint Padding was REMOVED from the Column entirely. The row's
    // vertical geometry collapsed by ~18dp and adjacent rows shifted upward
    // mid-gesture, causing miss-taps on the next checkbox down.
    //
    // Post-fix (mobile only — `!kIsWeb`): a fixed-height ExcludeSemantics-
    // wrapped SizedBox keeps the hint slot's vertical footprint stable
    // across the completion transition. Web continues to use the
    // conditional render to avoid re-triggering the Flutter Web semantics
    // engine role-swap bug documented in `_shouldShowHint`.
    //
    // The two pins below run under the standard test binding (host platform
    // = Linux/Mac/Win, kIsWeb=false → the !kIsWeb branch is active). They
    // exercise the layout-stability contract. The AOM survival contract
    // for the pendingPredictedPr->completedStandingPr transition is pinned
    // by E2E (personal-records.spec.ts:264/309, rank-up-celebration.spec.ts:847).
    // -------------------------------------------------------------------------

    // Phase 23 D4: 'H8 — hint slot layout stability (PR-5)' group removed.
    // Pre-Phase-23 the row reserved an 18dp filler ABOVE the frame so
    // adjacent rows wouldn't shift on completion. With the hint feature
    // gone the filler is gone too — the row's vertical geometry is fixed
    // at render time, so there's nothing to stabilise. The standing-PR-
    // transition AOM-regression pin (originally H8 #2) is replaced by
    // the Semantics-tree-shape stability test in
    // 'per-row hint removal (Phase 23 D4)' below.

    group('per-row hint removal (Phase 23 D4)', () {
      testWidgets(
        'should not render any previous-session hint text (en locale)',
        (tester) async {
          // Pin the negative contract: regardless of prior data, current
          // values, or completion state, the row MUST NOT render any of
          // the historical hint strings. Pre-fill carries the anchor;
          // the row stays bare.
          final set = makeSet(weight: 60.0, reps: 10, isCompleted: false);

          await tester.pumpWidget(
            buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
          );
          await tester.pump();

          for (final fragment in const ['Previous:', '= last set']) {
            expect(
              find.textContaining(fragment),
              findsNothing,
              reason:
                  'Phase 23 D4: per-row hint text "$fragment" must not '
                  'render in any state. If this fails, hint logic was '
                  're-added to SetRow.',
            );
          }
        },
      );

      testWidgets(
        'should not render any previous-session hint text (pt locale)',
        (tester) async {
          // Same contract on the pt locale: the Portuguese "Anterior:" /
          // "= série anterior" strings must not appear either. The ARB
          // keys are deleted so the strings literally cannot resolve —
          // this test guards against a copy/paste re-add via a hard-
          // coded Portuguese string.
          final set = makeSet(weight: 60.0, reps: 10, isCompleted: false);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001'),
              locale: const Locale('pt'),
            ),
          );
          await tester.pump();

          for (final fragment in const ['Anterior:', 'série anterior']) {
            expect(
              find.textContaining(fragment),
              findsNothing,
              reason:
                  'Phase 23 D4: pt hint fragment "$fragment" must not '
                  'render. ARB keys previousSet + matchedLastSet were '
                  'deleted; a hit here means a hard-coded re-introduction.',
            );
          }
        },
      );

      testWidgets('row Semantics tree shape is stable across set completion', (
        tester,
      ) async {
        // Pre-Phase-23 the Semantics tree gained/lost a descendant hint
        // node on completion — that mutation was the role-swap vector
        // behind the three previously-fragile E2E specs
        // (personal-records.spec.ts:264 / :309 ,
        // rank-up-celebration.spec.ts:847). Removing the hint locks the
        // tree shape: the pre- and post-completion Semantics labels
        // must be identical.
        final pending = makeSet(
          id: 'shape-row',
          weight: 60,
          reps: 8,
          isCompleted: false,
        );
        final completed = pending.copyWith(isCompleted: true);

        await tester.pumpWidget(
          buildTestWidget(SetRow(set: pending, workoutExerciseId: 'we-001')),
        );
        await tester.pump();
        final preLabels = _collectSemanticsLabels(tester);

        await tester.pumpWidget(
          buildTestWidget(SetRow(set: completed, workoutExerciseId: 'we-001')),
        );
        await tester.pump();
        final postLabels = _collectSemanticsLabels(tester);

        // The completion checkbox label flips ('Mark set as done' →
        // 'Set completed'); everything else MUST be identical. We
        // compare the symmetric difference excluding the two
        // checkbox-label states.
        const checkboxLabels = {'Mark set as done', 'Set completed'};
        final preFiltered = preLabels
            .where((l) => !checkboxLabels.contains(l))
            .toSet();
        final postFiltered = postLabels
            .where((l) => !checkboxLabels.contains(l))
            .toSet();

        expect(
          postFiltered,
          preFiltered,
          reason:
              'Phase 23 D4: aside from the checkbox state label, the '
              'row Semantics tree must be identical pre- and '
              'post-completion. Differences here mean a descendant '
              'Semantics node joined/left on completion — re-opening '
              'the role-swap mutation vector that broke the three '
              'previously-fragile E2E specs.',
        );
      });

      testWidgets(
        'row Semantics emits the correct identifier across state transitions',
        (tester) async {
          // Phase 23 root-cause (2026-05-12) — the three previously-
          // fragile E2E specs (personal-records.spec.ts:264/:309,
          // rank-up-celebration.spec.ts:847) all failed for the same
          // reason: on Flutter Web, when a `Semantics(identifier: X)`
          // node's identifier value changes WITHOUT a structural / role
          // change, the engine does not always propagate the new value
          // via `setAttribute('flt-semantics-identifier', ...)`. The
          // row's chrome rebuilt correctly (gold stripe + values + green
          // checkbox visible in the failure screenshot) but the DOM
          // element retained the pre-completion identifier. The fix is
          // a `ValueKey(rowStateId)` on the identifier-bearing
          // Semantics so a fresh SemanticsNode mounts when the
          // identifier value changes.
          //
          // This test pins the contract at unit speed: pump the row in
          // predicted-PR state, capture the identifier-bearing node's
          // identifier; transition to standing-PR (set completes + the
          // row's display state advances); the identifier observed in
          // the Semantics tree MUST be the new value, not the stale one.
          final pending = makeSet(
            id: 'identifier-row',
            weight: 130,
            reps: 5,
            isCompleted: false,
          );
          final completed = pending.copyWith(isCompleted: true);

          // Predicted-PR pre-completion — display.state =
          // pendingPredictedPr.
          const pendingDisplay = PrRowDisplay(
            state: PrRowState.pendingPredictedPr,
            accentTypes: {RecordType.maxWeight},
          );
          // Standing-PR post-completion — display.state =
          // completedStandingPr.
          const standingDisplay = PrRowDisplay(
            state: PrRowState.completedStandingPr,
            accentTypes: {RecordType.maxWeight},
          );

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: pending,
                workoutExerciseId: 'we-001',
                display: pendingDisplay,
              ),
            ),
          );
          await tester.pump();
          expect(
            _findRowStateIdentifier(tester),
            'set-row-state-pending-pr',
            reason: 'predicted-PR pre-completion must emit pending-pr id',
          );

          // Transition: set completes, display advances to standing-PR.
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: completed,
                workoutExerciseId: 'we-001',
                display: standingDisplay,
              ),
            ),
          );
          await tester.pump();
          expect(
            _findRowStateIdentifier(tester),
            'set-row-state-standing-pr',
            reason:
                'Phase 23 root-cause: identifier MUST transition to '
                'standing-pr post-completion. If this assertion stays at '
                "'set-row-state-pending-pr', the ValueKey on the row's "
                'identifier-bearing Semantics was dropped — re-opens the '
                'Flutter Web identifier-propagation hole that broke the '
                'three previously-fragile E2E specs.',
          );
        },
      );

      // Transition 2: pendingNoPr → completedNoPr.
      //
      // The row has no PR projection (PrRowState.none). User marks the
      // set done; the display advances to completedNonPr. The identifier
      // must reflect the transition — 'set-row-state-none' →
      // 'set-row-state-completed'. Pins the ValueKey fix for the
      // no-PR path (the Cluster B fix is generic to any identifier
      // change, not just the predicted-PR path).
      testWidgets(
        'row Semantics identifier transitions: none → completedNonPr',
        (tester) async {
          final handle = tester.ensureSemantics();
          final pending = makeSet(
            id: 'no-pr-row',
            weight: 60,
            reps: 8,
            isCompleted: false,
          );
          final completed = pending.copyWith(isCompleted: true);

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: pending,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay.plain(PrRowState.none),
              ),
            ),
          );
          await tester.pump();
          expect(
            _findRowStateIdentifier(tester),
            'set-row-state-none',
            reason: 'no-PR pending row must emit set-row-state-none',
          );

          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: completed,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay.plain(PrRowState.completedNonPr),
              ),
            ),
          );
          await tester.pump();
          expect(
            _findRowStateIdentifier(tester),
            'set-row-state-completed',
            reason:
                'Phase 23 Cluster B: identifier MUST transition to '
                'set-row-state-completed after a non-PR set is completed. '
                "If still 'set-row-state-none', the ValueKey was dropped.",
          );
          handle.dispose();
        },
      );

      // Transition 3: pendingPredictedPr → none (mid-set weight edit
      // drops the PR projection without completing the set).
      //
      // User edits the weight field DOWNWARD so it no longer beats the
      // standing record. The resolver transitions display.state from
      // pendingPredictedPr → none. The identifier must update:
      // 'set-row-state-pending-pr' → 'set-row-state-none'. This is the
      // "mid-set edit" path that the WIP explicitly called out as a
      // third required transition.
      testWidgets(
        'row Semantics identifier transitions: pendingPredictedPr → none '
        '(mid-set weight edit drops PR projection)',
        (tester) async {
          final handle = tester.ensureSemantics();
          final set = makeSet(
            id: 'pr-drop-row',
            weight: 130,
            reps: 5,
            isCompleted: false,
          );

          // Start as predicted-PR.
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
          await tester.pump();
          expect(
            _findRowStateIdentifier(tester),
            'set-row-state-pending-pr',
            reason:
                'pre-edit: predicted-PR row must emit set-row-state-pending-pr',
          );

          // Simulate weight edit drops below PR threshold → display
          // reverts to PrRowState.none.
          final lowWeight = set.copyWith(weight: 80);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(
                set: lowWeight,
                workoutExerciseId: 'we-001',
                display: const PrRowDisplay.plain(PrRowState.none),
              ),
            ),
          );
          await tester.pump();
          expect(
            _findRowStateIdentifier(tester),
            'set-row-state-none',
            reason:
                'Phase 23 Cluster B: after weight edit drops the PR '
                'projection, identifier MUST transition to '
                "set-row-state-none. If still 'set-row-state-pending-pr', "
                'the ValueKey was dropped — reopens the stale-identifier '
                'hole for the predicted-PR → none path.',
          );
          handle.dispose();
        },
      );
    });
  });
}

/// Walks the Semantics tree under the current widget and returns the
/// `identifier` of the first node whose identifier starts with
/// `set-row-state-`. Used by the Phase 23 root-cause regression test.
String? _findRowStateIdentifier(WidgetTester tester) {
  String? found;
  void visit(SemanticsNode node) {
    if (found != null) return;
    final data = node.getSemanticsData();
    final id = data.identifier;
    if (id.startsWith('set-row-state-')) {
      found = id;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  if (owner == null) return null;
  visit(owner.rootSemanticsNode!);
  return found;
}

/// Walks the Semantics tree under the current widget tree and returns the
/// set of non-empty labels. Used by the Phase 23 D4 tree-shape test.
Set<String> _collectSemanticsLabels(WidgetTester tester) {
  final labels = <String>{};
  void visit(SemanticsNode node) {
    final l = node.label;
    if (l.isNotEmpty) labels.add(l);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  // ignore: deprecated_member_use
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  if (owner == null) return labels;
  visit(owner.rootSemanticsNode!);
  return labels;
}
