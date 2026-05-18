/// Widget tests for the (now-retired) HomeStatusLine.
///
/// Phase 26f T11 stopped wiring `HomeStatusLine` into `HomeScreen`. T12
/// will delete the widget + this test file together. T11 keeps the file
/// compiling but skips every test so the suite stays green.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/home_status_line.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Notifier stubs
// ---------------------------------------------------------------------------

class _PlanStub extends AsyncNotifier<WeeklyPlan?>
    implements WeeklyPlanNotifier {
  _PlanStub(this.plan);
  final WeeklyPlan? plan;

  @override
  Future<WeeklyPlan?> build() async => plan;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryStub extends AsyncNotifier<List<Workout>>
    implements WorkoutHistoryNotifier {
  _HistoryStub(this.workouts);
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

class _ProfileStub extends AsyncNotifier<Profile?> implements ProfileNotifier {
  _ProfileStub(this.profile);
  final Profile? profile;

  @override
  Future<Profile?> build() async => profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Factories
// ---------------------------------------------------------------------------

WeeklyPlan _plan({required List<BucketRoutine> routines}) {
  return WeeklyPlan(
    id: 'plan-001',
    userId: 'user-001',
    weekStart: DateTime(2026, 4, 13),
    routines: routines,
    createdAt: DateTime(2026, 4, 13),
    updatedAt: DateTime(2026, 4, 13),
  );
}

BucketRoutine _bucket({
  required String routineId,
  required int order,
  String? completedWorkoutId,
}) => BucketRoutine(
  routineId: routineId,
  order: order,
  completedWorkoutId: completedWorkoutId,
);

Workout _workout() {
  return Workout.fromJson(
    TestWorkoutFactory.create(finishedAt: '2026-04-10T10:00:00Z'),
  );
}

Widget _build({
  WeeklyPlan? plan,
  List<Workout> workouts = const [],
  Profile? profile,
}) {
  return ProviderScope(
    overrides: [
      weeklyPlanProvider.overrideWith(() => _PlanStub(plan)),
      workoutHistoryProvider.overrideWith(() => _HistoryStub(workouts)),
      // HomeStatusLine derives its "has history" from `workoutCountProvider`
      // via `hasAnyWorkoutProvider` (keeps the widget from rebuilding on
      // every paginated loadMore). Mirror the list length here so the two
      // sources of truth stay aligned in tests.
      workoutCountProvider.overrideWith((ref) => Future.value(workouts.length)),
      profileProvider.overrideWith(() => _ProfileStub(profile)),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: HomeStatusLine()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// All groups skipped — see library docstring above. T12 deletes this file.
const _retiredReason = 'Retired in T12 — HomeStatusLine deleted in 26f';

void main() {
  group('HomeStatusLine - active plan, incomplete', skip: _retiredReason, () {
    testWidgets('shows "X of Y this week" when plan has uncompleted routines', (
      tester,
    ) async {
      await tester.pumpWidget(
        _build(
          plan: _plan(
            routines: [
              _bucket(routineId: 'r-1', order: 1, completedWorkoutId: 'wk-1'),
              _bucket(routineId: 'r-2', order: 2),
              _bucket(routineId: 'r-3', order: 3),
            ],
          ),
          profile: const Profile(
            id: 'user-001',
            displayName: 'Alex',
            weightUnit: 'kg',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Count text uses Text.rich with two spans. Read combined plain text.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final combined = richTexts.map((rt) => rt.text.toPlainText()).join('|');

      expect(combined, contains('1'));
      expect(combined, contains('of 3 this week'));
      // Explicitly NOT the complete copy.
      expect(combined, isNot(contains('Week complete')));
    });

    testWidgets('does not show date header (EEE, MMM d)', (tester) async {
      await tester.pumpWidget(
        _build(
          plan: _plan(routines: [_bucket(routineId: 'r-1', order: 1)]),
        ),
      );
      await tester.pump();
      await tester.pump();

      // None of the legacy date header should render.
      expect(find.textContaining('MON,'), findsNothing);
      expect(find.textContaining('TUE,'), findsNothing);
      expect(find.textContaining('WED,'), findsNothing);
      expect(find.textContaining('THU,'), findsNothing);
      expect(find.textContaining('FRI,'), findsNothing);
      expect(find.textContaining('SAT,'), findsNothing);
      expect(find.textContaining('SUN,'), findsNothing);
    });

    testWidgets(
      'incomplete state is rendered at titleLarge so it outranks hero content',
      (tester) async {
        await tester.pumpWidget(
          _build(
            plan: _plan(
              routines: [
                _bucket(routineId: 'r-1', order: 1, completedWorkoutId: 'wk-1'),
                _bucket(routineId: 'r-2', order: 2),
                _bucket(routineId: 'r-3', order: 3),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Resolve titleLarge from the active theme via the harness context.
        final ctx = tester.element(find.byType(HomeStatusLine));
        final expected = Theme.of(ctx).textTheme.titleLarge;

        // Scope the RichText search to the HomeStatusLine subtree — Material
        // chrome also renders RichTexts. Text.rich wraps the user spans in
        // a DefaultTextStyle-carrying root span (bodyMedium), so the tree is
        // [root 14dp] > [our TextSpan null] > [count span 20dp, suffix span
        // 20dp]. Assert that at least one leaf explicitly carries the
        // titleLarge fontSize; that's the contract that makes the status
        // line outrank the hero below it.
        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.byType(HomeStatusLine),
            matching: find.byType(RichText),
          ),
        );
        final sizes = <double?>[];
        void collect(InlineSpan span) {
          if (span is TextSpan) {
            if (span.style?.fontSize != null) sizes.add(span.style!.fontSize);
            for (final child in span.children ?? const <InlineSpan>[]) {
              collect(child);
            }
          }
        }

        collect(richText.text);
        expect(
          sizes,
          contains(expected?.fontSize),
          reason:
              'HomeStatusLine should render at least one span at '
              'titleLarge (${expected?.fontSize}); got $sizes',
        );
      },
    );
  });

  group('HomeStatusLine - active plan, complete', skip: _retiredReason, () {
    testWidgets(
      'shows "Week complete - Y of Y done" when all bucket routines are done',
      (tester) async {
        await tester.pumpWidget(
          _build(
            plan: _plan(
              routines: [
                _bucket(routineId: 'r-1', order: 1, completedWorkoutId: 'wk-1'),
                _bucket(routineId: 'r-2', order: 2, completedWorkoutId: 'wk-2'),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.textContaining('Week complete'), findsOneWidget);
        expect(find.textContaining('2 of 2 done'), findsOneWidget);
      },
    );

    testWidgets(
      'complete state is rendered at titleLarge so it outranks hero content',
      (tester) async {
        await tester.pumpWidget(
          _build(
            plan: _plan(
              routines: [
                _bucket(routineId: 'r-1', order: 1, completedWorkoutId: 'wk-1'),
                _bucket(routineId: 'r-2', order: 2, completedWorkoutId: 'wk-2'),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final completeFinder = find.textContaining('Week complete');
        final ctx = tester.element(completeFinder);
        final expected = Theme.of(ctx).textTheme.titleLarge;

        final actual = tester.widget<Text>(completeFinder).style;
        expect(actual?.fontSize, expected?.fontSize);
        expect(actual?.fontWeight, FontWeight.w700);
      },
    );
  });

  group('HomeStatusLine - no plan, history exists', skip: _retiredReason, () {
    testWidgets('shows "No plan this week" when history is non-empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _build(
          plan: null,
          workouts: [_workout()],
          profile: const Profile(
            id: 'user-001',
            displayName: 'Alex',
            weightUnit: 'kg',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No plan this week'), findsOneWidget);
    });

    testWidgets('lapsed state stays at titleMedium (muted, not celebratory)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _build(
          plan: null,
          workouts: [_workout()],
          profile: const Profile(
            id: 'user-001',
            displayName: 'Alex',
            weightUnit: 'kg',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final lapsedFinder = find.text('No plan this week');
      final ctx = tester.element(lapsedFinder);
      final expected = Theme.of(ctx).textTheme.titleMedium;

      final actual = tester.widget<Text>(lapsedFinder).style;
      expect(actual?.fontSize, expected?.fontSize);
    });

    testWidgets(
      'shows "No plan this week" when an empty plan exists but history is non-empty',
      (tester) async {
        // An empty plan (no routines) counts as "no plan" for the purposes of
        // the status line.
        await tester.pumpWidget(
          _build(
            plan: _plan(routines: const []),
            workouts: [_workout()],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('No plan this week'), findsOneWidget);
      },
    );
  });

  group(
    'HomeStatusLine - brand new (no plan, no history)',
    skip: _retiredReason,
    () {
      testWidgets('shows display name only when profile has one', (
        tester,
      ) async {
        await tester.pumpWidget(
          _build(
            plan: null,
            workouts: const [],
            profile: const Profile(
              id: 'user-001',
              displayName: 'Alex',
              weightUnit: 'kg',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Alex'), findsOneWidget);
        // No date, no "No plan this week" copy, no count.
        expect(find.text('No plan this week'), findsNothing);
        expect(find.textContaining('this week'), findsNothing);
        expect(find.textContaining('Week complete'), findsNothing);
      });

      testWidgets(
        'renders SizedBox.shrink equivalent when display name is null',
        (tester) async {
          await tester.pumpWidget(
            _build(
              plan: null,
              workouts: const [],
              profile: const Profile(id: 'user-001', weightUnit: 'kg'),
            ),
          );
          await tester.pump();
          await tester.pump();

          // No text is emitted at all.
          expect(find.textContaining('No plan'), findsNothing);
          expect(find.textContaining('week'), findsNothing);
        },
      );

      testWidgets(
        'renders SizedBox.shrink equivalent when display name is empty string',
        (tester) async {
          await tester.pumpWidget(
            _build(
              plan: null,
              workouts: const [],
              profile: const Profile(
                id: 'user-001',
                displayName: '',
                weightUnit: 'kg',
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.textContaining('No plan'), findsNothing);
        },
      );
    },
  );
}
