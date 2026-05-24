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

  // Bug C v2 (2026-05-23) — must mirror the production getter at
  // active_workout_notifier.dart's `totalSetsCount`, which short-circuits
  // to 0 when `state.value == null`. Reading from `_state` (which IS
  // nulled inside `finishWorkout` below) reproduces the production
  // lifecycle so the test catches the regression of reading
  // `notifier.totalSetsCount` AFTER the await. A hardcoded `=> 1` would
  // mask the bug because the post-await read in the coordinator would
  // (wrongly) succeed.
  //
  // PR #261 reviewer Blocker 2 (2026-05-24) — the `.where(isCompleted)`
  // filter mirrors the post-Bug-B production getter: planned-but-not-
  // tapped slots no longer count. `_makeNonEmptyState` uses
  // `isCompleted: true`, so the returned count stays at 1 — the
  // post-session navigation contract under test is unchanged.
  @override
  int get totalSetsCount {
    final s = _state;
    if (s == null) return 0;
    return s.exercises
        .expand((e) => e.sets)
        .where((set) => set.isCompleted)
        .length;
  }

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

/// Bug C (2026-05-23) regression fixture — baseline XP-only finish.
///
/// **What this notifier models.** Mockup §5 State 2: a session that
/// commits successfully but earns no reward events at all. No rank-up,
/// no PR, no class-change, no level-up, no title — just XP. Per the
/// post-session §5 spec this IS the most common state, and the
/// cinematic was designed around making baseline XP feel rewarding (the
/// B1 XP slam is documented at active_workout_notifier.dart:1825 as the
/// "user's primary feedback even on a session with no rank-up / no PR").
///
/// **The pre-fix bug.** The coordinator's old `shouldPushPostSession`
/// predicate was `hasRewardEvent || hasNewRecords`. For this state both
/// halves evaluate false (no events → no reward; no PR → null result),
/// so the predicate returned false and the user landed on /home via the
/// legacy navigator — skipping the cinematic the spec calls for.
///
/// **What this notifier returns.**
///   * `consumeLastCelebration() == null` — mirrors the production
///     notifier's `if (events.isEmpty) { _lastCelebration = null; }`
///     short-circuit at active_workout_notifier.dart:1843.
///   * `prResult == null` — no PR was set this session.
///   * `totalSetsCount == 1` — one logged set, so the empty-session
///     guard at line 95 passes and finish() proceeds.
///   * XP/BP deltas non-zero — the post-session screen has something
///     to slam into the user.
class _BaselineNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _BaselineNotifier(this._state);
  ActiveWorkoutState? _state;

  @override
  Future<ActiveWorkoutState?> build() async => _state;

  // Bug C v2 (2026-05-23) — mirror the production getter (reads from
  // `state.value`, returns 0 after `finishWorkout()` nulls the state).
  // A hardcoded `=> 1` here masks the lifecycle regression: the
  // coordinator's post-await `notifier.totalSetsCount > 0` read would
  // (wrongly) succeed, the predicate would (wrongly) be true, and the
  // test would PASS even with the broken production code. Reading from
  // `_state` — which we deliberately null inside `finishWorkout` below
  // — reproduces the production lifecycle exactly.
  //
  // PR #261 reviewer Blocker 2 (2026-05-24) — the `.where(isCompleted)`
  // filter mirrors the post-Bug-B production getter. `_makeNonEmptyState`
  // uses `isCompleted: true`, so the returned count stays at 1.
  @override
  int get totalSetsCount {
    final s = _state;
    if (s == null) return 0;
    return s.exercises
        .expand((e) => e.sets)
        .where((set) => set.isCompleted)
        .length;
  }

  @override
  int get incompleteSetsCount => 0;

  @override
  Future<FinishWorkoutResult?> finishWorkout({String? notes}) async {
    // Same two-yield dance as `_PRRewardNotifier` so the active-workout
    // shell has time to rebuild + dispose the body State that owns the
    // harness `ref`. See `_PRRewardNotifier.finishWorkout` for the full
    // explanation of why both yields are load-bearing.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _state = null;
    state = const AsyncData(null);
    await Future<void>.delayed(Duration.zero);
    return (prResult: null, savedOffline: false, serverErrorQueued: false);
  }

  @override
  CelebrationQueueResult? consumeLastCelebration() => null;

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
  required ActiveWorkoutNotifier notifier,
  required List<String> navigatedLocations,
  required List<PostSessionParams> capturedParams,
  int initialWorkoutCount = 1,
}) {
  final router = GoRouter(
    initialLocation: '/active',
    routes: [
      GoRoute(
        path: '/active',
        builder: (context, state) => const _ActiveWorkoutStub(),
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
  const _ActiveWorkoutStub();

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

    testWidgets(
      'navigates to /workout/finish/:workoutId for a baseline XP-only '
      'session (no reward events, no PR — Bug C 2026-05-23)',
      (tester) async {
        // Mockup §5 State 2 — THE most common finish state. Pre-fix the
        // coordinator's `shouldPushPostSession` predicate gated on
        // `hasRewardEvent || hasNewRecords`, and baseline finishes have
        // neither — so the user was dropped onto /home and never saw the
        // cinematic the spec calls for. Post-fix the predicate is
        // `!wasSavedOffline && notifier.totalSetsCount > 0`, so the
        // baseline path routes through the post-session screen and the
        // B1 XP slam (notifier author's "primary feedback") plays.
        final navigated = <String>[];
        final captured = <PostSessionParams>[];
        final notifier = _BaselineNotifier(_makeNonEmptyState());

        await tester.pumpWidget(
          _buildHarness(
            notifier: notifier,
            navigatedLocations: navigated,
            capturedParams: captured,
            initialWorkoutCount: 3,
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('finish-btn'))),
        );
        await container.read(workoutCountProvider.future);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('finish-btn')));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle(const Duration(seconds: 10));

        // Contract: baseline XP-only finishes MUST reach the post-session
        // route. If this assertion fails with an empty navigation list
        // the predicate has likely regressed to the legacy
        // `hasRewardEvent || hasNewRecords` form — re-read the doc-block
        // above `shouldPushPostSession` for the intent.
        expect(
          navigated.any((l) => l == '/workout/finish/$_testWorkoutId'),
          isTrue,
          reason:
              'Baseline XP-only finish must route to '
              '/workout/finish/$_testWorkoutId. An empty navigated list '
              'means the post-session push branch was skipped — most '
              'likely shouldPushPostSession regressed to the '
              '`hasRewardEvent || hasNewRecords` predicate. Mockup §5 '
              'State 2 is THE most common finish state and the cinematic '
              'was designed around making baseline XP feel rewarding.',
        );

        // And the screen must NOT have landed on /home — that would mean
        // the predicate evaluated false and the legacy navigator took
        // over, skipping the cinematic.
        expect(
          navigated.where((l) => l == '/home').toList(),
          isEmpty,
          reason:
              'Baseline XP-only finish must NOT land on /home. /home '
              'indicates shouldPushPostSession returned false and the '
              'legacy postWorkoutNavigator branch ran — skipping the '
              'cinematic.',
        );

        // Pin the params: the route builder must receive a valid
        // PostSessionParams (NOT null), with the threaded XP/BP deltas
        // and the synthesized empty CelebrationQueueResult.
        expect(
          captured,
          hasLength(1),
          reason:
              'Exactly one set of post-session params should reach '
              'the route builder.',
        );
        expect(
          captured.single.totalXpEarned,
          equals(50),
          reason:
              'totalXpEarned must thread through from the notifier — '
              'baseline XP-only is the user-visible reward and B1 needs '
              'the value to slam.',
        );
        expect(
          captured.single.bpXpDeltas,
          equals(const {BodyPart.chest: 50}),
          reason:
              'bpXpDeltas must thread through from the notifier — the '
              'tally cut renders per-body-part bars from these deltas.',
        );
        expect(
          captured.single.queueResult.queue,
          isEmpty,
          reason:
              'When the notifier returns null from consumeLastCelebration '
              '(events.isEmpty short-circuit), the coordinator must '
              'synthesize an empty CelebrationQueueResult — the screen '
              'never sees null. Empty queue is the choreographer\'s S2 '
              'baseline path.',
        );
        expect(
          captured.single.priorFinishedWorkoutCount,
          equals(3),
          reason:
              'priorFinishedWorkoutCount must come from the synchronous '
              'pre-await capture of workoutCountProvider.',
        );
      },
    );
  });
}
