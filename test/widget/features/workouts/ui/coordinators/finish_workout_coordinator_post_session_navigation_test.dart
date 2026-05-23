/// Regression test for [FinishWorkoutCoordinator]'s post-session push branch
/// (Phase 30 PR 30a).
///
/// **Bug context.** PR 30a's first cut of the post-session push branch read
/// `ref.read(workoutCountProvider).value` AFTER `await notifier.finishWorkout()`
/// to compute `priorFinishedWorkoutCount`. Because the active-workout
/// notifier transitions to `AsyncData(null)` inside `finishWorkout`, the
/// active-workout screen rebuilds + disposes the State that owns this `ref`
/// BEFORE the post-await code runs. Calling `ref.read(...)` on that
/// disposed `WidgetRef` throws:
///
/// ```
/// Bad state: Using "ref" when a widget is about to or has been unmounted
/// is unsafe. Ref relies on BuildContext, and BuildContext is unsafe to
/// use when the widget is deactivated.
/// ```
///
/// The exception fires synchronously inside the `if (shouldPushPostSession)`
/// branch BEFORE the `addPostFrameCallback` that schedules
/// `rootContext.go('/workout/finish/:id', ...)` — so the navigation never
/// happens and the URL stays on `/workout/active`. ~15 E2E tests failed
/// because of this; the page snapshot showed the active-workout screen
/// stuck behind the spinner ScafFold.
///
/// Same `ref`-lifetime hazard as `shouldShowPlanPrompt` (already documented
/// at the existing capture site above) — both reads have to happen
/// SYNCHRONOUSLY before the await.
///
/// **What this test pins.** A notifier whose `finishWorkout` flips state
/// to `AsyncData(null)` (the production behavior) + a non-zero set count
/// + a celebration queue carrying a `PersonalRecordEvent` triggers the
/// post-session push branch. The test asserts both:
///
/// 1. **Navigation succeeded** — `/workout/finish/:workoutId` reached.
///    Pre-fix this could still pass in a widget-test harness because the
///    test binding's pump cycle keeps the body Element mounted across the
///    await chain (where production unmounts it during the orchestrator's
///    saga-intro wait window). The navigation check alone is therefore
///    insufficient to catch the regression at widget-test layer.
///
/// 2. **`PostSessionParams.priorFinishedWorkoutCount` equals the
///    pre-finish workout count.** This is the load-bearing assertion: the
///    pre-fix coordinator read `(ref.read(workoutCountProvider).value ??
///    1) - 1` AFTER the await, returning `prior - 1` (the post-finish
///    count, minus one) — NOT `prior` itself. The post-fix code captures
///    `ref.read(workoutCountProvider).value ?? 0` BEFORE the await,
///    yielding the correct prior count. The harness seeds the provider
///    with `5` and asserts the captured params carry `5`, which is only
///    true if the synchronous pre-await capture is in place. Removing
///    the capture reverts to the broken `- 1` math and the assertion
///    fails with `Expected: 5, Actual: 4`.
///
/// The E2E spec `specs/personal-records.spec.ts:80` and its siblings
/// catch the production `Bad state` exception at the integration layer;
/// this widget test catches the same root cause via the value contract,
/// which is more deterministic in a synthetic test environment.
///
/// **Cluster:** `async-caller-broke-snackbar` / `async-caller-broke-nav` —
/// see PROJECT.md §0 Cluster Ledger and the inline comment in
/// `finish_workout_coordinator.dart` at the `priorWorkoutCount` capture.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/rpg/domain/celebration_queue.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/coordinators/celebration_orchestrator.dart';
import 'package:repsaga/features/workouts/ui/coordinators/finish_workout_coordinator.dart';
import 'package:repsaga/features/workouts/ui/post_session/post_session_controller.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testWorkoutId = 'workout-001';
const _testExerciseId = 'exercise-001';

final _testExercise = Exercise(
  id: _testExerciseId,
  name: 'Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

ActiveWorkoutState _makeNonEmptyState() {
  return ActiveWorkoutState(
    workout: Workout(
      id: _testWorkoutId,
      userId: 'user-001',
      name: 'Push Day',
      startedAt: DateTime.now().toUtc(),
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    ),
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-001',
          workoutId: _testWorkoutId,
          exerciseId: _testExerciseId,
          order: 0,
          exercise: _testExercise,
        ),
        sets: [
          ExerciseSet(
            id: 'set-001',
            workoutExerciseId: 'we-001',
            setNumber: 1,
            weight: 60,
            reps: 8,
            setType: SetType.working,
            isCompleted: true,
            createdAt: DateTime.now().toUtc(),
          ),
        ],
      ),
    ],
  );
}

