/// Widget tests for the offline connectivity guard added in Phase 14e.
///
/// Verifies that:
///   - `startRoutineWorkout` shows a snackbar when offline (isOnlineProvider
///     returns false) and does NOT call startFromRoutine.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/ui/start_routine_action.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
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
}
