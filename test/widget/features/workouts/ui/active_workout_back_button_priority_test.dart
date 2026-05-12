/// Phase 23 D2/D3 — back-press priority chain.
///
/// Pre-Phase-23 the active-workout `PopScope.onPopInvokedWithResult`
/// unconditionally routed to the discard coordinator. User on-device
/// feedback (2026-05-12) flagged that the Android back button during rest
/// opened the discard dialog instead of dismissing the rest timer — the
/// wrong mental model. Phase 23 D2 redefines the chain:
///
///   1. Rest timer active AND loading overlay NOT active → stop the rest
///      timer. Rest is the dominant on-screen affordance.
///   2. Loading overlay active → fall through to the discard coordinator
///      (D3 — loading carries its own Stop CTA, back is a reasonable
///      escape and routing here keeps the PR-3 S1 re-entrance guard
///      authoritative).
///   3. Else → discard coordinator (the historical contract).
///
/// `handlePopRoute()` on the WidgetsBinding is the test-harness analog of
/// Android's hardware back press — it walks the same route-pop chain that
/// fires PopScope callbacks. Existing tests in
/// `active_workout_popscope_test.dart` use the same hook.
library;

// ignore_for_file: invalid_use_of_internal_member
// `AsyncValue.copyWithPrevious` is @internal in Riverpod 3 but is the
// only way to simulate the AsyncLoading-with-prior-data shape that
// `ref.refresh` produces in production. Same pattern as
// `test/widget/features/weekly_plan/week_bucket_section_test.dart`.

import 'dart:async';

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

