import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/domain/workout_history_grouping.dart';
import 'package:repsaga/features/workouts/models/workout.dart';

import '../../../../fixtures/test_factories.dart';

/// Helper: build a [Workout] finished at the supplied LOCAL DateTime
/// (the test composes a local DateTime and the factory converts to ISO).
///
/// `totalXp` defaults to 0 unless overridden so the roll-up assertions
/// can pin specific values.
Workout _workout({
  required String id,
  required DateTime finishedAtLocal,
  int totalXp = 0,
}) {
  // Convert local → UTC ISO8601, mirroring how Supabase stores finish
  // timestamps. The grouping function applies `.toLocal()` so the
  // workout reads back at `finishedAtLocal` regardless of the device
  // zone.
  final iso = finishedAtLocal.toUtc().toIso8601String();
  final base = TestWorkoutFactory.create(id: id, finishedAt: iso);
  final w = Workout.fromJson(base);
  return w.copyWith(totalXp: totalXp);
}

void main() {
  group('groupByIsoWeek', () {
    test('empty input returns empty list', () {
      final result = groupByIsoWeek(const <Workout>[], 'en');
      expect(result, isEmpty);
    });

    test('all workouts in same ISO week → single group, correct roll-up', () {
      // Three workouts on Mon/Wed/Fri of the same week (May 18, 20, 22 2026).
      final mon = _workout(
        id: 'w-mon',
        finishedAtLocal: DateTime(2026, 5, 18, 10),
        totalXp: 100,
      );
      final wed = _workout(
        id: 'w-wed',
        finishedAtLocal: DateTime(2026, 5, 20, 11),
        totalXp: 250,
      );
      final fri = _workout(
        id: 'w-fri',
        finishedAtLocal: DateTime(2026, 5, 22, 12),
        totalXp: 75,
      );

      final groups = groupByIsoWeek([fri, wed, mon], 'en');

      expect(groups, hasLength(1));
      expect(groups.first.weekStart, DateTime(2026, 5, 18));
      expect(groups.first.workouts.map((w) => w.id), [
        'w-fri',
        'w-wed',
        'w-mon',
      ]);
      expect(groups.first.totalXp, 100 + 250 + 75);
    });

    test(
      'workouts spanning 2 ISO weeks → 2 groups, most-recent week first',
      () {
        // Week A: Mon May 18 2026
        final weekA = _workout(
          id: 'a',
          finishedAtLocal: DateTime(2026, 5, 18, 10),
          totalXp: 100,
        );
        // Week B: Mon May 25 2026 (next week)
        final weekB = _workout(
          id: 'b',
          finishedAtLocal: DateTime(2026, 5, 25, 10),
          totalXp: 200,
        );

        final groups = groupByIsoWeek([weekB, weekA], 'en');

        expect(groups, hasLength(2));
        // Most-recent week first (descending weekStart).
        expect(groups[0].weekStart, DateTime(2026, 5, 25));
        expect(groups[1].weekStart, DateTime(2026, 5, 18));
        expect(groups[0].workouts.single.id, 'b');
        expect(groups[1].workouts.single.id, 'a');
      },
    );

    test('Sunday 23:59 local stays in the week that ended on that Sunday', () {
      // Sunday May 24 2026, 23:59 local. ISO week starts Mon May 18.
      // Same week as workouts finished Mon May 18 — Sunday IS week-end.
      final sundayLate = _workout(
        id: 'sun',
        finishedAtLocal: DateTime(2026, 5, 24, 23, 59),
        totalXp: 50,
      );
      final mondayEarly = _workout(
        id: 'mon',
        finishedAtLocal: DateTime(2026, 5, 18, 8),
        totalXp: 25,
      );

      final groups = groupByIsoWeek([sundayLate, mondayEarly], 'en');

      // Both fall in the May 18 (Mon) week — single group.
      expect(groups, hasLength(1));
      expect(groups.first.weekStart, DateTime(2026, 5, 18));
      expect(groups.first.totalXp, 75);
    });

    test(
      'UTC vs local — workout at midnight UTC is bucketed per local week',
      () {
        // Build a workout whose finishedAt is May 25 2026 00:30 UTC. In
        // BRT (UTC-3) that's May 24 2026 21:30 — Sunday — which sits in
        // the May 18 week. Under a UTC-relative bucketing the workout
        // would shift into the May 25 week instead.
        final iso = DateTime.utc(2026, 5, 25, 0, 30).toIso8601String();
        final w = Workout.fromJson(
          TestWorkoutFactory.create(id: 'tz', finishedAt: iso),
        ).copyWith(totalXp: 10);

        final groups = groupByIsoWeek([w], 'en');

        // The single workout lands in whichever week the LOCAL anchor
        // resolves to. We assert the conversion is happening at all by
        // pinning the weekStart against the same local-anchor math the
        // production code uses.
        final localAnchor = DateTime.utc(2026, 5, 25, 0, 30).toLocal();
        final daysSinceMonday = localAnchor.weekday - 1;
        final expectedWeekStart = DateTime(
          localAnchor.year,
          localAnchor.month,
          localAnchor.day,
        ).subtract(Duration(days: daysSinceMonday));

        expect(groups, hasLength(1));
        expect(groups.first.weekStart, expectedWeekStart);
      },
    );

    test('totalSets uses the setCountFor callback (defaults to 0)', () {
      final w1 = _workout(id: 'w1', finishedAtLocal: DateTime(2026, 5, 18, 10));
      final w2 = _workout(id: 'w2', finishedAtLocal: DateTime(2026, 5, 19, 10));

      // Default — no callback supplied.
      final groupsDefault = groupByIsoWeek([w1, w2], 'en');
      expect(groupsDefault.first.totalSets, 0);

      // With callback — each workout contributes 5 sets.
      final groupsCounted = groupByIsoWeek(
        [w1, w2],
        'en',
        setCountFor: (_) => 5,
      );
      expect(groupsCounted.first.totalSets, 10);
    });

    test('falls back to startedAt when finishedAt is null', () {
      // Construct a workout with finishedAt == null.
      final base = TestWorkoutFactory.create(id: 'wnf');
      final map = Map<String, dynamic>.from(base)
        ..['finished_at'] = null
        ..['started_at'] = DateTime(2026, 5, 18, 10).toUtc().toIso8601String();
      final w = Workout.fromJson(map);

      final groups = groupByIsoWeek([w], 'en');

      expect(groups, hasLength(1));
      expect(groups.first.weekStart, DateTime(2026, 5, 18));
    });
  });
}
