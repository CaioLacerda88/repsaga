import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workout_history_providers.dart';

/// Consecutive training-day count anchored to today (local time).
///
/// Walks back from today: a day counts if any workout's effective
/// completion date (`finishedAt ?? startedAt`, matching the convention used
/// by [lastSessionProvider]) falls within that day's local date. Today is
/// grace — missing the current day does NOT immediately break the streak;
/// the count anchors on yesterday instead. The streak breaks on the first
/// missing day before the anchor.
///
/// Returns 0 when:
///   * [workoutHistoryProvider] is still loading or errored
///   * The user has no workout history
///   * No workout falls within today or yesterday
///
/// Uses `package:clock`'s ambient clock so tests can pin a fixed reference
/// time via `withClock(Clock.fixed(...), ...)`.
final streakProvider = Provider<int>((ref) {
  final history = ref.watch(workoutHistoryProvider).value?.workouts;
  if (history == null || history.isEmpty) return 0;

  final now = clock.now();
  final today = DateTime(now.year, now.month, now.day);

  // Bucket history into local-date keys for O(1) lookup. Multiple workouts
  // on the same calendar day collapse into a single set entry — the
  // streak counts days, not sessions.
  final trainedDays = <DateTime>{
    for (final w in history)
      _localDate(w.finishedAt?.toLocal() ?? w.startedAt.toLocal()),
  };

  // Pick anchor: today if trained, else yesterday (grace).
  final yesterday = today.subtract(const Duration(days: 1));
  DateTime cursor;
  if (trainedDays.contains(today)) {
    cursor = today;
  } else if (trainedDays.contains(yesterday)) {
    cursor = yesterday;
  } else {
    return 0;
  }

  var count = 0;
  while (trainedDays.contains(cursor)) {
    count++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return count;
});

DateTime _localDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
