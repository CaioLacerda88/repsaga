import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/history_week_header.dart';
import 'package:repsaga/features/workouts/ui/workout_history_screen.dart';
import 'package:repsaga/shared/widgets/reward_accent.dart';

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

/// A stub that lets tests push new [WorkoutHistoryState] snapshots mid-test
/// via [push], so the reactivity contract (isLoadingMore flag transition
/// rebuilds the spinner WITHOUT changing the workouts list) can be pinned.
class _MutableWorkoutHistoryStub extends AsyncNotifier<WorkoutHistoryState>
    implements WorkoutHistoryNotifier {
  _MutableWorkoutHistoryStub(this._initial);

  final WorkoutHistoryState _initial;

  @override
  Future<WorkoutHistoryState> build() async => _initial;

  void push(WorkoutHistoryState next) {
    state = AsyncData(next);
  }

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

          // Week B workout has prCount: 2 → diamond renders with ICU
          // plural ("2 PRs", not "2 PR"). Per PR #285 device-verification
          // finding the historyCardPrCount key now uses {count, plural,
          // =1{1 PR} other{{count} PRs}} so 1 stays singular and ≥2
          // renders the plural form. See lib/l10n/app_en.arb.
          expect(find.text('◆ 2 PRs'), findsOneWidget);
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

      // -----------------------------------------------------------------------
      // Reactivity contract — PR #285 Blocker 2
      // The spinner must appear when isLoadingMore transitions false → true
      // WITHOUT any change to the workouts list, proving the state-class emit
      // (not a stale notifier getter) drives the rebuild.
      // -----------------------------------------------------------------------

      testWidgets(
        'PR #285 Blocker 2: spinner appears when isLoadingMore transitions '
        'false → true without workouts-list change',
        (tester) async {
          final workouts = makeWorkoutsInTwoWeeks();
          // Initial state: list fully loaded (hasMore: false, isLoadingMore:
          // false) — no spinner. This baseline guarantees the subsequent
          // spinner is caused by the isLoadingMore flag flip alone, not by
          // the hasMore flag being true at pump-time.
          final stub = _MutableWorkoutHistoryStub((
            workouts: workouts,
            isLoadingMore: false,
            hasMore: false,
          ));

          await tester.pumpWidget(
            ProviderScope(
              overrides: [workoutHistoryProvider.overrideWith(() => stub)],
              child: TestMaterialApp(
                theme: AppTheme.dark,
                home: const WorkoutHistoryScreen(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          // Baseline: no spinner (hasMore: false, isLoadingMore: false).
          expect(find.byType(CircularProgressIndicator), findsNothing);

          // Mutate the state — same workouts, only isLoadingMore flips to true.
          // This simulates the mid-loadMore window where the API call is
          // in-flight. The workouts list is identical — the rebuild must be
          // driven by the state-class emit, not a list diff.
          stub.push((workouts: workouts, isLoadingMore: true, hasMore: false));
          await tester.pump();

          // Scroll to bottom so the load-more sliver enters the viewport.
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -1000),
          );
          await tester.pump();

          // The spinner must now be visible — the rebuild was driven by the
          // isLoadingMore flag transition in the emitted state object, not by
          // a workouts-list diff.
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        },
      );

      // -----------------------------------------------------------------------
      // Reward-scarcity contract — PR #285 UX-critic Blocker 5
      // The PR diamond must be rendered via RewardAccent (heroGold scope),
      // not as a raw Text or Icon with a hardcoded color.
      // -----------------------------------------------------------------------

      testWidgets(
        'PR diamond is rendered via RewardAccent widget (reward-scarcity '
        'contract)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
          );
          await tester.pump();
          await tester.pump();

          // weekB has prCount: 2 → diamond is in the tree.
          // Assert the Text is a descendant of a RewardAccent instance so the
          // heroGold color is provably gated through the scarcity widget,
          // not a raw AppColors.heroGold reference. check_reward_accent.sh
          // gates the source, this test gates the rendered tree.
          expect(
            find.descendant(
              of: find.byType(RewardAccent),
              matching: find.textContaining('PR'),
            ),
            findsAtLeastNWidgets(1),
          );
        },
      );

      // -----------------------------------------------------------------------
      // XP eyebrow color — hotViolet (daily-driver register, NOT heroGold)
      // -----------------------------------------------------------------------

      // -----------------------------------------------------------------------
      // PR diamond effective rendered color — PR #285 device-verification.
      // `AppTextStyles.numericSmall` bakes `color: textDim` which would
      // override RewardAccent's heroGold via the
      // `DefaultTextStyle.merge(style: TextStyle(color: heroGold))` → Text's
      // own style merge (explicit-color-wins). The fix strips the baked
      // color at the call site by composing a TextStyle WITHOUT a `color:`
      // — letting the ambient DefaultTextStyle's heroGold win. The lint
      // (`check_reward_accent.sh`) gates the source; this test gates the
      // rendered tree.
      // -----------------------------------------------------------------------
      testWidgets(
        'PR diamond effective color is heroGold (not textDim) — PR #285',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
          );
          await tester.pump();
          await tester.pump();

          // weekB has prCount: 2 → diamond renders. Find the RichText
          // descendant of the PR diamond's Semantics container — that's
          // the leaf paint node Flutter actually rasterizes, with the
          // merged effective style sitting on its `text.style`.
          final diamondContainer = find.bySemanticsIdentifier(
            'history-card-pr-diamond',
          );
          expect(diamondContainer, findsOneWidget);
          final richText = find.descendant(
            of: diamondContainer,
            matching: find.byType(RichText),
          );
          expect(richText, findsOneWidget);
          final rendered = tester.widget<RichText>(richText);
          // The effective color sits on the root TextSpan's style after
          // the DefaultTextStyle merge resolves. RewardAccent's heroGold
          // wins because the per-call-site TextStyle does NOT bake a
          // color of its own — the regression we're guarding against is
          // numericSmall's textDim overriding the gold scope.
          expect(rendered.text.style?.color, AppColors.heroGold);
        },
      );

      testWidgets('XP eyebrow text uses hotViolet color (not heroGold)', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(workouts: makeWorkoutsInTwoWeeks()),
        );
        await tester.pump();
        await tester.pump();

        // Find the Text widget inside the first history-card-xp-eyebrow
        // Semantics container and verify its resolved color is hotViolet
        // (with alpha 0.85). The color assertion gates that the eyebrow
        // is not accidentally painted heroGold (which would erode
        // reward-scarcity — XP is an expected outcome, not a rare prize).
        final eyebrowContainer = find.bySemanticsIdentifier(
          'history-card-xp-eyebrow',
        );
        expect(eyebrowContainer, findsAtLeastNWidgets(1));
        final eyebrowText = find.descendant(
          of: eyebrowContainer.first,
          matching: find.byType(Text),
        );
        expect(eyebrowText, findsOneWidget);
        final textWidget = tester.widget<Text>(eyebrowText);
        expect(
          textWidget.style?.color,
          AppColors.hotViolet.withValues(alpha: 0.85),
        );
      });
    },
  );
}
