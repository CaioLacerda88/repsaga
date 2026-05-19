/// Widget tests for the offline connectivity guard added in Phase 14e.
///
/// Verifies that:
///   - `startRoutineWorkout` shows a snackbar when offline (isOnlineProvider
///     returns false) and does NOT call startFromRoutine.
///   - `_startQuickWorkout` (via ActionHero) shows a snackbar when offline and
///     does NOT call startWorkout.
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
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/action_hero.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
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
// Stubs for ActionHero harness
// ---------------------------------------------------------------------------

/// Minimal plan stub: always resolves to null (no active plan) so ActionHero
/// enters the lapsed/brand-new branch based on workoutCount alone.
class _NullPlanStub extends AsyncNotifier<WeeklyPlan?>
    implements WeeklyPlanNotifier {
  @override
  Future<WeeklyPlan?> build() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty routine list — not needed for the offline guard path but required so
/// ActionHero's _BrandNewHero / _LapsedHero branches don't crash.
class _EmptyRoutineListStub extends AsyncNotifier<List<Routine>>
    implements RoutineListNotifier {
  @override
  Future<List<Routine>> build() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tracks whether startWorkout was called. Used to assert the offline guard
/// blocks the call.
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

  // ---------------------------------------------------------------------------
  // ActionHero._startQuickWorkout — offline guard
  //
  // _startQuickWorkout is a private method on ActionHero (lapsed-state path).
  // It shares the same guard pattern as startRoutineWorkout but lives in a
  // different file and a different widget tree. Testing it separately ensures
  // neither copy can be removed without a test failure catching the regression.
  // ---------------------------------------------------------------------------

  group(
    'ActionHero._startQuickWorkout — offline guard',
    // Phase 26f T10 collapsed ActionHero from 4 branches to 3 and removed
    // the legacy `_LapsedHero` that surfaced the "Quick workout" secondary
    // button. T12 deletes this group once `_startQuickWorkout` is fully
    // unused; until then we skip it so the rest of the offline-guard
    // contract (startRoutineWorkout) stays under test.
    skip: 'Retired in T12 — Quick workout button removed in 26f',
    () {
      late _TrackingActiveWorkoutNotifier trackingNotifier;

      setUp(() {
        trackingNotifier = _TrackingActiveWorkoutNotifier();
      });

      Future<void> pumpActionHeroLapsed(
        WidgetTester tester, {
        required bool isOnline,
      }) async {
        final router = GoRouter(
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (ctx, _) => Consumer(
                builder: (context, ref, _) {
                  ref.watch(activeWorkoutProvider);
                  return const Scaffold(body: ActionHero());
                },
              ),
            ),
            GoRoute(
              path: '/workout/active',
              builder: (ctx, _) =>
                  const Scaffold(body: Text('Active Workout Screen')),
            ),
            GoRoute(
              path: '/plan/week',
              builder: (ctx, _) =>
                  const Scaffold(body: Text('Plan Week Screen')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isOnlineProvider.overrideWithValue(isOnline),
              weeklyPlanProvider.overrideWith(() => _NullPlanStub()),
              routineListProvider.overrideWith(() => _EmptyRoutineListStub()),
              // workoutCount > 0 → lapsed state → "Quick workout" button visible.
              workoutCountProvider.overrideWith((_) => Future.value(3)),
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
      }

      testWidgets('shows snackbar and does NOT call startWorkout when offline', (
        tester,
      ) async {
        await pumpActionHeroLapsed(tester, isOnline: false);
        // Settle so workoutCountProvider resolves and ActionHero renders lapsed.
        await tester.pumpAndSettle();

        // The lapsed hero renders "Quick workout" as a secondary OutlinedButton.
        expect(find.text('Quick workout'), findsOneWidget);

        await tester.tap(find.text('Quick workout'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('Starting a workout requires an internet connection'),
          findsOneWidget,
        );

        // The tracking notifier must not have been asked to start a workout.
        expect(trackingNotifier.startWorkoutCallCount, 0);
      });
    },
  );
}
