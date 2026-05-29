import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/history_week_header.dart';
import 'package:repsaga/features/workouts/ui/workout_history_screen.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _WorkoutHistoryStub extends AsyncNotifier<WorkoutHistoryState>
    implements WorkoutHistoryNotifier {
  _WorkoutHistoryStub({
    required this.workouts,
    this.isLoadingMoreValue = false,
    this.hasMoreValue = false,
  });

  final List<Workout> workouts;
  final bool isLoadingMoreValue;
  final bool hasMoreValue;

  @override
  Future<WorkoutHistoryState> build() async => (
    workouts: workouts,
    isLoadingMore: isLoadingMoreValue,
    hasMore: hasMoreValue,
  );

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> refresh() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Workout> makeWorkouts(int count) {
  return List.generate(count, (i) {
    return Workout.fromJson(
      TestWorkoutFactory.create(
        id: 'workout-$i',
        name: 'Workout $i',
        finishedAt: DateTime.now()
            .subtract(Duration(days: i))
            .toIso8601String(),
      ),
    );
  });
}

/// Two workouts in distinct ISO weeks — used to assert that the sticky
/// week header sliver renders one section per week. Uses fixed local
/// dates so the test is deterministic regardless of when it runs.
List<Workout> makeWorkoutsInTwoWeeks() {
  final weekA = Workout.fromJson(
    TestWorkoutFactory.create(
      id: 'week-a',
      name: 'Week A workout',
      finishedAt: DateTime(2026, 5, 19, 10).toUtc().toIso8601String(),
    ),
  ).copyWith(totalXp: 120, prCount: 0);
  final weekB = Workout.fromJson(
    TestWorkoutFactory.create(
      id: 'week-b',
      name: 'Week B workout',
      finishedAt: DateTime(2026, 5, 26, 10).toUtc().toIso8601String(),
    ),
  ).copyWith(totalXp: 250, prCount: 2);
  return [weekB, weekA];
}

Widget buildTestWidget({
  required List<Workout> workouts,
  bool isLoadingMore = false,
  bool hasMore = false,
}) {
  return ProviderScope(
    overrides: [
      workoutHistoryProvider.overrideWith(
        () => _WorkoutHistoryStub(
          workouts: workouts,
          isLoadingMoreValue: isLoadingMore,
          hasMoreValue: hasMore,
        ),
      ),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const WorkoutHistoryScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — PO-028: loading indicator during load-more
// ---------------------------------------------------------------------------

void main() {
  group('WorkoutHistoryScreen', () {
    testWidgets('shows empty state when no workouts', (tester) async {
      await tester.pumpWidget(buildTestWidget(workouts: []));
      await tester.pump();
      await tester.pump();

      expect(find.text('No workouts yet'), findsOneWidget);
      expect(
        find.text('Your completed workouts will appear here'),
        findsOneWidget,
      );
    });

    testWidgets('shows workout cards when workouts are present', (
      tester,
    ) async {
      final workouts = makeWorkouts(3);
      await tester.pumpWidget(buildTestWidget(workouts: workouts));
      await tester.pump();
      await tester.pump();

      expect(find.text('Workout 0'), findsOneWidget);
      expect(find.text('Workout 1'), findsOneWidget);
      expect(find.text('Workout 2'), findsOneWidget);
    });

    testWidgets(
      'PO-028: shows CircularProgressIndicator in list when isLoadingMore is true',
      (tester) async {
        final workouts = makeWorkouts(5);
        await tester.pumpWidget(
          buildTestWidget(workouts: workouts, isLoadingMore: true),
        );
        await tester.pump();
        await tester.pump();

        // With sticky week headers + 5 cards the load-more sliver sits
        // below the 600dp test viewport. Scroll the list to the bottom so
        // the spinner builds. Same user-visible behaviour the original
        // PO-028 contract pinned — the user perceives the spinner by
        // scrolling toward the load-more boundary.
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1000),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'PO-028: shows CircularProgressIndicator in list when hasMore is true',
      (tester) async {
        final workouts = makeWorkouts(5);
        await tester.pumpWidget(
          buildTestWidget(workouts: workouts, hasMore: true),
        );
        await tester.pump();
        await tester.pump();

        // See the parallel PO-028 test above — scroll the list so the
        // load-more sliver builds inside the viewport.
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1000),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT show load-more indicator when isLoadingMore is false and hasMore is false',
      (tester) async {
        final workouts = makeWorkouts(5);
        await tester.pumpWidget(
          buildTestWidget(
            workouts: workouts,
            isLoadingMore: false,
            hasMore: false,
          ),
        );
        await tester.pump();
        await tester.pump();

        // No loading indicator should appear.
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('shows RefreshIndicator wrapping the list', (tester) async {
      final workouts = makeWorkouts(3);
      await tester.pumpWidget(buildTestWidget(workouts: workouts));
      await tester.pump();
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('history AppBar title reads "History"', (tester) async {
      await tester.pumpWidget(buildTestWidget(workouts: []));
      await tester.pump();

      expect(find.text('History'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Sticky week headers + XP eyebrow + PR diamond
  // -------------------------------------------------------------------------

  group(
    'WorkoutHistoryScreen — sticky week headers + XP eyebrow + PR diamond',
    () {
      testWidgets('renders one sticky week header per ISO week group', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
        );
        await tester.pump();
        await tester.pump();

        // Two distinct weeks → two HistoryWeekHeader widgets.
        expect(find.byType(HistoryWeekHeader), findsNWidgets(2));
      });

      testWidgets('per-card XP eyebrow renders +N XP for each workout', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
        );
        await tester.pump();
        await tester.pump();

        // Both card eyebrows AND week-header roll-ups carry the same "+N XP"
        // text because each week has a single workout — the eyebrow and the
        // roll-up share the same XP total. Pin the eyebrow count by its
        // Semantics identifier rather than the raw text so the assertion
        // distinguishes the card-level signal from the section-header
        // signal.
        final eyebrows = find.bySemanticsIdentifier('history-card-xp-eyebrow');
        expect(eyebrows, findsNWidgets(2));

        // And the per-card eyebrow text values are present in both the card
        // eyebrow AND the week-header roll-up that shares the same XP total
        // — two renders each. Explicit count (not `findsWidgets`) so a
        // regression that drops the card eyebrow while keeping only the
        // roll-up still trips the assertion. See PR #285 Important 12.
        expect(find.text('+120 XP'), findsNWidgets(2));
        expect(find.text('+250 XP'), findsNWidgets(2));
      });

      testWidgets(
        'PR diamond renders only when prCount > 0 (omitted on zero)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
          );
          await tester.pump();
          await tester.pump();

          // Week B workout has prCount: 2 → diamond renders.
          expect(find.text('◆ 2 PR'), findsOneWidget);
          // Week A workout has prCount: 0 → no PR row anywhere.
          expect(find.textContaining('◆ 0'), findsNothing);
        },
      );

      testWidgets('CustomScrollView replaces the flat ListView', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(CustomScrollView), findsOneWidget);
        // No top-level ListView — the redesign migrated to slivers.
        expect(find.byType(ListView), findsNothing);
      });

      testWidgets(
        'current ISO week renders "This Week" instead of the date format',
        (tester) async {
          // Pin "now" to a Wednesday inside the same week as weekB
          // (2026-05-26 falls in the Mon 2026-05-25 → Sun 2026-05-31
          // ISO week). With clock fixed, weekB's group should pick up
          // the "This Week" treatment while weekA keeps the date label.
          final now = DateTime(2026, 5, 27, 10);
          await withClock(Clock.fixed(now), () async {
            await tester.pumpWidget(
              buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
            );
            await tester.pump();
            await tester.pump();

            expect(find.text('This Week'), findsOneWidget);
            expect(find.textContaining('Week of'), findsOneWidget);
          });
        },
      );
    },
  );
}