CelebrationQueueResult _prCelebrationQueue() {
  return const CelebrationQueueResult(
    queue: <CelebrationEvent>[
      CelebrationEvent.personalRecord(
        exerciseId: _testExerciseId,
        exerciseName: 'Bench Press',
        weight: 60,
        reps: 8,
        repBand: '6-12',
        priorBest: null,
      ),
    ],
  );
}

PersonalRecord _seedRecord() {
  return PersonalRecord(
    id: 'pr-001',
    userId: 'user-001',
    exerciseId: _testExerciseId,
    recordType: RecordType.maxReps,
    value: 8,
    reps: 8,
    achievedAt: DateTime.now().toUtc(),
  );
}

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

/// Fake notifier that:
///   * Reports a single completed set (so the empty-session guard skips).
///   * Returns a [FinishWorkoutResult] with a real PR detection result.
///   * Flips state to `AsyncData(null)` inside `finishWorkout` (mimicking
///     production), which disposes the `_ActiveWorkoutStub` State that
///     owns the screen's `ref`.
///   * Returns a celebration queue carrying a [PersonalRecordEvent] so the
///     coordinator's `shouldPushPostSession` evaluates `true`.
///
/// This is exactly the failure pattern PR 30a's first cut hit: after the
/// state flips, `ref.read(workoutCountProvider)` throws.
class _PRRewardNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _PRRewardNotifier(this._state);
  ActiveWorkoutState? _state;

  @override
  Future<ActiveWorkoutState?> build() async => _state;

  @override
  int get totalSetsCount => 1;

  @override
  int get incompleteSetsCount => 0;

  @override
  Future<FinishWorkoutResult?> finishWorkout({String? notes}) async {
    // Mirror production: yield to the framework via a microtask BEFORE
    // flipping state, so the active-workout screen has time to receive
    // the notification, rebuild to its spinner branch, and dispose the
    // State that owns the harness's `ref`. Without the yield the state
    // mutation lands inside the same synchronous tick as `await` resumes,
    // and the framework hasn't yet rebuilt — so `ref` is still mounted
    // when the coordinator's post-await code runs and the regression
    // doesn't reproduce.
    //
    // In production this delay is the actual network round-trip + the
    // `_buildAndStashCelebration` chain inside `ActiveWorkoutNotifier`.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _state = null;
    state = const AsyncData(null);
    // Another yield to give the framework a paint tick to rebuild +
    // dispose the State. `Element.deactivate` runs during the post-frame
    // build phase, not synchronously with `notifyListeners`. With this
    // yield the State is properly disposed before the coordinator's
    // post-await `ref.read(...)` runs — reproducing the production race.
    await Future<void>.delayed(Duration.zero);
    return (
      prResult: PRDetectionResult(
        newRecords: [_seedRecord()],
        isFirstWorkout: false,
      ),
      savedOffline: false,
      serverErrorQueued: false,
    );
  }

  @override
  CelebrationQueueResult? consumeLastCelebration() => _prCelebrationQueue();

  @override
  num? consumeLastSessionTotalXpDelta() => 50;

  @override
  Map<BodyPart, num> consumeLastSessionBpDeltas() => const <BodyPart, num>{
    BodyPart.chest: 50,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No-op CelebrationOrchestrator that returns immediately.
///
/// The production [CelebrationOrchestrator] reads several global providers
/// (`currentUserIdProvider`, `earnedTitlesProvider`, `titleCatalogProvider`,
/// `rankUpPulseLocalStorageProvider`) which require a fully-bootstrapped
/// auth + RPG harness. This regression test is laser-focused on the
/// coordinator's post-await `ref` usage in the post-session push branch —
/// the orchestrator's own behavior is not under test here, so we inject
/// a fake to bypass its provider reads.
class _NoopCelebrationOrchestrator extends CelebrationOrchestrator {
  const _NoopCelebrationOrchestrator();

  @override
  Future<CelebrationOutcome> play({
    required BuildContext rootContext,
    required WidgetRef ref,
    required CelebrationQueueResult celebration,
  }) async {
    // Mirror the production orchestrator's saga-intro 5-second timeout +
    // 200ms gap by yielding through a delay long enough for the framework
    // to dispose the active-workout body widget that owns the
    // coordinator's `ref`. Without this delay the await chain returns
    // before the dispose window opens, and a `ref.read(...)` in the
    // post-session branch silently succeeds — masking the regression.
    //
    // 50 ms is enough for the test binding to deactivate the State while
    // still keeping the test fast.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return (userTappedOverflow: false);
  }
}

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

/// Builds a GoRouter + ProviderScope scaffold whose `/workout/finish/:id`
/// route records every navigation. The coordinator's
/// `rootContext.go('/workout/finish/...')` call materialises as an entry
/// in [navigatedLocations].
Widget _buildHarness({
  required _PRRewardNotifier notifier,
  required List<String> navigatedLocations,
  required List<PostSessionParams> capturedParams,
  int initialWorkoutCount = 1,
}) {
  final router = GoRouter(
    initialLocation: '/active',
    routes: [
      GoRoute(
        path: '/active',
        builder: (context, state) => _ActiveWorkoutStub(notifier: notifier),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          navigatedLocations.add('/home');
          return const Scaffold(body: Text('Home'));
        },
      ),
      GoRoute(
        // `extra` carries `PostSessionParams` — we capture it so the
        // test can assert the params were built correctly (e.g.
        // `priorFinishedWorkoutCount` came from the synchronous
        // pre-await capture, not from a post-await `ref.read`).
        path: '/workout/finish/:workoutId',
        builder: (context, state) {
          navigatedLocations.add(
            '/workout/finish/${state.pathParameters['workoutId']}',
          );
          if (state.extra is PostSessionParams) {
            capturedParams.add(state.extra as PostSessionParams);
          }
          return const Scaffold(body: Text('PostSession'));
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(() => notifier),
      // Provide a value for the workout-count provider that the
      // coordinator captures BEFORE the await. Pre-fix the coordinator
      // read this AFTER the await, throwing because the harness's
      // `ref` is bound to `_ActiveWorkoutStub` (disposed during the
      // notifier transition). Post-fix the read happens while the
      // State is still mounted, so the override is what the
      // post-session params see.
      workoutCountProvider.overrideWith((ref) async => initialWorkoutCount),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Mirrors the production `ActiveWorkoutScreen` shell: when the notifier
/// transitions to `AsyncData(null)` the body is removed from the tree
/// (replaced by a spinner Scaffold), which disposes the body's State and
/// invalidates its `ref`. This shell-vs-body split is the load-bearing
/// piece that makes the regression reproducible — without it the harness
/// widget never unmounts and the broken `ref.read(...)` after the await
/// silently succeeds.
class _ActiveWorkoutStub extends ConsumerWidget {
  const _ActiveWorkoutStub({required this.notifier});
  final _PRRewardNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeWorkoutProvider);
    if (async.value == null && !async.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Body is a child Consumer*Stateful*Widget with its OWN State and
    // `ref`. That State owns the FinishWorkoutCoordinator (mirroring
    // `_ActiveWorkoutScreenState`). When the shell swaps to the spinner
    // above, this body widget leaves the tree and its State is disposed
    // — invalidating the ref the coordinator's post-await code captured.
    return const _ActiveWorkoutBody();
  }
}

class _ActiveWorkoutBody extends ConsumerStatefulWidget {
  const _ActiveWorkoutBody();

  @override
  ConsumerState<_ActiveWorkoutBody> createState() => _ActiveWorkoutBodyState();
}

class _ActiveWorkoutBodyState extends ConsumerState<_ActiveWorkoutBody> {
  late final FinishWorkoutCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = FinishWorkoutCoordinator(
      celebrationOrchestrator: const _NoopCelebrationOrchestrator(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('finish-btn'),
          onPressed: () => _coordinator.finish(context: context, ref: ref),
          child: const Text('Finish'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FinishWorkoutCoordinator — post-session navigation', () {
    testWidgets('navigates to /workout/finish/:workoutId when a PR is set '
        '(does not throw on `ref` after the notifier transition)', (
      tester,
    ) async {
      final navigated = <String>[];
      final captured = <PostSessionParams>[];
      final notifier = _PRRewardNotifier(_makeNonEmptyState());

      await tester.pumpWidget(
        _buildHarness(
          notifier: notifier,
          navigatedLocations: navigated,
          capturedParams: captured,
          initialWorkoutCount: 5,
        ),
      );
      await tester.pumpAndSettle();

      // Force the workoutCountProvider FutureProvider to resolve so
      // `ref.read(workoutCountProvider).value` returns the override
      // (5) instead of `null`. Without this the coordinator's
      // synchronous capture would fall through the `?? 0` and the
      // assertion would see 0.
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('finish-btn'))),
      );
      await container.read(workoutCountProvider.future);
      await tester.pumpAndSettle();

      // Tap "Finish" → opens the FinishWorkoutDialog.
      await tester.tap(find.byKey(const ValueKey('finish-btn')));
      await tester.pumpAndSettle();

      // Confirm the dialog (FilledButton with the localized "Finish" copy).
      // The dialog renders Cancel (TextButton) + Finish (FilledButton).
      final confirmBtn = find.byType(FilledButton);
      expect(
        confirmBtn,
        findsOneWidget,
        reason:
            'FinishWorkoutDialog must show its confirm button after '
            'tapping the harness Finish button.',
      );
      await tester.tap(confirmBtn);

      // Drive the full post-finish frame chain: await notifier.finishWorkout,
      // the celebration orchestrator's saga-intro timeout (5s upper bound +
      // 200ms gap — but in a harness the SagaIntroSequencer never resolves
      // organically, so we let the timeout elapse), and the two-frame
      // deferred release. `pumpAndSettle` with a generous timeout walks the
      // animation queue + the timer wheel.
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // Contract: the post-session route MUST have been navigated to. If
      // the regression reverts (the pre-await `priorWorkoutCount` capture
      // is removed and a `ref.read` is inlined inside the post-session
      // push branch), this expectation fails with an empty
      // `navigatedLocations` list because the `Bad state` exception
      // thrown synchronously prevents the `addPostFrameCallback` from
      // running.
      expect(
        navigated.any((l) => l.startsWith('/workout/finish/')),
        isTrue,
        reason:
            'Coordinator must navigate to /workout/finish/:workoutId when '
            'a PR is set. Empty navigation list indicates the post-session '
            'push branch threw before scheduling the postFrame go() — most '
            'likely a `ref.read(...)` AFTER `await notifier.finishWorkout()` '
            '(cluster: async-caller-broke-nav). See '
            '`finish_workout_coordinator.dart` `priorWorkoutCount` capture '
            'comment for the contract.',
      );

      // Also pin the workoutId in the URL — it must come from the state
      // snapshot captured before finishWorkout disposed the active state
      // (mirrors the production code's `currentState?.workout.id` capture).
      expect(
        navigated.any((l) => l == '/workout/finish/$_testWorkoutId'),
        isTrue,
        reason:
            'The pushed route must carry the just-finished workout id '
            '($_testWorkoutId), not "unknown". If the URL shows "unknown" '
            'it means the pre-finish snapshot of `currentState` was lost.',
      );

      // And the screen must NOT be stuck on /home — that would mean the
      // active-workout screen postFrame won the race (its callback only
      // fires when `!_finishCoordinator.isFinishHandled`). Pre-fix
      // /home is sometimes hit instead of /workout/finish/... depending
      // on whether the exception fires before or after the
      // `_isFinishHandled = false` deferred release.
      expect(
        navigated.where((l) => l == '/home').toList(),
        isEmpty,
        reason:
            'Coordinator must NOT route to /home when a PR celebration '
            'is queued — the post-session push branch owns navigation. '
            'Routing to /home indicates `_isFinishHandled` was released '
            'early or the post-session branch threw.',
      );

      // Pin the contract on `priorFinishedWorkoutCount` — proves the
      // value came from a synchronous pre-await `ref.read(...)` and not
      // from a post-await read that would crash on a disposed widget.
      // The harness seeded `workoutCountProvider` with `5`; the captured
      // value MUST be 5 (the count BEFORE this finish — the just-
      // finished workout has not yet been counted at capture time).
      expect(
        captured,
        hasLength(1),
        reason:
            'Exactly one set of post-session params should reach '
            'the route builder.',
      );
      expect(
        captured.single.priorFinishedWorkoutCount,
        equals(5),
        reason:
            'priorFinishedWorkoutCount MUST equal the pre-finish '
            'workout count (5). The capture has to run BEFORE the '
            '`await notifier.finishWorkout()` — reading from `ref` '
            'after the await would throw `Bad state: Using "ref" when '
            'a widget is about to or has been unmounted is unsafe` '
            'because the active-workout State is disposed by then.',
      );
    });
  });
}
