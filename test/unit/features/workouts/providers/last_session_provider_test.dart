/// Unit tests for [lastSessionProvider].
///
/// Derives the user's most recent completed workout from
/// [workoutHistoryProvider] and formats a relative-date string for the
/// editorial "Last: ..." line on Home.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';

import '../../../../fixtures/test_factories.dart';

// ---------------------------------------------------------------------------
// Notifier stubs
// ---------------------------------------------------------------------------

class _WorkoutHistoryNotifier extends AsyncNotifier<WorkoutHistoryState>
    implements WorkoutHistoryNotifier {
  _WorkoutHistoryNotifier(this.workouts);
  final List<Workout> workouts;

  @override
  Future<WorkoutHistoryState> build() async =>
      (workouts: workouts, isLoadingMore: false, hasMore: false);

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

class _EmptyWorkoutHistoryNotifier extends AsyncNotifier<WorkoutHistoryState>
    implements WorkoutHistoryNotifier {
  @override
  Future<WorkoutHistoryState> build() async =>
      (workouts: const <Workout>[], isLoadingMore: false, hasMore: false);

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('lastSessionProvider', () {
    test('returns null when workout history is empty', () async {
      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _EmptyWorkoutHistoryNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Wait for the async notifier to build.
      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNull);
    });

    test(
      'returns workout name and relative date for most recent workout',
      () async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final workout = Workout.fromJson(
          TestWorkoutFactory.create(
            name: 'Push Day',
            finishedAt: yesterday.toIso8601String(),
          ),
        );

        final container = ProviderContainer(
          overrides: [
            workoutHistoryProvider.overrideWith(
              () => _WorkoutHistoryNotifier([workout]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(workoutHistoryProvider.future);

        final lastSession = container.read(lastSessionProvider);
        expect(lastSession, isNotNull);
        expect(lastSession!.name, 'Push Day');
        expect(lastSession.relativeDate, 'Yesterday');
      },
    );

    test('returns "Today" for same-day workout', () async {
      final now = DateTime.now();
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Leg Day',
          finishedAt: now.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      expect(lastSession!.relativeDate, 'Today');
    });

    test('returns "3 days ago" for workout 3 days old', () async {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Pull Day',
          finishedAt: threeDaysAgo.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      expect(lastSession!.relativeDate, '3 days ago');
      expect(lastSession.name, 'Pull Day');
    });

    test('uses finishedAt over startedAt when both present', () async {
      final now = DateTime.now();
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Upper Body',
          startedAt: now.subtract(const Duration(days: 5)).toIso8601String(),
          finishedAt: now.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      // Should use finishedAt (today), not startedAt (5 days ago).
      expect(lastSession!.relativeDate, 'Today');
    });

    test('returns "1w ago" for workout exactly 7 days old', () async {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Back Day',
          finishedAt: sevenDaysAgo.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      expect(lastSession!.relativeDate, '1w ago');
    });

    test('returns "2w ago" for workout 14 days old', () async {
      final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14));
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Chest Day',
          finishedAt: fourteenDaysAgo.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      expect(lastSession!.relativeDate, '2w ago');
    });

    test('returns "1mo ago" for workout 30 days old', () async {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Shoulders',
          finishedAt: thirtyDaysAgo.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      expect(lastSession!.relativeDate, '1mo ago');
    });

    test('returns "3mo ago" for workout 90 days old', () async {
      final ninetyDaysAgo = DateTime.now().subtract(const Duration(days: 90));
      final workout = Workout.fromJson(
        TestWorkoutFactory.create(
          name: 'Arms',
          finishedAt: ninetyDaysAgo.toIso8601String(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          workoutHistoryProvider.overrideWith(
            () => _WorkoutHistoryNotifier([workout]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workoutHistoryProvider.future);

      final lastSession = container.read(lastSessionProvider);
      expect(lastSession, isNotNull);
      expect(lastSession!.relativeDate, '3mo ago');
    });
  });
}