/// Notifier whose `build()` stays pending so the screen renders the
/// loading overlay branch (`asyncState.isLoading == true` while
/// `displayState` is still null on the very first emission). Used to
/// exercise the D3 fallthrough.
class _LoadingActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _LoadingActiveWorkoutNotifier(this._priorState);
  final ActiveWorkoutState _priorState;
  final _completer = Completer<ActiveWorkoutState?>();

  @override
  Future<ActiveWorkoutState?> build() => _completer.future;

  /// Manually trip the notifier into a loading state while still surfacing
  /// the prior state via `.value` (Riverpod's "loading with previous
  /// data" pattern). The screen then renders the discard-able body AND
  /// the loading overlay — exactly the D3 condition.
  void enterLoadingWithPriorData() {
    // Surface prior data via AsyncLoading-with-data: this is what
    // `ref.refresh()` produces.
    state = const AsyncLoading<ActiveWorkoutState?>().copyWithPrevious(
      AsyncData<ActiveWorkoutState?>(_priorState),
    );
  }

  void complete() {
    if (!_completer.isCompleted) _completer.complete(_priorState);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controllable rest timer — same shape as the production notifier's
/// `stop()` (sets state to null) but skips the real `Timer` machinery.
class _ControllableRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  _ControllableRestTimerNotifier(this._initial);
  final RestTimerState? _initial;

  /// Counts how many times `stop()` fired so the test can pin the
  /// idempotent-stop contract (one back press = one stop, never two).
  int stopCallCount = 0;

  @override
  RestTimerState? build() => _initial;

  @override
  void stop() {
    stopCallCount += 1;
    state = null;
  }

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

Widget _buildScreen({
  required ActiveWorkoutNotifier Function() activeOverride,
  required RestTimerNotifier Function() restOverride,
}) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(activeOverride),
      restTimerProvider.overrideWith(restOverride),
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
  group(
    'ActiveWorkoutScreen — back-press priority chain (Phase 23 D2/D3)',
    () {
      testWidgets(
        'should stop rest timer on Android back press without showing discard '
        'dialog',
        (tester) async {
          final restTimer = _ControllableRestTimerNotifier(
            const RestTimerState(
              totalSeconds: 90,
              remainingSeconds: 90,
              isActive: true,
              exerciseName: 'Bench Press',
            ),
          );
          await tester.pumpWidget(
            _buildScreen(
              activeOverride: () =>
                  _FixedActiveWorkoutNotifier(_activeStateWithOneSet()),
              restOverride: () => restTimer,
            ),
          );
          await tester.pump();
          await tester.pump();

          // Pre-condition: the screen is in the rest-active branch (D2).
          // Loading overlay must NOT be active or D3 would take over.
          expect(restTimer.stopCallCount, 0);

          // Simulate Android hardware back via the same hook the existing
          // popscope test uses (handlePopRoute fires the route-pop chain
          // that drives PopScope callbacks).
          final dynamic binding = tester.binding;
          // ignore: avoid_dynamic_calls
          await binding.handlePopRoute();
          await tester.pumpAndSettle();

          expect(
            restTimer.stopCallCount,
            1,
            reason:
                'Phase 23 D2: back-press during rest must call '
                '`restTimerProvider.notifier.stop()` exactly once. If this '
                'fails the chain is misrouted — most likely the rest-active '
                'branch was dropped and the call fell through to the discard '
                'coordinator instead.',
          );
          expect(
            find.text('Discard Workout?'),
            findsNothing,
            reason:
                'Phase 23 D2: rest-active back-press must NOT open the discard '
                'dialog. If this fails the priority chain is reversed (discard '
                'wins over rest). Verify the `if (restActive && !loadingActive)` '
                'branch in `PopScope.onPopInvokedWithResult` returns BEFORE '
                'the coordinator call.',
          );
        },
      );

      testWidgets(
        'should fall through to discard dialog when rest timer is inactive',
        (tester) async {
          await tester.pumpWidget(
            _buildScreen(
              activeOverride: () =>
                  _FixedActiveWorkoutNotifier(_activeStateWithOneSet()),
              restOverride: () => _NullRestTimerNotifier(),
            ),
          );
          await tester.pump();
          await tester.pump();

          final dynamic binding = tester.binding;
          // ignore: avoid_dynamic_calls
          await binding.handlePopRoute();
          await tester.pumpAndSettle();

          expect(
            find.text('Discard Workout?'),
            findsOneWidget,
            reason:
                'Phase 23: with no rest timer active the chain falls through to '
                'the discard coordinator — the historical contract. If this '
                'fails the `else` branch was dropped from '
                'PopScope.onPopInvokedWithResult.',
          );

          // Clean up so the coordinator guard resets.
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'should fall through to discard dialog when loading overlay is active '
        'even if rest timer is also active',
        (tester) async {
          // D3 — loading-overlay-active path. The loading overlay carries
          // its own Stop CTA (PR-1 Q1), so back-press routes to the
          // discard coordinator regardless of rest state.
          final restTimer = _ControllableRestTimerNotifier(
            const RestTimerState(
              totalSeconds: 90,
              remainingSeconds: 90,
              isActive: true,
              exerciseName: 'Bench Press',
            ),
          );
          final loadingNotifier = _LoadingActiveWorkoutNotifier(
            _activeStateWithOneSet(),
          );
          await tester.pumpWidget(
            _buildScreen(
              activeOverride: () => loadingNotifier,
              restOverride: () => restTimer,
            ),
          );
          // Complete the build() future so the screen has displayState then
          // bump back into AsyncLoading-with-prior-data (the shape produced
          // by `ref.refresh` on an AsyncNotifier — `isLoading: true` AND
          // `.value: priorState`).
          loadingNotifier.complete();
          await tester.pump();
          await tester.pump();
          loadingNotifier.enterLoadingWithPriorData();
          await tester.pump();

          final dynamic binding = tester.binding;
          // ignore: avoid_dynamic_calls
          await binding.handlePopRoute();
          // Bounded pumps instead of pumpAndSettle: the loading overlay
          // shows a CircularProgressIndicator that animates forever, so
          // pumpAndSettle never returns. 3 frames is enough to drive the
          // PopScope callback → coordinator.show → DiscardWorkoutDialog
          // route push → first paint.
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }

          expect(
            restTimer.stopCallCount,
            0,
            reason:
                'Phase 23 D3: during the loading-overlay-active branch the '
                'rest-stop short-circuit MUST NOT fire — back-press routes to '
                'the discard coordinator instead. If this fails the '
                '`&& !loadingActive` guard is missing on the rest-active '
                'branch.',
          );
          expect(
            find.text('Discard Workout?'),
            findsOneWidget,
            reason:
                'Phase 23 D3: with loading overlay active, back-press falls '
                'through to discard. Loading carries its own Stop CTA — back '
                'is a reasonable secondary escape.',
          );

          // Same bounded-pump pattern for the dismiss tap — the loading
          // overlay is still animating in the background.
          await tester.tap(find.text('Cancel'));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        },
      );

      testWidgets(
        'should stop rest timer exactly once when back press fires during rest',
        (tester) async {
          // Pin the idempotent-stop contract: one back press equals exactly
          // one `stop()` call. Without this guard a future refactor could
          // accidentally re-invoke the notifier inside a postFrameCallback
          // listener and double-stop (harmless functionally, but a hint
          // the chain has a feedback loop).
          final restTimer = _ControllableRestTimerNotifier(
            const RestTimerState(
              totalSeconds: 90,
              remainingSeconds: 90,
              isActive: true,
              exerciseName: 'Bench Press',
            ),
          );
          await tester.pumpWidget(
            _buildScreen(
              activeOverride: () =>
                  _FixedActiveWorkoutNotifier(_activeStateWithOneSet()),
              restOverride: () => restTimer,
            ),
          );
          await tester.pump();
          await tester.pump();

          final dynamic binding = tester.binding;
          // ignore: avoid_dynamic_calls
          await binding.handlePopRoute();
          // Single settle so any postFrameCallback that erroneously
          // re-fires stop() also drains here.
          await tester.pumpAndSettle();

          expect(
            restTimer.stopCallCount,
            1,
            reason:
                'Phase 23 D2: back-press must call `stop()` exactly once. A '
                'count > 1 means a state listener or postFrameCallback is '
                're-entering the stop path — silent state churn but a strong '
                'signal the priority chain has a feedback loop.',
          );
        },
      );
    },
  );
}
