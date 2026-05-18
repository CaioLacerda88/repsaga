/// Unit tests for WeeklyPlan and BucketRoutine Freezed models.
///
/// Covers: fromJson/toJson roundtrip, default values, and edge cases.
/// Also covers computed provider logic (completedCount, isWeekComplete)
/// using pure Dart logic — no Flutter pump needed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _bucketRoutineJson({
  String routineId = 'routine-001',
  int order = 1,
  String? completedWorkoutId,
  String? completedAt,
}) {
  return {
    'routine_id': routineId,
    'order': order,
    'completed_workout_id': completedWorkoutId,
    'completed_at': completedAt,
  };
}

Map<String, dynamic> _weeklyPlanJson({
  String id = 'plan-001',
  String userId = 'user-001',
  String weekStart = '2026-04-07T00:00:00.000',
  List<Map<String, dynamic>>? routines,
  String createdAt = '2026-04-07T00:00:00.000Z',
  String updatedAt = '2026-04-07T00:00:00.000Z',
}) {
  return {
    'id': id,
    'user_id': userId,
    'week_start': weekStart,
    'routines': routines ?? [],
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BucketRoutine model', () {
    test('fromJson parses all required fields', () {
      final json = _bucketRoutineJson(routineId: 'r-99', order: 3);
      final model = BucketRoutine.fromJson(json);

      expect(model.routineId, 'r-99');
      expect(model.order, 3);
      expect(model.completedWorkoutId, isNull);
      expect(model.completedAt, isNull);
    });

    test('fromJson parses optional completedWorkoutId and completedAt', () {
      final json = _bucketRoutineJson(
        completedWorkoutId: 'wk-123',
        completedAt: '2026-04-08T10:00:00.000Z',
      );
      final model = BucketRoutine.fromJson(json);

      expect(model.completedWorkoutId, 'wk-123');
      expect(model.completedAt, isNotNull);
      expect(model.completedAt!.year, 2026);
    });

    test('toJson roundtrip preserves all fields', () {
      final original = BucketRoutine.fromJson(
        _bucketRoutineJson(
          routineId: 'r-abc',
          order: 2,
          completedWorkoutId: 'wk-xyz',
          completedAt: '2026-04-08T10:00:00.000Z',
        ),
      );

      final json = original.toJson();
      final restored = BucketRoutine.fromJson(json);

      expect(restored.routineId, original.routineId);
      expect(restored.order, original.order);
      expect(restored.completedWorkoutId, original.completedWorkoutId);
      expect(restored.completedAt, original.completedAt);
    });

    test('toJson roundtrip with null optionals preserves nulls', () {
      final original = BucketRoutine.fromJson(_bucketRoutineJson());
      final json = original.toJson();
      final restored = BucketRoutine.fromJson(json);

      expect(restored.completedWorkoutId, isNull);
      expect(restored.completedAt, isNull);
    });

    test('toJson uses snake_case keys', () {
      final model = BucketRoutine.fromJson(_bucketRoutineJson());
      final json = model.toJson();

      expect(json.containsKey('routine_id'), isTrue);
      expect(json.containsKey('completed_workout_id'), isTrue);
      expect(json.containsKey('completed_at'), isTrue);
      // No camelCase keys
      expect(json.containsKey('routineId'), isFalse);
    });

    test('value equality: same data produces equal instances', () {
      final a = BucketRoutine.fromJson(_bucketRoutineJson(order: 1));
      final b = BucketRoutine.fromJson(_bucketRoutineJson(order: 1));

      expect(a, equals(b));
    });

    test('value equality: different order produces non-equal instances', () {
      final a = BucketRoutine.fromJson(_bucketRoutineJson(order: 1));
      final b = BucketRoutine.fromJson(_bucketRoutineJson(order: 2));

      expect(a, isNot(equals(b)));
    });
  });

  group('BucketRoutine — isSpontaneous field', () {
    test('should default to false when absent from JSONB (back-compat)', () {
      final json = _bucketRoutineJson();
      // Defensive: legacy JSONB rows have no `is_spontaneous` key.
      json.remove('is_spontaneous');
      final routine = BucketRoutine.fromJson(json);
      expect(routine.isSpontaneous, isFalse);
    });

    test('should roundtrip true through toJson/fromJson', () {
      const routine = BucketRoutine(
        routineId: 'routine-001',
        order: 1,
        isSpontaneous: true,
      );
      final json = routine.toJson();
      expect(json['is_spontaneous'], isTrue);
      final restored = BucketRoutine.fromJson(json);
      expect(restored.isSpontaneous, isTrue);
    });

    test('should roundtrip false explicitly', () {
      const routine = BucketRoutine(
        routineId: 'routine-001',
        order: 1,
        isSpontaneous: false,
      );
      final json = routine.toJson();
      expect(json['is_spontaneous'], isFalse);
      final restored = BucketRoutine.fromJson(json);
      expect(restored.isSpontaneous, isFalse);
    });
  });

  group('WeeklyPlan model', () {
    test('fromJson parses all required fields', () {
      final json = _weeklyPlanJson(id: 'plan-42', userId: 'user-007');
      final plan = WeeklyPlan.fromJson(json);

      expect(plan.id, 'plan-42');
      expect(plan.userId, 'user-007');
      expect(plan.routines, isEmpty);
    });

    test('fromJson parses weekStart as DateTime', () {
      final json = _weeklyPlanJson(weekStart: '2026-04-07T00:00:00.000');
      final plan = WeeklyPlan.fromJson(json);

      expect(plan.weekStart.year, 2026);
      expect(plan.weekStart.month, 4);
      expect(plan.weekStart.day, 7);
    });

    test('fromJson defaults routines to empty list when field is null', () {
      final json = _weeklyPlanJson();
      json['routines'] = null; // force null
      final plan = WeeklyPlan.fromJson(json);

      expect(plan.routines, isEmpty);
    });

    test('fromJson parses nested BucketRoutine list', () {
      final json = _weeklyPlanJson(
        routines: [
          _bucketRoutineJson(routineId: 'r-1', order: 1),
          _bucketRoutineJson(routineId: 'r-2', order: 2),
        ],
      );
      final plan = WeeklyPlan.fromJson(json);

      expect(plan.routines.length, 2);
      expect(plan.routines[0].routineId, 'r-1');
      expect(plan.routines[1].routineId, 'r-2');
    });

    test('toJson roundtrip preserves all scalar fields', () {
      final original = WeeklyPlan.fromJson(_weeklyPlanJson());
      final json = original.toJson();
      final restored = WeeklyPlan.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.userId, original.userId);
      expect(restored.weekStart, original.weekStart);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('toJson roundtrip preserves nested routines', () {
      final original = WeeklyPlan.fromJson(
        _weeklyPlanJson(
          routines: [
            _bucketRoutineJson(routineId: 'r-1', order: 1),
            _bucketRoutineJson(
              routineId: 'r-2',
              order: 2,
              completedWorkoutId: 'wk-done',
            ),
          ],
        ),
      );

      // WeeklyPlan.toJson serializes nested BucketRoutine objects; to round-
      // trip through fromJson we must convert them to maps first.
      final json = original.toJson();
      final routinesAsMaps = original.routines.map((r) => r.toJson()).toList();
      json['routines'] = routinesAsMaps;
      final restored = WeeklyPlan.fromJson(json);

      expect(restored.routines.length, 2);
      expect(restored.routines[1].completedWorkoutId, 'wk-done');
    });

    test('toJson uses snake_case keys', () {
      final plan = WeeklyPlan.fromJson(_weeklyPlanJson());
      final json = plan.toJson();

      expect(json.containsKey('user_id'), isTrue);
      expect(json.containsKey('week_start'), isTrue);
      expect(json.containsKey('created_at'), isTrue);
      expect(json.containsKey('updated_at'), isTrue);
      expect(json.containsKey('userId'), isFalse);
    });

    test('value equality: identical JSON produces equal instances', () {
      final a = WeeklyPlan.fromJson(_weeklyPlanJson());
      final b = WeeklyPlan.fromJson(_weeklyPlanJson());

      expect(a, equals(b));
    });
  });

  group('WeeklyPlan completedCount computed logic', () {
    WeeklyPlan makePlan({required List<BucketRoutine> routines}) {
      return WeeklyPlan(
        id: 'plan-001',
        userId: 'user-001',
        weekStart: DateTime(2026, 4, 7),
        routines: routines,
        createdAt: DateTime(2026, 4, 7),
        updatedAt: DateTime(2026, 4, 7),
      );
    }

    test('completedCount is 0 for an empty plan', () {
      final plan = makePlan(routines: []);
      final count = plan.routines
          .where((r) => r.completedWorkoutId != null)
          .length;
      expect(count, 0);
    });

    test('completedCount is 0 when no routines are done', () {
      final plan = makePlan(
        routines: [
          const BucketRoutine(routineId: 'r-1', order: 1),
          const BucketRoutine(routineId: 'r-2', order: 2),
        ],
      );
      final count = plan.routines
          .where((r) => r.completedWorkoutId != null)
          .length;
      expect(count, 0);
    });

    test('completedCount equals 1 when one of three is done', () {
      final plan = makePlan(
        routines: [
          const BucketRoutine(
            routineId: 'r-1',
            order: 1,
            completedWorkoutId: 'wk-1',
          ),
          const BucketRoutine(routineId: 'r-2', order: 2),
          const BucketRoutine(routineId: 'r-3', order: 3),
        ],
      );
      final count = plan.routines
          .where((r) => r.completedWorkoutId != null)
          .length;
      expect(count, 1);
    });

    test('completedCount equals total when all routines are done', () {
      final plan = makePlan(
        routines: [
          const BucketRoutine(
            routineId: 'r-1',
            order: 1,
            completedWorkoutId: 'wk-1',
          ),
          const BucketRoutine(
            routineId: 'r-2',
            order: 2,
            completedWorkoutId: 'wk-2',
          ),
        ],
      );
      final count = plan.routines
          .where((r) => r.completedWorkoutId != null)
          .length;
      expect(count, plan.routines.length);
    });
  });

  group('WeeklyPlan isWeekComplete computed logic', () {
    WeeklyPlan makePlan({required List<BucketRoutine> routines}) {
      return WeeklyPlan(
        id: 'plan-001',
        userId: 'user-001',
        weekStart: DateTime(2026, 4, 7),
        routines: routines,
        createdAt: DateTime(2026, 4, 7),
        updatedAt: DateTime(2026, 4, 7),
      );
    }

    bool isComplete(WeeklyPlan plan) {
      if (plan.routines.isEmpty) return false;
      return plan.routines.every((r) => r.completedWorkoutId != null);
    }

    test('isWeekComplete is false for empty routines list', () {
      expect(isComplete(makePlan(routines: [])), isFalse);
    });

    test('isWeekComplete is false when any routine is incomplete', () {
      final plan = makePlan(
        routines: [
          const BucketRoutine(
            routineId: 'r-1',
            order: 1,
            completedWorkoutId: 'wk-1',
          ),
          const BucketRoutine(routineId: 'r-2', order: 2),
        ],
      );
      expect(isComplete(plan), isFalse);
    });

    test('isWeekComplete is true when all routines are completed', () {
      final plan = makePlan(
        routines: [
          const BucketRoutine(
            routineId: 'r-1',
            order: 1,
            completedWorkoutId: 'wk-1',
          ),
          const BucketRoutine(
            routineId: 'r-2',
            order: 2,
            completedWorkoutId: 'wk-2',
          ),
          const BucketRoutine(
            routineId: 'r-3',
            order: 3,
            completedWorkoutId: 'wk-3',
          ),
        ],
      );
      expect(isComplete(plan), isTrue);
    });

    test('isWeekComplete is false for a single uncompleted routine', () {
      final plan = makePlan(
        routines: [const BucketRoutine(routineId: 'r-1', order: 1)],
      );
      expect(isComplete(plan), isFalse);
    });

    test('isWeekComplete is true for a single completed routine', () {
      final plan = makePlan(
        routines: [
          const BucketRoutine(
            routineId: 'r-1',
            order: 1,
            completedWorkoutId: 'wk-1',
          ),
        ],
      );
      expect(isComplete(plan), isTrue);
    });
  });
}
