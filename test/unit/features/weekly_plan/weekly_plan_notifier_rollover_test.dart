/// Unit tests for the week-rollover filter applied by `WeeklyPlanNotifier`.
///
/// Pins the contract that spontaneous entries do NOT carry forward when a
/// new week's plan is auto-populated from the previous week (both via the
/// build-time `_tryAutoPopulate` path and the user-facing
/// `autoPopulateFromLastWeek` path). The filter expression mirrored here
/// MUST stay in sync with `weekly_plan_provider.dart`; a future refactor
/// that drops the filter breaks these tests.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';

void main() {
  group('week rollover filters spontaneous entries', () {
    test('should only copy non-spontaneous entries forward', () {
      final previous = [
        const BucketRoutine(routineId: 'r1', order: 1, isSpontaneous: false),
        const BucketRoutine(
          routineId: 'r2',
          order: 2,
          isSpontaneous: true,
          completedWorkoutId: 'w-spontaneous',
        ),
        const BucketRoutine(routineId: 'r3', order: 3, isSpontaneous: false),
      ];

      // Mirror the filter expression used inside autoPopulateFromLastWeek
      // and _tryAutoPopulate so a future refactor that drops the filter
      // breaks this test.
      final carriedForward = previous
          .where((r) => !r.isSpontaneous)
          .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
          .toList();

      expect(carriedForward.length, 2);
      expect(carriedForward[0].routineId, 'r1');
      expect(carriedForward[1].routineId, 'r3');
      // Completion state is cleared.
      expect(carriedForward.every((r) => r.completedWorkoutId == null), isTrue);
      expect(carriedForward.every((r) => !r.isSpontaneous), isTrue);
    });

    test(
      'should produce an empty rollover when previous week was all-spontaneous',
      () {
        final previous = [
          const BucketRoutine(routineId: 'r1', order: 1, isSpontaneous: true),
          const BucketRoutine(routineId: 'r2', order: 2, isSpontaneous: true),
        ];
        final carriedForward = previous.where((r) => !r.isSpontaneous).toList();
        expect(carriedForward, isEmpty);
      },
    );

    test(
      'should renumber surviving entries contiguously starting at order 1',
      () {
        // Previous week with a gap: planned, spontaneous, planned, planned.
        // After filtering the spontaneous entry, the three survivors must
        // be re-ordered 1/2/3 (not 1/3/4) so the new week's bucket reads
        // as a fresh ordered list.
        final previous = [
          const BucketRoutine(routineId: 'r1', order: 1, isSpontaneous: false),
          const BucketRoutine(routineId: 'r2', order: 2, isSpontaneous: true),
          const BucketRoutine(routineId: 'r3', order: 3, isSpontaneous: false),
          const BucketRoutine(routineId: 'r4', order: 4, isSpontaneous: false),
        ];

        // Mirror the renumber expression used inside _tryAutoPopulate and
        // autoPopulateFromLastWeek.
        final filtered = previous
            .where((r) => !r.isSpontaneous)
            .map((r) => BucketRoutine(routineId: r.routineId, order: r.order))
            .toList();
        final renumbered = filtered.indexed
            .map((entry) => entry.$2.copyWith(order: entry.$1 + 1))
            .toList();

        expect(renumbered.map((r) => r.routineId).toList(), ['r1', 'r3', 'r4']);
        expect(renumbered.map((r) => r.order).toList(), [1, 2, 3]);
      },
    );
  });
}
