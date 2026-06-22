/// Widget tests for the offline connectivity guard added in Phase 14e.
///
/// Verifies two live offline-guard entry points:
///   - `startRoutineWorkout` shows a snackbar when offline (isOnlineProvider
///     returns false) and does NOT call startFromRoutine.
///   - The free-workout hero card (`_FreeWorkoutHero` → `_startQuickWorkout`
///     in `action_hero.dart`) shows the offline snackbar and does NOT start a
///     workout / navigate when offline. The trigger moved from a `_LapsedHero`
///     OutlinedButton to a card tap in Phase 26f; the guard
///     (`action_hero.dart:186-195`) is still live, so this group tests the
///     post-26f surface directly via `ActionHero` rendered on its
///     free-workout branch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/providers/notifiers/routine_list_notifier.dart';
import 'package:repsaga/features/routines/ui/start_routine_action.dart';
import 'package:repsaga/features/weekly_plan/providers/suggested_next_provider.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/action_hero.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';
import 'package:repsaga/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

// ---------------------------------------------------------------------------
// Stubs for the free-workout (ActionHero) harness
// ---------------------------------------------------------------------------

/// Empty user-routine list so ActionHero's branch gate sees
/// `userRoutines.isEmpty`. Combined with `workoutCount > 0` and
/// `suggestedNext == null`, this lands on the `_FreeWorkoutHero` branch
/// (not `_CreateFirstRoutineHero`, which requires `workoutCount == 0`).
class _EmptyRoutineListStub extends AsyncNotifier<List<Routine>>
    implements RoutineListNotifier {
  @override
  Future<List<Routine>> build() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tracks whether `startWorkout` was invoked, and reports no active workout
/// from `build()` so `_startQuickWorkout` takes the offline-guard path (which
/// returns BEFORE the resume-vs-start dialog or any start). The offline guard
/// must short-circuit before this method is ever reached.
class _TrackingActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  int startWorkoutCallCount = 0;

  @override
  Future<ActiveWorkoutState?> build() async => null;

  @override
  Future<void> startWorkout([String? name]) async {
    startWorkoutCallCount++;
  }

  @override
  Future<void> startFromRoutine(RoutineStartConfig config) async {}

  @override
  Future<void> discardWorkout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Routine _makeRoutineWithValidExercises() {
  final exercise = TestExerciseFactory.create(
    id: 'ex-bench',
    name: 'Bench Press',
    equipmentType: 'barbell',
  );
  return Routine.fromJson(
    TestRoutineFactory.create(
      id: 'r-valid',
      name: 'Push Day',
      exercises: [
        TestRoutineExerciseFactory.create(
          exerciseId: 'ex-bench',
          exercise: exercise,
        ),
      ],
    ),
  );
}

/// Pumps a minimal scaffold with a button calling [startRoutineWorkout].
///
/// When [useGoRouter] is true, wraps the widget tree in a GoRouter with
/// a `/workout/active` route so that the online path can navigate without
/// throwing "No GoRouter found".
Future<void> _pumpRoutineStarter(
  WidgetTester tester,
  Routine routine, {
  required MockWorkoutRepository mockRepo,
  required MockWorkoutLocalStorage mockStorage,
  required bool isOnline,
  bool useGoRouter = false,
}) async {
  final overrides = [
    workoutRepositoryProvider.overrideWithValue(mockRepo),
    workoutLocalStorageProvider.overrideWithValue(mockStorage),
    isOnlineProvider.overrideWithValue(isOnline),
  ];

  if (useGoRouter) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => startRoutineWorkout(context, ref, routine),
                  child: const Text('Start'),
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: '/workout/active',
          builder: (context, state) =>
              const Scaffold(body: Text('Active Workout')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
  } else {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: TestMaterialApp(
          theme: AppTheme.dark,
          home: Consumer(
            builder: (context, ref, _) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => startRoutineWorkout(context, ref, routine),
                  child: const Text('Start'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(FakeActiveWorkoutState());
  });

  group('startRoutineWorkout — offline guard', () {
    late MockWorkoutRepository mockRepo;
    late MockWorkoutLocalStorage mockStorage;

    setUp(() {
      mockRepo = MockWorkoutRepository();
      mockStorage = MockWorkoutLocalStorage();

      when(() => mockStorage.loadActiveWorkout()).thenReturn(null);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.hasActiveWorkout).thenReturn(false);
    });

    testWidgets('shows snackbar and does NOT start workout when offline', (
      tester,
    ) async {
      final routine = _makeRoutineWithValidExercises();

      await _pumpRoutineStarter(
        tester,
        routine,
        mockRepo: mockRepo,
        mockStorage: mockStorage,
        isOnline: false,
      );

      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Starting a workout requires an internet connection'),
        findsOneWidget,
      );

      // No network call was made.
      verifyNever(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      );
    });

    testWidgets('does NOT show offline snackbar when online', (tester) async {
      final routine = _makeRoutineWithValidExercises();

      // For the online case, createActiveWorkout must be stubbed because
      // startRoutineWorkout will proceed to call startFromRoutine.
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer(
        (_) async => ActiveWorkoutState.fromJson(
          TestActiveWorkoutStateFactory.create(
            workout: TestWorkoutFactory.create(
              id: 'w-online',
              name: 'Push Day',
              isActive: true,
            ),
          ),
        ).workout,
      );
      when(
        () => mockRepo.getLastWorkoutSets(any()),
      ).thenAnswer((_) async => {});

      await _pumpRoutineStarter(
        tester,
        routine,
        mockRepo: mockRepo,
        mockStorage: mockStorage,
        isOnline: true,
        useGoRouter: true,
      );
      await tester.pump();

      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Starting a workout requires an internet connection'),
        findsNothing,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Free-workout hero (_FreeWorkoutHero → _startQuickWorkout) — offline guard
  //
  // Phase 26f moved the quick-workout trigger from a `_LapsedHero`
  // OutlinedButton ("Quick workout" text) to the `_FreeWorkoutHero` card tap.
  // The offline guard at action_hero.dart:186-195 is still live: offline →
  // snackbar → return (no start, no nav). This group renders the real
  // `ActionHero` on its free-workout branch and pins that BEHAVIOR against
  // the post-26f tree.
  // -------------------------------------------------------------------------
  group('Free-workout hero — offline guard', () {
    late _TrackingActiveWorkoutNotifier trackingNotifier;

    setUp(() {
      trackingNotifier = _TrackingActiveWorkoutNotifier();
    });

    /// Pumps `ActionHero` inside a GoRouter, with provider overrides that
    /// force the free-workout branch:
    ///   * `workoutCount > 0` → NOT the create-first-routine (day-0) branch.
    ///   * `routineList` empty + `suggestedNext == null` → no start-next-
    ///     routine branch → falls through to `_FreeWorkoutHero`.
    /// A distinctive `/workout/active` screen lets us assert no navigation
    /// occurred (the offline guard returns before `context.go`).
    Future<void> pumpFreeWorkoutHero(
      WidgetTester tester, {
      required bool isOnline,
    }) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (ctx, _) => const Scaffold(body: ActionHero()),
          ),
          GoRoute(
            path: '/workout/active',
            builder: (ctx, _) =>
                const Scaffold(body: Text('ACTIVE-WORKOUT-SCREEN')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isOnlineProvider.overrideWithValue(isOnline),
            // workoutCount > 0 → not the day-0 create-first-routine branch.
            workoutCountProvider.overrideWith((_) => Future.value(3)),
            // No user routines → userRoutines.isEmpty.
            routineListProvider.overrideWith(() => _EmptyRoutineListStub()),
            // No suggested next entry → free-workout branch (not start-next).
            suggestedNextProvider.overrideWithValue(null),
            isWeekCompleteProvider.overrideWithValue(false),
            activeWorkoutProvider.overrideWith(() => trackingNotifier),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.dark,
            routerConfig: router,
          ),
        ),
      );
      // Let workoutCountProvider resolve so the branch gate settles on
      // _FreeWorkoutHero.
      await tester.pumpAndSettle();
    }

    testWidgets(
      'tapping the free-workout card when offline shows the snackbar and '
      'does NOT start a workout or navigate',
      (tester) async {
        await pumpFreeWorkoutHero(tester, isOnline: false);

        // The free-workout hero is rendered (precondition for the test —
        // proves the branch gate landed where we expect).
        expect(find.text('Free workout'), findsOneWidget);

        await tester.tap(find.text('Free workout'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // (a) The offline snackbar surfaces.
        expect(
          find.text('Starting a workout requires an internet connection'),
          findsOneWidget,
        );

        // (b) No workout was started — observable via the tracking notifier
        // AND the absence of navigation to the active-workout screen.
        expect(trackingNotifier.startWorkoutCallCount, 0);
        expect(find.text('ACTIVE-WORKOUT-SCREEN'), findsNothing);
      },
    );

    testWidgets(
      'tapping the free-workout card when online navigates to the active '
      'workout (no offline snackbar)',
      (tester) async {
        await pumpFreeWorkoutHero(tester, isOnline: true);

        expect(find.text('Free workout'), findsOneWidget);

        await tester.tap(find.text('Free workout'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // No offline snackbar on the online path.
        expect(
          find.text('Starting a workout requires an internet connection'),
          findsNothing,
        );
        // The guard let the start path through: a workout was started and the
        // app navigated to the active-workout screen.
        expect(trackingNotifier.startWorkoutCallCount, 1);
        expect(find.text('ACTIVE-WORKOUT-SCREEN'), findsOneWidget);
      },
    );
  });
}
