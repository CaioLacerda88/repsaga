/// Phase 23 D1 — rest-overlay chrome visibility contract.
///
/// When the rest-timer overlay is visible the FAB (`AddExerciseFab`) and
/// the `FinishBottomBar` must NOT render. The AppBar's discard X stays so
/// the user can bail mid-rest (pin in
/// `active_workout_appbar_discard_during_rest_test.dart`). When the rest
/// timer stops, both surfaces must reappear immediately on the next frame.
///
/// **Why a fresh test file:** scope is tight and the failure mode is
/// distinct — a single fail here says "chrome leaks above the rest scrim,"
/// which is exactly what the user reported in the 2026-05-12 device walk
/// through. The sibling `active_workout_appbar_discard_during_rest_test`
/// owns the inverse: chrome that MUST stay reachable.
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
import 'package:repsaga/features/workouts/ui/widgets/add_exercise_fab.dart';
import 'package:repsaga/features/workouts/ui/widgets/finish_bottom_bar.dart';

import '../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

ActiveWorkoutState _activeStateWithOneSet() {
  final now = DateTime.now().toUtc();
  return ActiveWorkoutState(
    workout: Workout(
      id: 'workout-001',
      userId: 'user-001',
      name: 'Push Day',
      startedAt: now,
      isActive: true,
      createdAt: now,
    ),
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-001',
          workoutId: 'workout-001',
          exerciseId: 'exercise-001',
          order: 1,
          exercise: _testExercise,
        ),
        sets: [
          ExerciseSet(
            id: 'set-1',
            workoutExerciseId: 'we-001',
            setNumber: 1,
            reps: 10,
            weight: 60.0,
            isCompleted: false,
            setType: SetType.working,
            createdAt: now,
          ),
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _FixedActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _FixedActiveWorkoutNotifier(this._state);
  final ActiveWorkoutState _state;

  @override
  Future<ActiveWorkoutState?> build() async => _state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controllable rest-timer notifier. `build()` returns the [_initial] state
/// (active or null); the test can later call `stop()` to flip the timer
/// off and observe the chrome reappear without invoking real `Timer`
/// machinery.
class _ControllableRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  _ControllableRestTimerNotifier(this._initial);
  final RestTimerState? _initial;

  @override
  RestTimerState? build() => _initial;

  @override
  void stop() {
    state = null;
  }

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

Widget _buildScreen({
  required ActiveWorkoutState state,
  required _ControllableRestTimerNotifier restTimerNotifier,
}) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(state),
      ),
      restTimerProvider.overrideWith(() => restTimerNotifier),
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

void main() {
  group('ActiveWorkoutScreen — rest-overlay chrome visibility (Phase 23 D1)', () {
    testWidgets('should hide AddExerciseFab when rest timer is active', (
      tester,
    ) async {
      final restTimerNotifier = _ControllableRestTimerNotifier(
        const RestTimerState(
          totalSeconds: 90,
          remainingSeconds: 90,
          isActive: true,
          exerciseName: 'Bench Press',
        ),
      );
      await tester.pumpWidget(
        _buildScreen(
          state: _activeStateWithOneSet(),
          restTimerNotifier: restTimerNotifier,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(AddExerciseFab),
        findsNothing,
        reason:
            'Phase 23 D1: while the rest timer is active the FAB must NOT '
            'render — it would otherwise paint above the scrim per Scaffold '
            'slot ordering. Failing here means the `chromeVisible` gate in '
            '_ActiveWorkoutBody.build was reverted.',
      );
    });

    testWidgets('should hide FinishBottomBar when rest timer is active', (
      tester,
    ) async {
      final restTimerNotifier = _ControllableRestTimerNotifier(
        const RestTimerState(
          totalSeconds: 90,
          remainingSeconds: 90,
          isActive: true,
          exerciseName: 'Bench Press',
        ),
      );
      await tester.pumpWidget(
        _buildScreen(
          state: _activeStateWithOneSet(),
          restTimerNotifier: restTimerNotifier,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(FinishBottomBar),
        findsNothing,
        reason:
            'Phase 23 D1: while the rest timer is active the FinishBottomBar '
            'must NOT render — same chrome-leak rationale as the FAB above.',
      );
    });

    testWidgets('should restore FAB and Finish after rest timer stops', (
      tester,
    ) async {
      // Start with rest ACTIVE so the chrome is hidden.
      final restTimerNotifier = _ControllableRestTimerNotifier(
        const RestTimerState(
          totalSeconds: 90,
          remainingSeconds: 90,
          isActive: true,
          exerciseName: 'Bench Press',
        ),
      );
      await tester.pumpWidget(
        _buildScreen(
          state: _activeStateWithOneSet(),
          restTimerNotifier: restTimerNotifier,
        ),
      );
      await tester.pump();
      await tester.pump();

      // Pre-condition: chrome is hidden.
      expect(find.byType(AddExerciseFab), findsNothing);
      expect(find.byType(FinishBottomBar), findsNothing);

      // Stop the rest timer — same path as user-tap on the scrim.
      restTimerNotifier.stop();
      await tester.pump();

      expect(
        find.byType(AddExerciseFab),
        findsOneWidget,
        reason:
            'Phase 23 D1: stopping the rest timer must restore the FAB on the '
            'next frame. Reactivity is driven by `ref.watch(restTimerProvider)` '
            'in `ActiveWorkoutScreen.build` — if this fails, that watch was '
            'replaced with a one-shot `ref.read`.',
      );
      expect(
        find.byType(FinishBottomBar),
        findsOneWidget,
        reason:
            'Phase 23 D1: stopping the rest timer must restore the bottom bar '
            'on the next frame for the same reason as the FAB above.',
      );
    });

    testWidgets('should keep AppBar discard X reachable during rest', (
      tester,
    ) async {
      // This re-asserts the contract pinned in
      // `active_workout_appbar_discard_during_rest_test.dart`. Re-confirming
      // here locally so the chrome-visibility refactor cannot accidentally
      // hide the AppBar slot too — the AppBar's discard-X is the in-rest
      // exit affordance and MUST keep painting above the rest scrim.
      final restTimerNotifier = _ControllableRestTimerNotifier(
        const RestTimerState(
          totalSeconds: 90,
          remainingSeconds: 90,
          isActive: true,
          exerciseName: 'Bench Press',
        ),
      );
      await tester.pumpWidget(
        _buildScreen(
          state: _activeStateWithOneSet(),
          restTimerNotifier: restTimerNotifier,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byTooltip('Discard workout'),
        findsOneWidget,
        reason:
            'Phase 23 D1 trade-off: the FAB + FinishBottomBar hide on rest, '
            'but the AppBar discard-X is the SOLE in-rest exit affordance '
            'and must stay visible + reachable. If this fails, the gate was '
            'over-broad and also hid the AppBar.',
      );
    });
  });
}
