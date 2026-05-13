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

ExerciseSet _makeSet({required int setNumber, bool isCompleted = false}) {
  return ExerciseSet(
    id: 'set-$setNumber',
    workoutExerciseId: 'we-001',
    setNumber: setNumber,
    reps: 10,
    weight: 60.0,
    isCompleted: isCompleted,
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

/// Capturing notifier for M1 widget-level test. Records the weight argument
/// passed to [addSet] so we can assert the warmup filter was applied.
/// All other methods are no-ops (same as [_FixedActiveWorkoutNotifier]).
class _CapturingActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _CapturingActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;

  double? capturedWeight;
  int? capturedReps;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  Future<void> addSet(
    String workoutExerciseId, {
    double? defaultWeight,
    int? defaultReps,
  }) async {
    capturedWeight = defaultWeight;
    capturedReps = defaultReps;
    // Do not mutate state — the widget will observe no new set, which is fine
    // for asserting the pre-fill values that were computed and passed in.
  }

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

    // -------------------------------------------------------------------
    // PR-3 (H2/Q6, H3) — destructive long-press shortcuts removed
    //
    // Earlier builds wired `onLongPress` on TWO surfaces inside the card:
    //
    //   1. Header InkWell (`_ExerciseCardHeader`) → opened the exercise
    //      picker → tapping any exercise IMMEDIATELY swapped (no confirm,
    //      logged sets re-attributed silently). H2/Q6.
    //   2. `_AddSetButton` OutlinedButton → fired `_fillRemaining` (the
    //      same action the visible `_FillRemainingButton` below it
    //      already exposes). H3.
    //
    // Both shortcuts violated the principle that destructive actions
    // should never be fired by undiscoverable gestures (industry has
    // converged AWAY from gesture shortcuts in gym apps per Q6
    // benchmarks).
    //
    // These tests pin the structural fix at the InkWell / OutlinedButton
    // construction site so a future commit re-adding `onLongPress` is
    // caught at compile-time-equivalent (widget-tree assertion). We test
    // by reading the widget tree, not by simulating long-press — the
    // long-press semantics on Flutter's Inkwell are timing-sensitive in
    // tests, but the widget-tree contract is deterministic.
    // -------------------------------------------------------------------
    group('PR-3 (H2/Q6, H3) — long-press shortcuts removed', () {
      testWidgets(
        'header InkWell exposes onTap (open detail) but NOT onLongPress (H2/Q6)',
        (tester) async {
          await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
          await tester.pump();

          // Find the header InkWell — the one wired up to open the
          // exercise detail sheet. There are several InkWells in the
          // tree (every IconButton has one); we identify the header by
          // walking down from the Semantics label that matches the
          // exercise name prefix.
          final headerInkWell = tester
              .widgetList<InkWell>(
                find.descendant(
                  of: find.bySemanticsLabel(
                    RegExp(r'^Exercise: Barbell Bench Press\.'),
                  ),
                  matching: find.byType(InkWell),
                ),
              )
              .firstWhere(
                (w) => w.onTap != null,
                orElse: () => throw StateError(
                  'No tappable InkWell found in header — the header should '
                  'always wire onTap for opening the detail sheet.',
                ),
              );

          // PR-3 H2/Q6 contract: the header InkWell MUST keep onTap (open
          // detail sheet) and MUST NOT set onLongPress (long-press swap
          // shortcut removed).
          expect(
            headerInkWell.onTap,
            isNotNull,
            reason: 'Header tap must still open the exercise detail sheet.',
          );
          expect(
            headerInkWell.onLongPress,
            isNull,
            reason:
                'PR-3 H2/Q6: the long-press-to-swap shortcut on the exercise '
                'name was removed because it was an undiscoverable destructive '
                'gesture (silent re-attribution of logged sets to a different '
                'exercise). The visible swap_horiz icon button is the sole '
                'entry point for swap. If this assertion fails, someone re-'
                'added onLongPress — see BUGS.md PR-3 / H2.',
          );
        },
      );

      testWidgets(
        'Add Set OutlinedButton exposes onPressed but NOT onLongPress (H3)',
        (tester) async {
          await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
          await tester.pump();

          // The Add Set OutlinedButton lives inside a Semantics container
          // identified by 'workout-add-set'.
          final addSetOutlined = tester.widget<OutlinedButton>(
            find.descendant(
              of: find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.identifier == 'workout-add-set',
              ),
              matching: find.byType(OutlinedButton),
            ),
          );

          expect(
            addSetOutlined.onPressed,
            isNotNull,
            reason: 'Add Set must keep its primary tap action.',
          );
          expect(
            addSetOutlined.onLongPress,
            isNull,
            reason:
                'PR-3 H3: the long-press-to-fill-remaining shortcut on the '
                'Add Set button was removed because the visible '
                '_FillRemainingButton renders right below it — having two '
                'affordances for the same action (one invisible) violated '
                'the no-redundant-affordance rule. If this fails, someone '
                're-added the long-press handler — see BUGS.md PR-3 / H3.',
          );
        },
      );
    });

    // -----------------------------------------------------------------------
    // PR-4 / M1 — _computeNewSetDefaults warmup filter
    //
    // `_computeNewSetDefaults` is private to [ExerciseCard]. This widget test
    // verifies it via the public "Add Set" button: seed `lastWorkoutSetsProvider`
    // with a previous session that contains warmup sets before the working set,
    // then tap "Add Set" and assert the notifier receives the WORKING weight (100),
    // not the warmup weight (40). This pins the CARD-level M1 fix path, which is
    // separate from the NOTIFIER-level `startFromRoutine` path covered by unit
    // tests. See BUGS.md PR-4 / M1.
    // -----------------------------------------------------------------------
    group('PR-4 / M1 — Add Set pre-fill skips previous-session warmups', () {
      testWidgets(
        'M1: Add Set pre-fills working weight (100kg), skipping warmup weights '
        '(40kg / 60kg) from the previous session',
        (tester) async {
          // Build an exercise card with ONE existing set (so the second add
          // hits Priority 1 of `_computeNewSetDefaults` — previous-session
          // match). The capturing notifier records the defaultWeight passed to
          // addSet. Seed `lastWorkoutSetsProvider` with [warmup@40, warmup@60,
          // working@100] for exercise-001 to reproduce the M1 bug shape.
          final capturingNotifier = _CapturingActiveWorkoutNotifier(
            _makeState(_makeActiveExercise(setCount: 0)),
          );

          final prevWarmup1 = ExerciseSet(
            id: 'prev-warm-1',
            workoutExerciseId: 'we-prev',
            setNumber: 1,
            weight: 40,
            reps: 12,
            setType: SetType.warmup,
            isCompleted: true,
            createdAt: DateTime(2026, 5, 1),
          );
          final prevWarmup2 = ExerciseSet(
            id: 'prev-warm-2',
            workoutExerciseId: 'we-prev',
            setNumber: 2,
            weight: 60,
            reps: 10,
            setType: SetType.warmup,
            isCompleted: true,
            createdAt: DateTime(2026, 5, 1),
          );
          final prevWorking = ExerciseSet(
            id: 'prev-work-1',
            workoutExerciseId: 'we-prev',
            setNumber: 3,
            weight: 100,
            reps: 8,
            setType: SetType.working,
            isCompleted: true,
            createdAt: DateTime(2026, 5, 1),
          );

          final widget = ProviderScope(
            overrides: [
              activeWorkoutProvider.overrideWith(() => capturingNotifier),
              restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
              profileProvider.overrideWith(() => _KgProfileNotifier()),
              exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
              // Seed previous session with [warmup@40, warmup@60, working@100].
              // The key is 'exercise-001' — the exerciseId used by _testExercise.
              lastWorkoutSetsProvider.overrideWith(
                (ref, _) => Future.value({
                  'exercise-001': [prevWarmup1, prevWarmup2, prevWorking],
                }),
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  child: ExerciseCard(
                    activeExercise: _makeActiveExercise(setCount: 0),
                    reorderMode: false,
                    isFirst: true,
                    isLast: true,
                  ),
                ),
              ),
            ),
          );

          await tester.pumpWidget(widget);
          // Drain the async provider builds for both activeWorkoutProvider
          // and lastWorkoutSetsProvider.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Tap the "Add Set" button by its Semantics identifier.
          final addSetFinder = find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.identifier == 'workout-add-set',
          );
          expect(
            addSetFinder,
            findsOneWidget,
            reason: 'Add Set button must be present',
          );
          await tester.tap(addSetFinder);
          await tester.pump();

          expect(
            capturingNotifier.capturedWeight,
            100.0,
            reason:
                'PR-4 / M1: `_computeNewSetDefaults` must filter previous-session '
                'warmups BEFORE index-matching. With [warmup@40, warmup@60, '
                'working@100], the first working-set match is 100kg — not 40kg '
                '(the warmup at index 0). If this fails, the `.where(setType != '
                'warmup)` filter in `_computeNewSetDefaults` is missing or broken.',
          );
        },
      );
    });

    // -----------------------------------------------------------------------
    // Phase 23 D4 — per-row hint removal (card-level negative coverage).
    //
    // Even with prior-session data seeded into `lastWorkoutSetsProvider`,
    // the ExerciseCard MUST NOT render any of the historical hint strings.
    // Pre-fill is the only consumer of the lastSets lookup now (see
    // `_onAddSet` → `_computeNewSetDefaults`); the per-row hint is gone.
    // -----------------------------------------------------------------------
    group('Phase 23 D4 — per-row hint removal', () {
      testWidgets(
        'should not render any per-row hint text for an exercise with prior data',
        (tester) async {
          // Seed prior-session data so the lookup returns a non-empty
          // list. Pre-Phase-23 this would have rendered "Previous: 100kg
          // × 8" on set 1. Post-Phase-23 the row stays bare.
          final prevWorking = ExerciseSet(
            id: 'prev-work-1',
            workoutExerciseId: 'we-prev',
            setNumber: 1,
            weight: 100,
            reps: 8,
            setType: SetType.working,
            isCompleted: true,
            createdAt: DateTime(2026, 5, 1),
          );
          final widget = ProviderScope(
            overrides: [
              activeWorkoutProvider.overrideWith(
                () => _FixedActiveWorkoutNotifier(
                  _makeState(_makeActiveExercise(setCount: 1)),
                ),
              ),
              restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
              profileProvider.overrideWith(() => _KgProfileNotifier()),
              exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
              lastWorkoutSetsProvider.overrideWith(
                (ref, _) => Future.value({
                  'exercise-001': [prevWorking],
                }),
              ),
            ],
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  child: ExerciseCard(
                    activeExercise: _makeActiveExercise(setCount: 1),
                    reorderMode: false,
                    isFirst: true,
                    isLast: true,
                  ),
                ),
              ),
            ),
          );

          await tester.pumpWidget(widget);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          for (final fragment in const ['Previous:', '= last set']) {
            expect(
              find.textContaining(fragment),
              findsNothing,
              reason:
                  'Phase 23 D4: ExerciseCard must not render the hint '
                  'fragment "$fragment" even with prior-session data '
                  'present. The lastSets lookup feeds only `_onAddSet` '
                  'pre-fill now.',
            );
          }
        },
      );
    });

    // -----------------------------------------------------------------------
    // PR-5 M8 — Info-outline icon size + alpha (header detail affordance)
    //
    // Pre-fix: 14dp at α=0.35 — the icon sat at the visibility threshold,
    // making the "tap header for details" affordance invisible to first-
    // time users. Post-fix: 16dp at α=0.5.
    // -----------------------------------------------------------------------
    group('PR-5 / M8 — info_outline visibility', () {
      testWidgets(
        'header info_outline renders at 16dp with onSurface @ alpha ~0.5',
        (tester) async {
          await tester.pumpWidget(_buildExerciseCard(_makeActiveExercise()));
          await tester.pump();

          // Locate the info_outline Icon descendant of ExerciseCard. There
          // is exactly one — the header detail affordance.
          final infoIcon = tester.widget<Icon>(
            find.descendant(
              of: find.byType(ExerciseCard),
              matching: find.byIcon(Icons.info_outline),
            ),
          );

          expect(
            infoIcon.size,
            16,
            reason:
                'M8 (PR-5): info_outline must render at 16dp. Pre-fix was '
                '14dp — below the visibility threshold for a functional '
                'affordance.',
          );

          // Alpha lives on the Icon's color (`onSurface.withValues(alpha:
          // 0.5)`). We compare opacity within a tolerance window because
          // floating-point alpha is not exactly representable.
          final alpha = infoIcon.color?.a ?? 0;
          expect(
            alpha,
            inInclusiveRange(0.45, 0.55),
            reason:
                'M8 (PR-5): info_outline alpha must be ~0.5 (got $alpha). '
                'Pre-fix was 0.35 — invisible to first-time users.',
          );
        },
      );
    });
  });
}
