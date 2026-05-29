import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/ui/workout_detail_screen.dart';
import 'package:repsaga/shared/widgets/reward_accent.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

class _ProfileNotifierWithUnit extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  _ProfileNotifierWithUnit(this._weightUnit);
  final String _weightUnit;

  @override
  Future<Profile?> build() async =>
      Profile(id: 'user-001', weightUnit: _weightUnit);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  WorkoutDetail makeDetail() {
    // Phase 15f Stage 6: parseWorkoutDetail resolves exercises from the
    // `exerciseMap` parameter keyed on exercise_id, not from an embedded
    // `'exercise'` field in the workout_exercises JSON.
    return WorkoutRepository.parseWorkoutDetail(
      {
        ...TestWorkoutFactory.create(id: 'w-1'),
        'workout_exercises': [
          {
            ...TestWorkoutExerciseFactory.create(id: 'we-1', exerciseId: 'e-1'),
            'sets': [
              TestSetFactory.create(
                id: 'set-1',
                workoutExerciseId: 'we-1',
                setNumber: 1,
              ),
              TestSetFactory.create(
                id: 'set-2',
                workoutExerciseId: 'we-1',
                setNumber: 2,
              ),
            ],
          },
        ],
      },
      {
        'e-1': Exercise.fromJson(
          TestExerciseFactory.create(id: 'e-1', name: 'Bench Press'),
        ),
      },
    );
  }

  Widget buildTestWidget({required List<Override> overrides}) {
    return ProviderScope(
      overrides: overrides,
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutDetailScreen(workoutId: 'w-1'),
      ),
    );
  }

  // The PR badge on a set row is an `AppIcons.levelUp` SVG rendered inside
  // a `RewardAccent` — it replaces the pre-17.0d `Icon(Icons.emoji_events)`.
  // Counting `RewardAccent` ancestors is the most stable selector: the glyph
  // may change (icon-set-v2) but the scarcity-widget wrapper won't.
  Finder prTrophyFinder() => find.descendant(
    of: find.byType(RewardAccent),
    matching: find.byType(SvgPicture),
  );

  group('WorkoutDetailScreen PR badges', () {
    testWidgets('shows trophy icon on PR sets', (tester) async {
      final detail = makeDetail();

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            workoutDetailProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(detail)),
            workoutPRSetIdsProvider(
              'w-1',
            ).overrideWith((ref) => Future.value({'set-1'})),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // set-1 is a PR: trophy icon should appear
      expect(prTrophyFinder(), findsOneWidget);
    });

    testWidgets('shows set number text on non-PR sets', (tester) async {
      final detail = makeDetail();

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            workoutDetailProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(detail)),
            workoutPRSetIdsProvider(
              'w-1',
            ).overrideWith((ref) => Future.value({'set-1'})),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // set-2 is not a PR: its set number '2.' should be visible
      expect(find.text('2.'), findsOneWidget);
      // set-1 is a PR so '1.' should not be shown
      expect(find.text('1.'), findsNothing);
    });

    testWidgets('shows no trophy icons when PR set is empty', (tester) async {
      final detail = makeDetail();

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            workoutDetailProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(detail)),
            workoutPRSetIdsProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(<String>{})),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // No PR sets: no trophy icons at all
      expect(prTrophyFinder(), findsNothing);
      // Both set numbers shown
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets(
      'shows no trophy icons while workoutPRSetIdsProvider is loading',
      (tester) async {
        final detail = makeDetail();
        // Never completes during this test — simulates in-flight async fetch.
        final completer = Completer<Set<String>>();

        await tester.pumpWidget(
          buildTestWidget(
            overrides: [
              workoutDetailProvider(
                'w-1',
              ).overrideWith((ref) => Future.value(detail)),
              workoutPRSetIdsProvider(
                'w-1',
              ).overrideWith((ref) => completer.future),
            ],
          ),
        );
        // One pump: workout detail resolves, but PR provider is still loading.
        await tester.pump();
        await tester.pump();

        // Workout content is visible.
        expect(find.text('Bench Press'), findsOneWidget);
        // No trophy icons rendered during loading state.
        expect(prTrophyFinder(), findsNothing);

        // Resolve the completer to avoid pending timer assertion.
        completer.complete({'set-1'});
        await tester.pump();
        await tester.pump();

        // After resolution, badge appears for set-1.
        expect(prTrophyFinder(), findsOneWidget);
      },
    );

    testWidgets('trophy icon is rendered at 18dp', (tester) async {
      final detail = makeDetail();

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            workoutDetailProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(detail)),
            workoutPRSetIdsProvider(
              'w-1',
            ).overrideWith((ref) => Future.value({'set-1'})),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      final trophy = tester.widget<SvgPicture>(prTrophyFinder());
      expect(trophy.width, 18.0);
      expect(trophy.height, 18.0);
    });
  });

  group('WorkoutDetailScreen weight unit threading', () {
    // Fake workout: 3 completed sets at 60/80/100 × 10/8/5.
    // Total volume = 600 + 640 + 500 = 1,740.
    WorkoutDetail makeVolumeDetail() {
      return WorkoutRepository.parseWorkoutDetail(
        {
          ...TestWorkoutFactory.create(id: 'w-1', name: 'Push Day'),
          'workout_exercises': [
            {
              ...TestWorkoutExerciseFactory.create(
                id: 'we-1',
                exerciseId: 'e-1',
              ),
              'sets': [
                TestSetFactory.create(
                  id: 'set-1',
                  workoutExerciseId: 'we-1',
                  setNumber: 1,
                  weight: 60.0,
                  reps: 10,
                ),
                TestSetFactory.create(
                  id: 'set-2',
                  workoutExerciseId: 'we-1',
                  setNumber: 2,
                  weight: 80.0,
                  reps: 8,
                ),
                TestSetFactory.create(
                  id: 'set-3',
                  workoutExerciseId: 'we-1',
                  setNumber: 3,
                  weight: 100.0,
                  reps: 5,
                ),
              ],
            },
          ],
        },
        {
          'e-1': Exercise.fromJson(
            TestExerciseFactory.create(id: 'e-1', name: 'Bench Press'),
          ),
        },
      );
    }

    testWidgets('Per-set weight row shows kg suffix when profile is kg', (
      tester,
    ) async {
      final detail = makeVolumeDetail();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workoutDetailProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(detail)),
            workoutPRSetIdsProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(<String>{})),
            profileProvider.overrideWith(() => _ProfileNotifierWithUnit('kg')),
          ],
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: const WorkoutDetailScreen(workoutId: 'w-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Per-set rows: "60 kg", "80 kg", "100 kg".
      expect(find.text('60 kg'), findsOneWidget);
      expect(find.text('80 kg'), findsOneWidget);
      expect(find.text('100 kg'), findsOneWidget);

      // Total volume footer: 60*10 + 80*8 + 100*5 = 1,740.
      expect(find.text('Total Volume: 1,740 kg'), findsOneWidget);

      // No lbs anywhere.
      expect(find.textContaining('lbs'), findsNothing);
    });

    // -----------------------------------------------------------------
    // 48dp summary strip — XP (hotViolet) + PR (heroGold via RewardAccent)
    // -----------------------------------------------------------------

    /// Helper: rebuilds [makeDetail] with explicit XP + PR overrides on the
    /// returned `workout` so the strip can be asserted at known values.
    /// Post-PR-#285 the prCount on the strip is sourced from
    /// `workout.prCount` (not the `workoutPRSetIdsProvider` length) —
    /// single source of truth shared with the History feed's per-card
    /// diamond.
    WorkoutDetail makeDetailWithXp({required int totalXp, int prCount = 0}) {
      final detail = makeDetail();
      return (
        workout: detail.workout.copyWith(totalXp: totalXp, prCount: prCount),
        exercises: detail.exercises,
        setsByExercise: detail.setsByExercise,
      );
    }

    testWidgets(
      '48dp summary strip renders +N XP and M PRs above exercise cards',
      (tester) async {
        final detail = makeDetailWithXp(totalXp: 340, prCount: 2);

        await tester.pumpWidget(
          buildTestWidget(
            overrides: [
              workoutDetailProvider(
                'w-1',
              ).overrideWith((ref) => Future.value(detail)),
              workoutPRSetIdsProvider(
                'w-1',
              ).overrideWith((ref) => Future.value({'set-1', 'set-2'})),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        // The strip Text.rich splits XP from PRs across two spans so the
        // colors can be assigned independently (hotViolet vs heroGold via
        // RewardAccent). The XP + separator live as inline TextSpans on
        // the host RichText (matched via textContaining since the host's
        // rendered text concatenates "+340 XP · "); the PR portion is a
        // WidgetSpan wrapping a Text widget that surfaces as its own
        // discrete `Text("2 PRs")`. Assert both render, plus the strip's
        // Semantics identifier is mounted.
        expect(find.textContaining('+340 XP'), findsOneWidget);
        expect(find.text('2 PRs'), findsOneWidget);
        expect(
          find.bySemanticsIdentifier('history-detail-strip'),
          findsOneWidget,
        );

        // Reward-scarcity contract: the PR portion of the strip must be
        // rendered inside a RewardAccent widget (heroGold gated through the
        // scarcity scope). A raw AppColors.heroGold reference would bypass
        // the reward-scarcity audit script — this type check pins the tree.
        // The WidgetSpan child is a Text wrapping the PR count; its nearest
        // RewardAccent ancestor must exist.
        expect(
          find.descendant(
            of: find.byType(RewardAccent),
            matching: find.textContaining('PRs'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('strip hides entirely when both totalXp and prCount are zero', (
      tester,
    ) async {
      final detail = makeDetailWithXp(totalXp: 0);

      await tester.pumpWidget(
        buildTestWidget(
          overrides: [
            workoutDetailProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(detail)),
            workoutPRSetIdsProvider(
              'w-1',
            ).overrideWith((ref) => Future.value(<String>{})),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // No "+0 XP" anywhere — strip collapsed (no negative confirmation).
      expect(find.text('+0 XP'), findsNothing);
      expect(find.textContaining('PRs'), findsNothing);
    });

    testWidgets(
      'strip renders XP-only (no PR span) when prCount is zero but XP > 0',
      (tester) async {
        final detail = makeDetailWithXp(totalXp: 120);

        await tester.pumpWidget(
          buildTestWidget(
            overrides: [
              workoutDetailProvider(
                'w-1',
              ).overrideWith((ref) => Future.value(detail)),
              workoutPRSetIdsProvider(
                'w-1',
              ).overrideWith((ref) => Future.value(<String>{})),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        // XP span renders, PR span omitted. When prCount == 0 the
        // Text.rich has only the single XP TextSpan, so the host
        // RichText's text is exactly "+120 XP" (no trailing separator).
        expect(find.text('+120 XP'), findsOneWidget);
        expect(find.textContaining('PRs'), findsNothing);
      },
    );

    testWidgets(
      'Per-set weight row and total flip to lbs when profile weightUnit '
      'is lbs',
      (tester) async {
        final detail = makeVolumeDetail();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workoutDetailProvider(
                'w-1',
              ).overrideWith((ref) => Future.value(detail)),
              workoutPRSetIdsProvider(
                'w-1',
              ).overrideWith((ref) => Future.value(<String>{})),
              profileProvider.overrideWith(
                () => _ProfileNotifierWithUnit('lbs'),
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: const WorkoutDetailScreen(workoutId: 'w-1'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Stored values are in the user's chosen unit — no conversion, only
        // the suffix flips. The numeric part is identical to the kg test.
        expect(find.text('60 lbs'), findsOneWidget);
        expect(find.text('80 lbs'), findsOneWidget);
        expect(find.text('100 lbs'), findsOneWidget);

        // Total volume footer: same numeric value, different suffix.
        expect(find.text('Total Volume: 1,740 lbs'), findsOneWidget);

        // And kg must not appear anywhere in the rendered tree.
        expect(find.textContaining(' kg'), findsNothing);
      },
    );
  });
}
