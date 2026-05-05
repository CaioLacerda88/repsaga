/// Widget tests for [ExerciseCard]. The PR #152 fix #3 motivation is in this
/// file: pin the contracts that PREVENT the giant `flt-tappable role="group"`
/// merge bug — where the header InkWell, the column-header letters
/// (SET/WEIGHT/REPS), and the per-row Semantics all collapsed into ONE
/// merged AOM node that intercepted every tap. See `tasks/lessons.md`
/// "Semantics container/explicitChildNodes is needed at EVERY tap-merging
/// boundary, not just one place".
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/exercise_card.dart';

import '../../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Barbell Bench Press',
  muscleGroup: MuscleGroup.chest,
  equipmentType: EquipmentType.barbell,
  isDefault: true,
  createdAt: DateTime(2026),
);

final _testWorkout = Workout(
  id: 'workout-001',
  userId: 'user-001',
  name: 'Push Day',
  startedAt: DateTime.now().toUtc(),
  isActive: true,
  createdAt: DateTime.now().toUtc(),
);

ExerciseSet _makeSet({required int setNumber}) {
  return ExerciseSet(
    id: 'set-$setNumber',
    workoutExerciseId: 'we-001',
    setNumber: setNumber,
    reps: 10,
    weight: 60.0,
    isCompleted: false,
    setType: SetType.working,
    createdAt: DateTime.now().toUtc(),
  );
}

ActiveWorkoutExercise _makeActiveExercise({int setCount = 2}) {
  return ActiveWorkoutExercise(
    workoutExercise: WorkoutExercise(
      id: 'we-001',
      workoutId: 'workout-001',
      exerciseId: 'exercise-001',
      order: 1,
      exercise: _testExercise,
    ),
    sets: List.generate(setCount, (i) => _makeSet(setNumber: i + 1)),
  );
}

ActiveWorkoutState _makeState(ActiveWorkoutExercise activeExercise) {
  return ActiveWorkoutState(workout: _testWorkout, exercises: [activeExercise]);
}

// ---------------------------------------------------------------------------
// Provider stubs (mirror the pattern in active_workout_fill_test.dart)
// ---------------------------------------------------------------------------

