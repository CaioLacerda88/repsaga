/// Widget tests for [DiscardWorkoutCoordinator] (PR-3 / S1).
///
/// Pins the load-bearing re-entrance contract:
///   * After a cancel-mid-discard restores active-workout state, the
///     coordinator's `_isShowingDialog` flag MUST be cleared so the
///     subsequent discard tap is honored.
///
/// The coordinator's flag is private — we observe its effect by issuing
/// TWO sequential `show(...)` calls and asserting the second one re-opens
/// the dialog rather than silently no-op'ing on the re-entrance guard.
///
/// The notifier stub here returns a [Completer]-controlled future from
/// `discardWorkout()` so we can simulate "cancel during stalled DELETE":
/// the coordinator awaits the stub, the test mutates state to a non-null
/// value (mimicking `cancelLoading`'s state restoration), then resolves
/// the stub. Without the S1 fix, the second `show(...)` call short-
/// circuits on `_isShowingDialog`. With the fix, the post-await state
/// poll clears the flag and the second call opens the dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/coordinators/discard_workout_coordinator.dart';

import '../../../../../helpers/test_material_app.dart';

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

ActiveWorkoutState _makeState() {
  return ActiveWorkoutState(
    workout: Workout(
      id: 'workout-001',
      userId: 'user-001',
      name: 'Push Day',
      // Started 5 minutes ago so the discard dialog renders a non-zero
      // elapsed-duration string. The coordinator's `show` requires this.
      startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    ),
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-001',
          workoutId: 'workout-001',
          exerciseId: 'exercise-001',
          order: 0,
          exercise: _testExercise,
        ),
        sets: const [],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Stub notifier
//
// Records `discardWorkout()` calls and exposes a Completer the test
// resolves manually so the coordinator's await can be parked / released
// at deterministic checkpoints. Lets the test directly mutate `state` to
// simulate `cancelLoading` restoring the workout mid-discard (the real
// notifier path).
// ---------------------------------------------------------------------------

/// Hand-rolled stub for [ActiveWorkoutNotifier].
///
/// **PR-3 review W3 — explicit `UnimplementedError` over `noSuchMethod`.**
/// The previous version used `noSuchMethod` as the catch-all so any future
/// method added to [ActiveWorkoutNotifier] that the coordinator started
/// calling would silently no-op in the test (Object.noSuchMethod returns
/// `null`, which is then implicitly accepted by `Future<void>` returns).
/// The reviewer flagged this as a long-term correctness trap.
///
/// Every member the test does NOT exercise now throws
/// [UnimplementedError] explicitly. If a coordinator change starts calling
/// any of them, the test fails loudly with a stack trace pointing at the
/// new call instead of mysteriously passing.
///
/// Members the test DOES exercise (`build`, `discardWorkout`) are
/// implemented properly. The `simulate...` helpers are test-only hooks
/// that don't exist on the real interface.
class _StubActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _StubActiveWorkoutNotifier(this._initialState);
  final ActiveWorkoutState? _initialState;

  /// Per-call completers — one per `discardWorkout` invocation. Test can
  /// pop the most recent and resolve it after restoring state.
  final List<Completer<void>> discardCalls = [];

  @override
  Future<ActiveWorkoutState?> build() async => _initialState;

  @override
  Future<void> discardWorkout() {
    final completer = Completer<void>();
    discardCalls.add(completer);
    return completer.future;
  }

  /// Test hook: mimic `cancelLoading` restoring the active-workout state
  /// while a `discardWorkout()` future is still pending.
  void simulateCancelLoading(ActiveWorkoutState restored) {
    state = AsyncData(restored);
  }

  /// Test hook: mimic the AsyncLoading emission that fires when
  /// `discardWorkout` starts (used to put the coordinator into the
  /// awaiting state before testing recovery).
  void simulateDiscardLoading() {
    state = const AsyncLoading();
  }

  // --- Explicit "not used by this test" stubs ---------------------------
  // Each one matches a member of the [ActiveWorkoutNotifier] public API.
  // Throw on call so a future coordinator change that starts using one
  // fails loudly here instead of mysteriously passing.

  @override
  void cancelLoading() => throw UnimplementedError(
    '_StubActiveWorkoutNotifier.cancelLoading() is not stubbed for this test',
  );

  @override
  int get incompleteSetsCount => throw UnimplementedError(
    '_StubActiveWorkoutNotifier.incompleteSetsCount getter is not stubbed',
  );

  @override
  Future<void> startWorkout([String? name]) =>
      throw UnimplementedError('startWorkout is not stubbed for this test');

  @override
  Future<void> startFromRoutine(RoutineStartConfig config) =>
      throw UnimplementedError('startFromRoutine is not stubbed for this test');

  @override
  Future<void> renameWorkout(String name) =>
      throw UnimplementedError('renameWorkout is not stubbed for this test');

  @override
  Future<void> addExercise(Exercise exercise) =>
      throw UnimplementedError('addExercise is not stubbed for this test');

  @override
  Future<void> removeExercise(String workoutExerciseId) =>
      throw UnimplementedError('removeExercise is not stubbed for this test');

  @override
  Future<void> restoreExercise(String workoutExerciseId) =>
      throw UnimplementedError('restoreExercise is not stubbed for this test');

  @override
  Future<void> addSet(
    String workoutExerciseId, {
    double? defaultWeight,
    int? defaultReps,
  }) => throw UnimplementedError('addSet is not stubbed for this test');

  @override
  Future<void> updateSet(
    String workoutExerciseId,
    String setId, {
    double? weight,
    int? reps,
    int? rpe,
    SetType? setType,
    String? notes,
  }) => throw UnimplementedError('updateSet is not stubbed for this test');

  @override
  Future<void> propagateWeight(
    String workoutExerciseId,
    String fromSetId,
    double oldWeight,
    double newWeight,
  ) => throw UnimplementedError('propagateWeight is not stubbed for this test');

  @override
  Future<void> completeSet(String workoutExerciseId, String setId) =>
      throw UnimplementedError('completeSet is not stubbed for this test');

  @override
  Future<void> deleteSet(String workoutExerciseId, String setId) =>
      throw UnimplementedError('deleteSet is not stubbed for this test');

  @override
  Future<void> restoreSet(String workoutExerciseId, ExerciseSet deletedSet) =>
      throw UnimplementedError('restoreSet is not stubbed for this test');

  @override
  Future<void> copyLastSet(String workoutExerciseId, String setId) =>
      throw UnimplementedError('copyLastSet is not stubbed for this test');

  @override
  Future<void> fillRemainingSets(String workoutExerciseId) =>
      throw UnimplementedError(
        'fillRemainingSets is not stubbed for this test',
      );

  @override
  Future<void> reorderExercise(String workoutExerciseId, int direction) =>
      throw UnimplementedError('reorderExercise is not stubbed for this test');

  @override
  Future<void> swapExercise(String workoutExerciseId, Exercise newExercise) =>
      throw UnimplementedError('swapExercise is not stubbed for this test');

  @override
  Future<FinishWorkoutResult?> finishWorkout({String? notes}) =>
      throw UnimplementedError('finishWorkout is not stubbed for this test');

  @override
  CelebrationQueueResult? consumeLastCelebration() => throw UnimplementedError(
    'consumeLastCelebration is not stubbed for this test',
  );
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Builds a minimal MaterialApp + Scaffold so the coordinator can show a
/// dialog. The hosting widget exposes a button that, when tapped, invokes
/// `coordinator.show(context, ref, state)` so the test drives the
/// coordinator through realistic context plumbing.
class _Harness extends ConsumerStatefulWidget {
  const _Harness({super.key, required this.coordinator, required this.state});

  final DiscardWorkoutCoordinator coordinator;
  final ActiveWorkoutState state;

  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  /// Captured BuildContext + WidgetRef so a test can call
  /// `harnessKey.currentState!.openDiscard()` directly even when a modal
  /// dialog is on-screen (and would otherwise eat taps on the button below
  /// it). Required for the C1 race-pin test where dialog #2 covers the
  /// button at the moment we want to attempt opening dialog #3.
  late BuildContext _ctx;

  void openDiscard() {
    widget.coordinator.show(_ctx, ref, widget.state);
  }

  @override
  Widget build(BuildContext context) {
    _ctx = context;
    // Mirror the production wiring: every state change is fed into the
    // coordinator so it can drop the re-entrance guard the moment
    // cancelLoading restores state mid-discard (PR-3 S1).
    ref.listen<AsyncValue<ActiveWorkoutState?>>(activeWorkoutProvider, (
      _,
      next,
    ) {
      widget.coordinator.notifyStateChanged(next);
    });
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: openDiscard,
          child: const Text('open-discard'),
        ),
      ),
    );
  }
}

