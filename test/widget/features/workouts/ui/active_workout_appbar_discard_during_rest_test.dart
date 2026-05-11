/// Widget regression pin for the PR-2 C3 z-order contract:
///
/// The rest-timer overlay is now painted INSIDE the Scaffold's `body` slot
/// (see `active_workout_screen.dart` _ActiveWorkoutBody.build). The
/// reviewer's one-question check on PR #198 surfaced a real worry: the
/// outer `GestureDetector` of `RestTimerOverlay` uses
/// `HitTestBehavior.opaque`, which historically swallowed pointer events
/// across the whole screen when the overlay sat at the Stack root. With
/// the overlay constrained to the body slot, the AppBar paints ON TOP of
/// it (Scaffold's standard slot order: appBar > body > snackbar), and a
/// tap on the AppBar's discard-X must still reach the IconButton.
///
/// This test pumps the full `ActiveWorkoutScreen` with the rest-timer
/// notifier seeded into an active state, taps the AppBar discard button,
/// and asserts that the discard confirmation dialog appears. The dialog
/// is the user-visible signal that the tap reached the handler — if the
/// rest-timer scrim were stealing the tap, no dialog would appear.
///
/// **Why a fresh test file (vs. extending tap-target tests):** this is a
/// hit-test / z-order contract, not a tap-target-size contract. Keeping
/// it isolated makes the failure mode obvious — if this file's lone test
/// fails, the rest-timer overlay is intercepting AppBar taps again.
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
import 'package:repsaga/features/workouts/ui/widgets/rest_timer_overlay.dart';

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

/// Rest-timer notifier seeded ACTIVE so the screen renders the overlay.
///
/// Bypasses the real `start()` / `Timer.periodic` machinery — this is a
/// unit-level pin on the Scaffold slot ordering, not a timer-tick test.
/// The state is constant (90s of 90s remaining) and `isActive: true` so
/// `restTimerProvider != null` in `ActiveWorkoutScreen.build` and
/// `_ActiveWorkoutBody` mounts the `RestTimerOverlay` inside the body slot.
class _ActiveRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  @override
  RestTimerState? build() => const RestTimerState(
    totalSeconds: 90,
    remainingSeconds: 90,
    isActive: true,
    exerciseName: 'Bench Press',
  );

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

Widget _buildScreenWithRestTimerActive(ActiveWorkoutState state) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(state),
      ),
      restTimerProvider.overrideWith(() => _ActiveRestTimerNotifier()),
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
// Test
// ---------------------------------------------------------------------------

void main() {
  group(
    'ActiveWorkoutScreen — AppBar reachability during rest timer (PR-2 C3)',
    () {
      testWidgets(
        'tap on AppBar discard-X opens the discard dialog while rest-timer '
        'overlay is up (overlay does not steal the tap)',
        (tester) async {
          await tester.pumpWidget(
            _buildScreenWithRestTimerActive(_activeStateWithOneSet()),
          );
          // Two pumps: first to settle the AsyncNotifier's build(), second
          // to settle the resulting widget tree (PopScope + Scaffold + body).
          await tester.pump();
          await tester.pump();

          // Sanity check: the rest-timer overlay is actually rendered. If
          // it's missing, this test would vacuously pass (the AppBar would
          // be reachable trivially), so pin its presence first.
          expect(
            find.byType(RestTimerOverlay),
            findsOneWidget,
            reason:
                'Pre-condition: rest-timer overlay must be mounted. '
                'If the overlay is gone, the test cannot prove the AppBar '
                'is still reachable WHILE it is up.',
          );

          // Tap the AppBar discard button. The button is in the AppBar
          // leading slot, which paints AFTER (above) the body slot in
          // Scaffold's standard ordering. The rest-timer scrim lives
          // inside the body slot post-PR-2 C3, so it must NOT intercept
          // this tap. If it does, the discard dialog never opens.
          await tester.tap(find.byTooltip('Discard workout'));
          await tester.pumpAndSettle();

          // The DiscardWorkoutDialog appearing is the user-visible signal
          // that the tap reached the IconButton's onPressed handler. If
          // the rest-timer overlay's `HitTestBehavior.opaque` GestureDetector
          // had caught the tap first, this assertion would fail.
          expect(
            find.text('Discard Workout?'),
            findsOneWidget,
            reason:
                'AppBar discard tap must reach its IconButton even when '
                'the rest-timer overlay is mounted. PR-2 C3 moved the '
                'overlay INTO the Scaffold body slot — the AppBar paints '
                'above the body, so its hit-tests must win. If this fails, '
                'the overlay has regressed back to a Stack-root sibling '
                'that swallows AppBar pointer events.',
          );

          // Clean up — dismiss the dialog so the coordinator's
          // `_isShowingDialog` flag resets and downstream tests do not
          // leak state.
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        },
      );
    },
  );
}