class _FixedActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _FixedActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NullRestTimerNotifier extends Notifier<RestTimerState?>
    implements RestTimerNotifier {
  @override
  RestTimerState? build() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KgProfileNotifier extends AsyncNotifier<Profile?>
    implements ProfileNotifier {
  @override
  Future<Profile?> build() async => const Profile(id: 'u1', weightUnit: 'kg');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildExerciseCard(ActiveWorkoutExercise activeExercise) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(_makeState(activeExercise)),
      ),
      restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
      exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        // 800dp width keeps the data table from overflowing in the test
        // harness — well above the 360dp Brazilian-mid-market floor.
        body: SizedBox(
          width: 800,
          child: ExerciseCard(
            activeExercise: activeExercise,
            reorderMode: false,
            isFirst: true,
            isLast: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ExerciseCard', () {
    group('header semantics — PR #152 fix #3 contracts', () {
      // -----------------------------------------------------------------
      // The bug: the InkWell wrapping the exercise title carried a
      // `Semantics(label: 'Exercise: ...')` WITHOUT `container: true` /
      // `explicitChildNodes: true`. Without the boundary, the header label,
      // the inner Row Text, the IconButton tooltips (Swap/Remove), AND the
      // sibling `_SetColumnHeaders` Text widgets (SET/WEIGHT/REPS) all
      // merged into ONE giant `flt-tappable role="group"` in the AOM
      // (Playwright artifact: `aria-label="Exercise: ... Tap for details.
      // ... Barbell Bench Press ... Swap exercise ... Remove exercise ...
      // SET ... WEIGHT ... REPS"`). That merged group overlaid the entire
      // card and intercepted every tap — taps on stepper +/- buttons or
      // value zones landed on the merged group instead, frequently
      // producing the "Enter weight" dialog when the test wanted to open
      // the exercise detail sheet.
      //
      // This test pins the structural fix: the header label MUST live on a
      // SemanticsNode that does NOT also carry the SET/WEIGHT/REPS column-
      // header text. They must be separate semantic regions.
      // -----------------------------------------------------------------
      testWidgets(
        'header InkWell semantics does NOT merge with column header letters',
        (tester) async {
          final handle = tester.ensureSemantics();

          await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
          await tester.pump(); // drain microtask for async provider build

          // Find the header SemanticsNode — its label starts with "Exercise:"
          // (l10n.exerciseSemanticsLabel("Barbell Bench Press") →
          // "Exercise: Barbell Bench Press. Tap for details. Long press to
          // swap.").
          final headerFinder = find.bySemanticsLabel(
            RegExp(r'^Exercise: Barbell Bench Press\.'),
          );
          expect(
            headerFinder,
            findsOneWidget,
            reason:
                'The header InkWell must expose ONE SemanticsNode whose '
                'label starts with "Exercise:" — that is the e2e contract '
                'for `role=group[name*="Exercise: <name>. Tap for details"]`.',
          );

          final SemanticsData headerData = tester
              .getSemantics(headerFinder)
              .getSemanticsData();
          final mergedLabel = headerData.label;

          // The header label must NOT contain the column-header letters.
          // If it does, _SetColumnHeaders' Text widgets were absorbed into
          // the header's Semantics group — the exact merge bug from PR
          // #152 fix #3.
          for (final colHeader in const ['SET', 'WEIGHT', 'REPS']) {
            expect(
              mergedLabel.contains(colHeader),
              isFalse,
              reason:
                  'Header SemanticsNode label "$mergedLabel" contains the '
                  'column-header letter "$colHeader". This means the '
                  '_SetColumnHeaders Text widgets merged INTO the header '
                  'group — the exact regression that caused PR #152 e2e '
                  'failures (taps on the card landed on a giant merged '
                  'tappable region instead of the intended target). Fix: '
                  'keep _SetColumnHeaders wrapped in ExcludeSemantics and '
                  'the header InkWell wrapped in '
                  'Semantics(container: true, explicitChildNodes: true).',
            );
          }

          // Synchronous dispose — addTearDown runs AFTER Flutter's
          // _endOfTestVerifications which complains about active handles.
          handle.dispose();
        },
      );

      // -----------------------------------------------------------------
      // The header InkWell is the canonical tap target for opening the
      // exercise detail sheet. With the fix in place
      // (Semantics(container: true, explicitChildNodes: true) wrapping the
      // InkWell, plus ExcludeSemantics on the visual title text and on
      // _SetColumnHeaders), the header label, the column headers, AND any
      // sibling tap target should NEVER co-occupy a single AOM node.
      //
      // This second test pins the inverse contract: walk the semantics
      // tree under the card and assert there is NO SemanticsNode with
      // action=tap whose label MERGES the header text with the column
      // header letters. Such a node would mean the AOM has built the
      // giant `flt-tappable role="group"` that intercepted all card taps
      // in PR #152's e2e failures.
      // -----------------------------------------------------------------
      testWidgets(
        'no SemanticsNode merges the header InkWell tap action with the '
        'column header letters into a single flt-tappable region',
        (tester) async {
          final handle = tester.ensureSemantics();

          await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
          await tester.pump();

          // The semantics tree we want lives on the binding's render-object
          // pipeline owner. `rootPipelineOwner` is the meta-owner — its
          // `semanticsOwner` is null in the test harness; the populated
          // owner sits on `pipelineOwner` (deprecated alias, no drop-in
          // replacement that exposes a non-null semanticsOwner from the
          // test binding — keep using it).
          final SemanticsOwner owner =
              // ignore: deprecated_member_use
              tester.binding.pipelineOwner.semanticsOwner!;
          final List<String> badNodeLabels = [];
          void walk(SemanticsNode node) {
            final data = node.getSemanticsData();
            // Catch the regression directly: a SemanticsNode whose label
            // simultaneously carries the "Exercise:" prefix AND the
            // column-header letters is the merged group from the bug. We
            // also flag any tappable node whose label simultaneously holds
            // both signals — this is exactly what the artifact's
            // `<flt-semantics role="group" flt-tappable aria-label="…
            // Exercise: … SET WEIGHT REPS">` looked like.
            final lbl = data.label;
            final hasHeader = lbl.startsWith('Exercise:');
            final hasColHeaders =
                lbl.contains('SET') &&
                lbl.contains('WEIGHT') &&
                lbl.contains('REPS');
            if (hasHeader && hasColHeaders) {
              badNodeLabels.add(lbl);
            }
            node.visitChildren((child) {
              walk(child);
              return true;
            });
          }

          walk(owner.rootSemanticsNode!);

          expect(
            badNodeLabels,
            isEmpty,
            reason:
                'Found ${badNodeLabels.length} SemanticsNode(s) whose label '
                'merges the header "Exercise: …" prefix with the column '
                'header letters SET/WEIGHT/REPS. This is the exact AOM '
                'merge bug that intercepted every tap on the card in PR '
                '#152\'s e2e failures. First offending label: '
                '"${badNodeLabels.isEmpty ? '<none>' : badNodeLabels.first}". '
                'Fix: keep _SetColumnHeaders wrapped in ExcludeSemantics '
                'and the header InkWell wrapped in '
                'Semantics(container: true, explicitChildNodes: true).',
          );

          handle.dispose();
        },
      );
    });
  });
}