Widget _build({
  required _StubActiveWorkoutNotifier notifier,
  required DiscardWorkoutCoordinator coordinator,
  required ActiveWorkoutState state,
  GlobalKey<_HarnessState>? harnessKey,
}) {
  return ProviderScope(
    overrides: [activeWorkoutProvider.overrideWith(() => notifier)],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      // Stub the GoRouter routing so `context.go('/home')` doesn't blow
      // up if a code path reaches it. We never expect to hit it in the
      // S1 test because the cancel path returns before navigation.
      builder: (context, child) => InheritedGoRouter(
        goRouter: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => child!),
            GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
          ],
        ),
        child: child!,
      ),
      home: _Harness(key: harnessKey, coordinator: coordinator, state: state),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DiscardWorkoutCoordinator — PR-3 S1 re-entrance fix', () {
    testWidgets(
      're-entrance flag is cleared while discardWorkout() is still in flight, '
      'so the next discard tap re-opens the dialog WITHOUT waiting for the '
      'held network (S1)',
      (tester) async {
        final initialState = _makeState();
        final notifier = _StubActiveWorkoutNotifier(initialState);
        final coordinator = DiscardWorkoutCoordinator();

        await tester.pumpWidget(
          _build(
            notifier: notifier,
            coordinator: coordinator,
            state: initialState,
          ),
        );
        // Drain the AsyncNotifier build microtask so `state.value` is
        // populated before the first show.
        await tester.pump();
        await tester.pump();

        // 1. Open the discard dialog.
        await tester.tap(find.text('open-discard'));
        await tester.pumpAndSettle();
        expect(find.text('Discard Workout?'), findsOneWidget);

        // 2. Confirm the discard. The stub `discardWorkout()` returns a
        //    pending completer — the coordinator's await is parked.
        await tester.tap(find.text('Discard'));
        await tester.pump();
        expect(notifier.discardCalls, hasLength(1));

        // 3a. Simulate the AsyncLoading transition that production's
        //     `discardWorkout` emits before the network call. This drives
        //     the listener so the post-restore transition fires a real
        //     state change (not a same-value no-op).
        notifier.simulateDiscardLoading();
        await tester.pump();

        // 3b. Simulate cancelLoading restoring active-workout state mid-
        //     discard. In production this happens because `cancelLoading`
        //     on the notifier emits AsyncData(restored) immediately while
        //     the still-in-flight DELETE is held. The coordinator's await
        //     on `discardWorkout()` stays parked. The screen's ref.listen
        //     feeds the new state into the coordinator, which clears its
        //     re-entrance guard immediately — without waiting for the
        //     held network.
        notifier.simulateCancelLoading(initialState);
        await tester.pump();

        // 4. Tap "open-discard" AGAIN — pre-fix this is a silent no-op
        //    on `_isShowingDialog` until the held network resolves.
        //    Post-fix the state-listener cleared the flag in step 3, so
        //    the dialog re-opens cleanly EVEN THOUGH the first discard
        //    is still parked.
        expect(
          notifier.discardCalls.first.isCompleted,
          isFalse,
          reason:
              'Sanity check: the first discardWorkout() must still be '
              'parked when we tap discard again — that is the load-bearing '
              'condition for the S1 fix.',
        );
        await tester.tap(find.text('open-discard'));
        await tester.pumpAndSettle();
        expect(
          find.text('Discard Workout?'),
          findsOneWidget,
          reason:
              'PR-3 S1: after cancel-mid-discard restored the workout, the '
              're-entrance flag MUST be cleared via the state-listener path '
              'so the next discard attempt re-opens the dialog without '
              'waiting for the held network. Pre-fix the second tap '
              'silently no-op\'d on `_isShowingDialog`. See BUGS.md '
              'PR-3 / S1.',
        );

        // 5. Clean up: dismiss the second dialog, then release the held
        //    first call so its `finally` runs and the first coroutine
        //    exits cleanly.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        notifier.discardCalls.first.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'first call\'s finally MUST NOT release the re-entrance guard while a '
      'second dialog is still open — a third tap during that window must be '
      'rejected (PR-3 review C1: race window between stalled-call cleanup '
      'and second-dialog lifetime)',
      (tester) async {
        // Race shape (pre-fix):
        //   1. First show() opens dialog #1, user confirms → notifier
        //      `discardWorkout()` is awaited and stalls.
        //   2. `notifyStateChanged` fires (cancelLoading restored state) and
        //      clears `_isShowingDialog`.
        //   3. Second show() runs, opens dialog #2 — flips
        //      `_isShowingDialog` back to true.
        //   4. First call's stalled completer resolves. Its inner finally
        //      runs, then control returns to the outer `finally` which
        //      sets `_isShowingDialog = false` — UNCONDITIONALLY.
        //   5. While dialog #2 is still on-screen, a third tap now passes
        //      the guard check and stacks a third dialog.
        //
        // The fix uses a per-call generation counter so only the LATEST
        // owner of the flag clears it on cleanup. This test pins that
        // contract: assert step 5 yields exactly ONE dialog (not two).
        final initialState = _makeState();
        final notifier = _StubActiveWorkoutNotifier(initialState);
        final coordinator = DiscardWorkoutCoordinator();
        final harnessKey = GlobalKey<_HarnessState>();

        await tester.pumpWidget(
          _build(
            notifier: notifier,
            coordinator: coordinator,
            state: initialState,
            harnessKey: harnessKey,
          ),
        );
        await tester.pump();
        await tester.pump();

        // 1. Open dialog #1 and confirm — `discardWorkout()` is now parked.
        //    Use the harness method instead of tapping the button so this
        //    test is symmetric with steps 3 and 5 below where the button
        //    is hidden behind a modal dialog.
        harnessKey.currentState!.openDiscard();
        await tester.pumpAndSettle();
        expect(find.text('Discard Workout?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pump();
        expect(notifier.discardCalls, hasLength(1));

        // 2. Drive a state-restore cycle so the listener clears the guard.
        notifier.simulateDiscardLoading();
        await tester.pump();
        notifier.simulateCancelLoading(initialState);
        await tester.pump();

        // 3. Open dialog #2 — guard was cleared in step 2, so this opens.
        harnessKey.currentState!.openDiscard();
        await tester.pumpAndSettle();
        expect(
          find.text('Discard Workout?'),
          findsOneWidget,
          reason: 'Dialog #2 should be on-screen at this point.',
        );

        // 4. Resolve the FIRST call's parked completer. Its inner finally
        //    + outer finally now run, while dialog #2 is still up. Pre-fix
        //    the outer finally sets `_isShowingDialog = false` even though
        //    the second call still owns the open dialog.
        notifier.discardCalls.first.complete();
        await tester.pump();
        await tester.pump();

        // 5. Attempt to open dialog #3 from inside the modal. Pre-fix
        //    `_isShowingDialog` was just cleared in step 4, so the guard
        //    permits this call and a SECOND "Discard Workout?" dialog
        //    stacks on top of dialog #2 → `findsNWidgets(2)`. Post-fix the
        //    generation counter means the stalled call's finally is a
        //    no-op (it's no longer the latest owner), so this call hits
        //    the guard and is silently rejected.
        harnessKey.currentState!.openDiscard();
        await tester.pumpAndSettle();
        expect(
          find.text('Discard Workout?'),
          findsOneWidget,
          reason:
              'PR-3 review C1: a stalled first call MUST NOT release the '
              're-entrance guard while a second dialog is still open. The '
              'generation counter ensures only the latest call\'s finally '
              'clears the flag, so a third tap during the second dialog\'s '
              'lifetime is rejected (would otherwise stack as findsNWidgets(2)).',
        );

        // Cleanup: dismiss dialog #2.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'concurrent show() calls are still de-duped while a dialog is up '
      '(re-entrance guard works for stacked invocations)',
      (tester) async {
        // Pin the original guard contract — the S1 fix MUST NOT regress
        // it. Two rapid taps on the discard button should still produce
        // exactly ONE dialog.
        final initialState = _makeState();
        final notifier = _StubActiveWorkoutNotifier(initialState);
        final coordinator = DiscardWorkoutCoordinator();

        await tester.pumpWidget(
          _build(
            notifier: notifier,
            coordinator: coordinator,
            state: initialState,
          ),
        );
        await tester.pump();
        await tester.pump();

        // First tap opens the dialog.
        await tester.tap(find.text('open-discard'));
        await tester.pump();
        // Second tap fires before the first dialog is even painted — the
        // guard MUST short-circuit it.
        await tester.tap(find.text('open-discard'));
        await tester.pumpAndSettle();

        expect(
          find.text('Discard Workout?'),
          findsOneWidget,
          reason:
              'The re-entrance guard must still prevent stacked dialogs '
              'when two invocations race during the same lifecycle.',
        );

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );
  });
}
