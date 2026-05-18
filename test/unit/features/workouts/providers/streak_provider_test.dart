/// Unit tests for [streakProvider].
///
/// Derives the user's consecutive-day training streak from
/// [workoutHistoryProvider]. Walks back from today (or yesterday if today
/// is untrained — "today is grace") and counts unbroken days. A day
/// counts if any workout's effective date (finishedAt ?? startedAt)
/// falls within that local date.
library;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/streak_provider.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';

import '../../../../fixtures/test_factories.dart';

// ---------------------------------------------------------------------------
// Notifier stubs
// ---------------------------------------------------------------------------

class _WorkoutHistoryNotifier extends AsyncNotifier<List<Workout>>
    implements WorkoutHistoryNotifier {
  _WorkoutHistoryNotifier(this.workouts);
  final List<Workout> workouts;

  @override
  Future<List<Workout>> build() async => workouts;

  @override
  bool get hasMore => false;

  @override
  bool get isLoadingMore => false;

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

class _EmptyWorkoutHistoryNotifier extends AsyncNotifier<List<Workout>>
    implements WorkoutHistoryNotifier {
  @override
  Future<List<Workout>> build() async => [];

  @override
  bool get hasMore => false;

  @override
  bool get isLoadingMore => false;

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Fixed mid-afternoon reference time so day-boundary edge cases are not
/// triggered. Tests subtract whole-day Durations from this to seed
/// workouts on prior calendar days.
final _reference = DateTime(2026, 5, 18, 14, 30);

Workout _workoutAt(DateTime finishedAt, {String id = 'w'}) {
  return Workout.fromJson(
    TestWorkoutFactory.create(
      id: id,
      startedAt: finishedAt.toIso8601String(),
      finishedAt: finishedAt.toIso8601String(),
    ),
  );
}

Future<int> _readStreakWith(List<Workout> workouts) async {
  return withClock(Clock.fixed(_reference), () async {
    final container = ProviderContainer(
      overrides: [
        workoutHistoryProvider.overrideWith(
          () => workouts.isEmpty
              ? _EmptyWorkoutHistoryNotifier()
              : _WorkoutHistoryNotifier(workouts),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(workoutHistoryProvider.future);
    return container.read(streakProvider);
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('streakProvider', () {
    test('returns 0 for empty workout history', () async {
      final streak = await _readStreakWith(const []);
      expect(streak, 0);
    });

    test('returns 1 for a single workout completed today', () async {
      final streak = await _readStreakWith([_workoutAt(_reference)]);
      expect(streak, 1);
    });

    test('returns 2 for workouts on today + yesterday', () async {
      final streak = await _readStreakWith([
        _workoutAt(_reference, id: 'today'),
        _workoutAt(_reference.subtract(const Duration(days: 1)), id: 'yest'),
      ]);
      expect(streak, 2);
    });

    test('returns 1 when only yesterday is trained (today is grace)', () async {
      final streak = await _readStreakWith([
        _workoutAt(_reference.subtract(const Duration(days: 1))),
      ]);
      expect(streak, 1);
    });

    test(
      'returns 1 when today is trained but yesterday is missing (gap breaks)',
      () async {
        final streak = await _readStreakWith([
          _workoutAt(_reference, id: 'today'),
          _workoutAt(
            _reference.subtract(const Duration(days: 2)),
            id: 'day-before-yest',
          ),
        ]);
        expect(streak, 1);
      },
    );

    test('returns 7 for seven consecutive days ending today', () async {
      final workouts = <Workout>[
        for (var i = 0; i < 7; i++)
          _workoutAt(_reference.subtract(Duration(days: i)), id: 'w-$i'),
      ];
      final streak = await _readStreakWith(workouts);
      expect(streak, 7);
    });

    test('multiple workouts on the same day count as one streak day', () async {
      // Three workouts all dated today — streak should be 1, not 3.
      final today = DateTime(_reference.year, _reference.month, _reference.day);
      final streak = await _readStreakWith([
        _workoutAt(today.add(const Duration(hours: 6)), id: 'morning'),
        _workoutAt(today.add(const Duration(hours: 12)), id: 'noon'),
        _workoutAt(today.add(const Duration(hours: 18)), id: 'evening'),
      ]);
      expect(streak, 1);
    });
  });
}
