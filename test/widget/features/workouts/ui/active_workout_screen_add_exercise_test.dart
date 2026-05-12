/// Phase 23 D6 — `addExercise` auto-seeds set 1.
///
/// Unit-level coverage of the seed-value computation lives in
/// `test/unit/features/workouts/providers/active_workout_notifier_test.dart`
/// → `addExercise auto-seed (Phase 23 D6)` group. This file pins the
/// widget-level contract: when `addExercise` runs, the exercise card
/// renders with exactly ONE pre-filled set row immediately — no
/// intermediate empty state, no spinner.
///
/// **Why not drive the full picker → pick → seed flow:**
/// `ExercisePickerSheet` is an `Overlay`-mounted modal bottom sheet
/// with its own async provider chain. Pumping that path adds 200+
/// lines of stub plumbing for ~zero marginal coverage over a focused
/// pump that exercises the notifier directly. The E2E suite covers
/// the full picker-driven flow; this widget test owns the
/// `addExercise → screen renders pre-filled set` contract.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/active_workout_screen.dart';
import 'package:repsaga/features/workouts/ui/widgets/set_row.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/test_material_app.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class _FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

final _benchPress = Exercise(
  id: 'exercise-bench',
  name: 'Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

Workout _workout() {
  final now = DateTime.now().toUtc();
  return Workout(
    id: 'workout-001',
    userId: 'user-001',
    name: 'Push Day',
    startedAt: now,
    isActive: true,
    createdAt: now,
  );
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

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeActiveWorkoutState());
  });

  group('ActiveWorkoutScreen — addExercise auto-seeds set 1 (Phase 23 D6)', () {
    testWidgets(
      'should render exercise card with one pre-filled set immediately '
      'after addExercise with prior session data',
      (tester) async {
        // Seed the repo with prior-session data for bench press —
        // 100 kg × 8. Pre-Phase-23 the new exercise card rendered empty;
        // Post-Phase-23 it MUST render one row with those values.
        final mockRepo = _MockWorkoutRepository();
        final mockStorage = _MockWorkoutLocalStorage();

        when(
          () => mockStorage.loadActiveWorkout(),
        ).thenReturn(ActiveWorkoutState(workout: _workout(), exercises: []));
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});

        final prior = ExerciseSet(
          id: 'prev-1',
          workoutExerciseId: 'we-prev',
          setNumber: 1,
          weight: 100,
          reps: 8,
          setType: SetType.working,
          isCompleted: true,
          createdAt: DateTime(2026, 5, 1),
        );
        when(() => mockRepo.getLastWorkoutSets(any())).thenAnswer(
          (_) async => {
            'exercise-bench': [prior],
          },
        );

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(mockRepo),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
            restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
            profileProvider.overrideWith(() => _KgProfileNotifier()),
            exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
            lastWorkoutSetsProvider.overrideWith(
              (ref, _) => Future.value({
                'exercise-bench': [prior],
              }),
            ),
            elapsedTimerProvider.overrideWith(
              (ref, startedAt) => Stream.value(const Duration(minutes: 5)),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ActiveWorkoutScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Pre-condition: workout has zero exercises so far.
        expect(find.byType(SetRow), findsNothing);

        // Drive addExercise — the production code path triggered by
        // the FAB / picker is exactly `notifier.addExercise(exercise)`.
        // We invoke it directly to avoid pumping ExercisePickerSheet's
        // overlay (which would need additional provider stubs and
        // contributes nothing to the post-add contract pinned here).
        await container
            .read(activeWorkoutProvider.notifier)
            .addExercise(_benchPress);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Post-condition: exactly one SetRow renders, carrying the
        // seeded values from the prior session.
        expect(
          find.byType(SetRow),
          findsOneWidget,
          reason:
              'Phase 23 D6: addExercise must produce exactly one '
              'pre-filled set row immediately. If this fails, either '
              'the auto-seed dropped or the screen does not react to '
              'the AsyncData change.',
        );

        // The seeded weight + reps should be visible somewhere in the
        // card. WeightStepper / RepsStepper render the value as plain
        // Text. We assert on a flexible match — '100' for weight,
        // '8' for reps — which is the user-visible signal.
        expect(
          find.textContaining('100'),
          findsWidgets,
          reason:
              'Phase 23 D6: seeded weight (100 kg from prior session) '
              'must appear in the rendered SetRow.',
        );
        expect(
          find.textContaining('8'),
          findsWidgets,
          reason:
              'Phase 23 D6: seeded reps (8 from prior session) must '
              'appear in the rendered SetRow.',
        );
      },
    );

    testWidgets(
      'should render exercise card with equipment-default-filled set when '
      'no prior data exists',
      (tester) async {
        // Fallback path: empty prior data → equipment defaults.
        // Barbell + kg = 20 kg × 5 per defaultSetValues.
        final mockRepo = _MockWorkoutRepository();
        final mockStorage = _MockWorkoutLocalStorage();

        when(
          () => mockStorage.loadActiveWorkout(),
        ).thenReturn(ActiveWorkoutState(workout: _workout(), exercises: []));
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});
        when(
          () => mockRepo.getLastWorkoutSets(any()),
        ).thenAnswer((_) async => const <String, List<ExerciseSet>>{});

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(mockRepo),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
            restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
            profileProvider.overrideWith(() => _KgProfileNotifier()),
            exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
            lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
            elapsedTimerProvider.overrideWith(
              (ref, startedAt) => Stream.value(const Duration(minutes: 5)),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const ActiveWorkoutScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        await container
            .read(activeWorkoutProvider.notifier)
            .addExercise(_benchPress);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(SetRow), findsOneWidget);
        // Barbell equipment defaults = 20 kg × 5.
        expect(find.textContaining('20'), findsWidgets);
        expect(find.textContaining('5'), findsWidgets);
      },
    );
  });
}
