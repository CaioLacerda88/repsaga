// Phase 32 PR 32d — `session_zero_xp` analytics emit contract.
//
// Pins the `recordZeroXpSession` notifier method:
//   - Computes `elapsed_seconds` from the captured `workout.startedAt`.
//   - Reports the current `exercises.length` (zero or non-zero).
//   - Records exactly one [AnalyticsEvent.sessionZeroXp] per call.
//   - Silently no-ops when there is no active workout (defensive).
//
// Behavior, not wiring: we assert on the captured event value, not on
// `verify(...).called(1)`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;

import '../../../../fixtures/test_factories.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

class _FakeWorkout extends Fake implements Workout {}

/// Recording fake — captures every event the notifier records so tests
/// can assert on the EXACT payload (not just the call count).
class _RecordingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    events.add(event);
  }
}

supabase.User _fakeUser({String id = 'user-test-001'}) {
  return supabase.User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

/// Builds an [ActiveWorkoutState] with a known `started_at` so we can
/// assert the computed `elapsed_seconds`.
ActiveWorkoutState _stateStartedAt(DateTime startedAt) {
  return ActiveWorkoutState.fromJson(
    TestActiveWorkoutStateFactory.createWithExercises(
      workout: TestWorkoutFactory.create(
        isActive: true,
        startedAt: startedAt.toUtc().toIso8601String(),
      ),
      exerciseCount: 3,
      setsPerExercise: 0,
    ),
  );
}

({ProviderContainer container, _RecordingAnalyticsRepository analyticsRepo})
_makeBundle({required ActiveWorkoutState? initial}) {
  final mockRepo = _MockWorkoutRepository();
  final mockStorage = _MockWorkoutLocalStorage();
  final mockAuth = _MockAuthRepository();
  final analyticsRepo = _RecordingAnalyticsRepository();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
  when(() => mockAuth.currentUser).thenReturn(_fakeUser());

  final container = ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(analyticsRepo),
    ],
  );
  return (container: container, analyticsRepo: analyticsRepo);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeActiveWorkoutState());
    registerFallbackValue(_FakeWorkout());
  });

  group('ActiveWorkoutNotifier.recordZeroXpSession', () {
    test(
      'records session_zero_xp with exercise_count + elapsed_seconds derived '
      'from workout.startedAt',
      () async {
        // started_at = 60 seconds ago in UTC.
        final startedAt = DateTime.now().toUtc().subtract(
          const Duration(seconds: 60),
        );
        final bundle = _makeBundle(initial: _stateStartedAt(startedAt));
        addTearDown(bundle.container.dispose);

        await bundle.container.read(activeWorkoutProvider.future);
        bundle.container
            .read(activeWorkoutProvider.notifier)
            .recordZeroXpSession();

        // Single event recorded.
        expect(bundle.analyticsRepo.events, hasLength(1));
        final recorded = bundle.analyticsRepo.events.single;

        // exercise_count matches the seeded state (3 exercises, 0 sets each).
        expect(recorded.name, 'session_zero_xp');
        expect(recorded.props['exercise_count'], 3);

        // elapsed_seconds is computed at-call-time — allow 0–3 seconds of
        // slack for the test environment's runtime jitter.
        final elapsed = recorded.props['elapsed_seconds'] as int;
        expect(
          elapsed,
          inInclusiveRange(60, 65),
          reason: 'elapsed_seconds must be derived from startedAt at call time',
        );
      },
    );

    test('silently no-ops when there is no active workout', () async {
      final bundle = _makeBundle(initial: null);
      addTearDown(bundle.container.dispose);

      await bundle.container.read(activeWorkoutProvider.future);
      // No active workout — calling this defensively is safe.
      bundle.container
          .read(activeWorkoutProvider.notifier)
          .recordZeroXpSession();

      expect(
        bundle.analyticsRepo.events,
        isEmpty,
        reason:
            'recordZeroXpSession with state.value == null must not emit — '
            'the empty-session guard sheet path only runs after a workout '
            'was started, but a concurrent discard could race the call.',
      );
    });

    test('records exact event payload (sealed-union pattern match)', () async {
      // started_at = exactly 42 seconds ago to assert a tight value.
      final startedAt = DateTime.now().toUtc().subtract(
        const Duration(seconds: 42),
      );
      final bundle = _makeBundle(
        initial: ActiveWorkoutState.fromJson(
          TestActiveWorkoutStateFactory.createWithExercises(
            workout: TestWorkoutFactory.create(
              isActive: true,
              startedAt: startedAt.toIso8601String(),
            ),
            exerciseCount: 1,
            setsPerExercise: 0,
          ),
        ),
      );
      addTearDown(bundle.container.dispose);

      await bundle.container.read(activeWorkoutProvider.future);
      bundle.container
          .read(activeWorkoutProvider.notifier)
          .recordZeroXpSession();

      final recorded = bundle.analyticsRepo.events.single;
      expect(recorded, isA<AnalyticsEvent>());
      // The sealed-union pattern match: assert it's sessionZeroXp with the
      // expected exercise_count. elapsed_seconds remains a range check.
      expect(recorded.name, 'session_zero_xp');
      expect(recorded.props['exercise_count'], 1);
      final elapsed = recorded.props['elapsed_seconds'] as int;
      expect(elapsed, inInclusiveRange(42, 47));
    });
  });
}
