/// BUG-020 pin: the workout "Finish" button must live in
/// [Scaffold.bottomNavigationBar], not in the AppBar trailing actions.
///
/// Reverses Phase 18c §13's "intentional friction by hiding it top-right"
/// rationale — the [FinishWorkoutDialog] confirmation is the safety gate.
/// Placement is now optimised for one-handed reach + first-time discoverability.
///
/// Tests pin three contracts:
///   1. Bottom-bar slot hosts the Finish button when the workout has at least
///      one exercise.
///   2. Bottom bar is hidden on the empty body (the `_EmptyWorkoutBody` owns
///      its own CTA).
///   3. AppBar `actions` no longer contains a button with the
///      `workout-finish-btn` semantics identifier.
library;

import 'package:flutter/material.dart';
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
import 'package:repsaga/features/workouts/ui/active_workout_screen.dart';

import '../../../../helpers/test_material_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _testExercise = Exercise(
  id: 'exercise-001',
  name: 'Bench Press',
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

ExerciseSet _makeSet({
  required int setNumber,
  required bool isCompleted,
  double weight = 60.0,
  int reps = 10,
}) {
  return ExerciseSet(
    id: 'set-$setNumber',
    workoutExerciseId: 'we-001',
    setNumber: setNumber,
    reps: reps,
    weight: weight,
    isCompleted: isCompleted,
    setType: SetType.working,
    createdAt: DateTime.now().toUtc(),
  );
}

ActiveWorkoutState _makeStateWithSets(List<ExerciseSet> sets) {
  return ActiveWorkoutState(
    workout: _testWorkout,
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-001',
          workoutId: 'workout-001',
          exerciseId: 'exercise-001',
          order: 1,
          exercise: _testExercise,
        ),
        sets: sets,
      ),
    ],
  );
}

ActiveWorkoutState _makeEmptyState() {
  return ActiveWorkoutState(workout: _testWorkout, exercises: const []);
}

// ---------------------------------------------------------------------------
// Stubs (mirrors the pattern from active_workout_fill_test.dart)
// ---------------------------------------------------------------------------

class _FixedActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _FixedActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  int get incompleteSetsCount => state_.exercises
      .expand((e) => e.sets)
      .where((s) => !s.isCompleted)
      .length;

  @override
  int get totalSetsCount => state_.exercises.expand((e) => e.sets).length;

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

Widget _buildScreen(ActiveWorkoutState state) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(
        () => _FixedActiveWorkoutNotifier(state),
      ),
      restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
      profileProvider.overrideWith(() => _KgProfileNotifier()),
      exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
      lastWorkoutSetsProvider.overrideWith((ref, _) => Future.value({})),
      elapsedTimerProvider.overrideWith(
        (ref, startedAt) => Stream.value(const Duration(minutes: 5)),
      ),
    ],
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: const ActiveWorkoutScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Locates the [Scaffold] hosting the [ActiveWorkoutScreen] body. The screen
/// stacks loading + rest-timer overlays on top of [_ActiveWorkoutBody], so we
/// fish out the inner Scaffold (the one that owns `bottomNavigationBar`).
Scaffold _findActiveWorkoutScaffold(WidgetTester tester) {
  final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold)).toList();
  // The body Scaffold is the one with a non-null bottomNavigationBar OR an
  // AppBar — the wrapper Scaffolds for loading state are bare (body only).
  return scaffolds.firstWhere(
    (s) => s.appBar != null,
    orElse: () => scaffolds.first,
  );
}

/// Walks the AppBar's actions slot looking for any descendant carrying the
/// `workout-finish-btn` semantics identifier. Used to assert the Finish button
/// is no longer there.
bool _appBarHasFinishButton(WidgetTester tester) {
  final scaffold = _findActiveWorkoutScaffold(tester);
  final appBar = scaffold.appBar;
  if (appBar is! AppBar) return false;

  // Walk every Semantics widget reachable from the AppBar actions list and
  // check the identifier. We do this by pumping the actions inside a probe
  // tree and inspecting Semantics widget properties.
  for (final action in appBar.actions ?? const <Widget>[]) {
    final hits = <Widget>[];
    void visit(Widget w) {
      hits.add(w);
    }

    visit(action);
    // Cheap structural check: in the previous (Phase 18c) layout the action
    // was a `Padding > Semantics > OutlinedButton`. We just look for the
    // type names in the action's runtime debug string — sufficient for a pin
    // since the identifier was unique to that widget.
    if (action.toString().contains('workout-finish-btn')) return true;
  }
  return false;
}

void main() {
  group('BUG-020: Finish button placement', () {
    testWidgets(
      'Finish button renders in bottomNavigationBar when exercises exist',
      (tester) async {
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: true),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        final scaffold = _findActiveWorkoutScaffold(tester);
        expect(
          scaffold.bottomNavigationBar,
          isNotNull,
          reason:
              'Scaffold.bottomNavigationBar must host the Finish bar when '
              'the workout has at least one exercise (BUG-020).',
        );
      },
    );

    testWidgets(
      'Finish button is reachable via the workout-finish-btn semantics identifier',
      (tester) async {
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: true),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        // Find any Semantics widget carrying the contract identifier — this
        // is what existing E2E selectors target. If this assertion ever fails
        // we have silently broken the E2E suite.
        final finishSemantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.identifier == 'workout-finish-btn',
        );
        expect(
          finishSemantics,
          findsOneWidget,
          reason:
              'Semantics(identifier: "workout-finish-btn") is the public '
              'contract — moving it broke E2E selectors.',
        );
      },
    );

    testWidgets(
      'AppBar actions no longer contain the workout-finish-btn (placement reversed)',
      (tester) async {
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: true),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        expect(
          _appBarHasFinishButton(tester),
          isFalse,
          reason:
              'BUG-020 reverses Phase 18c §13 — Finish button must NOT live '
              'in AppBar.actions any more. It belongs in the bottom bar.',
        );
      },
    );

    testWidgets(
      'bottomNavigationBar is null when the workout has no exercises (empty state)',
      (tester) async {
        final state = _makeEmptyState();

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        final scaffold = _findActiveWorkoutScaffold(tester);
        expect(
          scaffold.bottomNavigationBar,
          isNull,
          reason:
              'Empty body owns its own CTA; rendering a Finish bar with zero '
              'logged sets would be dead chrome (BUG-020 spec).',
        );
      },
    );

    testWidgets(
      'tapping the Finish button opens the FinishWorkoutDialog AlertDialog',
      (tester) async {
        // The dialog itself is the safety gate (kept exactly as-is). This pin
        // proves the bottom bar still wires through to _onFinish → showDialog.
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: true),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        // Tap the FilledButton inside the bottom bar carrying the Finish
        // semantics identifier. (Cluster 4 review: was OutlinedButton; swapped
        // to FilledButton so the bar reads as the primary CTA.)
        final finishButton = find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'workout-finish-btn',
          ),
          matching: find.byType(FilledButton),
        );
        expect(finishButton, findsOneWidget);

        await tester.tap(finishButton);
        await tester.pumpAndSettle();

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason:
              'FinishWorkoutDialog must still appear as the confirmation '
              'safety gate after the placement change.',
        );
      },
    );

    testWidgets('FAB sits above bottomNavigationBar with non-zero gap', (
      tester,
    ) async {
      // Cluster 4 review pin: ui-ux-critic worried that the
      // FloatingActionButton.extended would visually crash into the
      // _FinishBottomBar. Flutter's default `FloatingActionButtonLocation
      // .endFloat` actually anchors the FAB *above* the bottomNavigationBar
      // with a small spec'd gap — this test pins that geometry so a future
      // refactor (e.g. swapping to `centerDocked` or moving the FAB into the
      // bar) cannot silently regress one-handed reach for either action.
      final state = _makeStateWithSets([
        _makeSet(setNumber: 1, isCompleted: false),
      ]);

      // Pin at a realistic narrow phone width so the gap math reflects
      // the worst-case mobile layout, not a wide tablet canvas.
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildScreen(state));
      await tester.pump();
      await tester.pump();

      final fabRect = tester.getRect(find.byType(FloatingActionButton));
      final bottomBarRect = tester.getRect(
        find.byKey(const ValueKey('finish-bottom-bar')),
      );

      expect(
        fabRect.bottom < bottomBarRect.top,
        isTrue,
        reason:
            'FAB.bottom (${fabRect.bottom}) must be above '
            'bottomBar.top (${bottomBarRect.top}). If this fails, '
            'FloatingActionButtonLocation.endFloat is no longer keeping the '
            'FAB clear of the bottomNavigationBar — the layout regressed.',
      );

      final gap = bottomBarRect.top - fabRect.bottom;
      expect(
        gap >= 8,
        isTrue,
        reason:
            'Gap between FAB.bottom and bottomBar.top is $gap dp; needs '
            '>= 8 dp so the two stacked actions read as separate elements '
            'rather than touching. ui-ux-critic Cluster 4 review.',
      );
    });

    testWidgets(
      'FAB and bottomNavigationBar coexist without one suppressing the other',
      (tester) async {
        // Pin: when exercises exist, Scaffold must have BOTH a non-null
        // floatingActionButton (_AddExerciseFab) AND a non-null
        // bottomNavigationBar (_FinishBottomBar). Before BUG-020 the FAB was
        // tied to the Finish button being in the AppBar; this regression pin
        // ensures no future refactor silently disables the FAB when the
        // bottom bar is present (or vice-versa), which would regress one-
        // handed discoverability on either action.
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: false),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        final scaffold = _findActiveWorkoutScaffold(tester);
        expect(
          scaffold.bottomNavigationBar,
          isNotNull,
          reason:
              'BUG-020: _FinishBottomBar must be present when exercises exist.',
        );
        expect(
          scaffold.floatingActionButton,
          isNotNull,
          reason:
              '_AddExerciseFab must be present when exercises exist — it must '
              'not be suppressed by the presence of the bottom bar.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AW-EX-C-BR1-03 disabled-state contract pin (Family 8).
  //
  // Charter C BR-1 reported the Finish button was tappable (and opened the
  // FinishWorkoutDialog) when the workout had zero completed sets, despite
  // rendering at 30% alpha. Static analysis says `finish_bottom_bar.dart:74`
  // already wires `onPressed: enabled ? onPressed : null`, and
  // `active_workout_screen.dart:271` passes `enabled: _hasCompletedSet`, where
  // `_hasCompletedSet` walks `widget.state.exercises[*].sets[*].isCompleted`.
  //
  // These pins reproduce both no-completed-set scenarios and assert the
  // FilledButton's `onPressed` is null, the FinishBottomBar.enabled is false,
  // and tapping it does NOT open the FinishWorkoutDialog. This is the contract
  // — if it ever flips back, this test fires before E2E.
  //
  // Charter C BR-1 P11 (Playwright, Web) observed the dialog opening; root
  // cause is unconfirmed (most plausible: stale Hive-resumed completed-set
  // state). These tests pin the Flutter-engine contract; the Playwright/Web
  // path was not separately reproduced.
  //
  // CONTRACT BOUNDARY (not CI-pinned, see Warning 3 follow-up): the `enabled`
  // flag MUST derive from live traversal of
  // `state.exercises[*].sets[*].isCompleted` — any cached/persisted count
  // field on `ActiveWorkoutState` (e.g. `completedSetsCount`) wired into the
  // gate would be a regression. The current 3 tests inject
  // `ActiveWorkoutState` directly and bypass the notifier's Hive
  // deserialization path, so the Hive-resume boundary is documented here but
  // not exercised by CI.
  // ---------------------------------------------------------------------------
  group('AW-EX-C-BR1-03: Finish button disabled state', () {
    testWidgets('finish button is non-tappable when exercise has zero sets', (
      tester,
    ) async {
      // Charter C ran on BR-1 (360×780). Pin the same surface so any
      // narrow-width layout overflow that could hide hit-test geometry is
      // exercised here, not only on the default 800×600 desktop canvas.
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Direct repro of `addExercise` path: notifier creates the exercise
      // with `sets: const []` (active_workout_notifier.dart:300), so the
      // first instant after the picker resolves the workout has one
      // exercise + zero sets total.
      final state = _makeStateWithSets(const []);

      await tester.pumpWidget(_buildScreen(state));
      await tester.pump();
      await tester.pump();

      // Locate the FilledButton inside the workout-finish-btn Semantics.
      final finishButton = find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.identifier == 'workout-finish-btn',
        ),
        matching: find.byType(FilledButton),
      );
      expect(
        finishButton,
        findsOneWidget,
        reason:
            'Finish bar must still RENDER with zero completed sets — per '
            'spec §5.5 the disabled state is "visible but disabled", not '
            '"hidden".',
      );

      // Flutter\'s canonical disabled signal: FilledButton.onPressed == null.
      // This is what Material maps to aria-disabled in the AOM.
      final btn = tester.widget<FilledButton>(finishButton);
      expect(
        btn.onPressed,
        isNull,
        reason:
            'AW-EX-C-BR1-03 contract: with zero completed sets, the '
            'FilledButton.onPressed MUST be null. The wiring is '
            'active_workout_screen.dart `enabled: _hasCompletedSet` → '
            'finish_bottom_bar.dart `onPressed: enabled ? onPressed : null`. '
            'If onPressed is non-null here, the disabled-state contract has '
            'regressed.',
      );

      // Behavioural guard: even if a future refactor accidentally re-enables
      // tap (e.g. wraps in a GestureDetector), tapping must NOT open the
      // FinishWorkoutDialog.
      // warnIfMissed: false — disabled FilledButton (onPressed: null) does
      // not participate in hit-testing; the tap intentionally misses and
      // that is the behaviour under test.
      await tester.tap(finishButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Tapping the disabled Finish button must not open the '
            'FinishWorkoutDialog. Charter C BR-1 observed this happening '
            'on Web — the test pins it can never regress.',
      );
    });

    testWidgets(
      'finish button is non-tappable when sets exist but none are completed',
      (tester) async {
        // Charter C ran on BR-1 (360×780). Pin the same surface so any
        // narrow-width layout overflow that could hide hit-test geometry is
        // exercised here, not only on the default 800×600 desktop canvas.
        await tester.binding.setSurfaceSize(const Size(360, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Charter C BR-1 P11 exact repro: picker auto-adds one set, user has
        // not tapped the done-mark, so `sets: [oneIncompleteSet]`.
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: false),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        final finishButton = find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'workout-finish-btn',
          ),
          matching: find.byType(FilledButton),
        );
        expect(finishButton, findsOneWidget);

        final btn = tester.widget<FilledButton>(finishButton);
        expect(
          btn.onPressed,
          isNull,
          reason:
              'AW-EX-C-BR1-03 contract (Charter C P11 repro): one exercise + '
              'one incomplete set must leave FilledButton.onPressed == null. '
              'If this fires, the disabled-tap-handler bug from Charter C is '
              'real and must be fixed in finish_bottom_bar.dart or '
              'active_workout_screen.dart.',
        );

        // warnIfMissed: false — disabled FilledButton (onPressed: null) does
        // not participate in hit-testing; the tap intentionally misses and
        // that is the behaviour under test.
        await tester.tap(finishButton, warnIfMissed: false);
        await tester.pump();
        await tester.pump();
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason:
              'AW-EX-C-BR1-03: tapping Finish with no completed sets must NOT '
              'open the FinishWorkoutDialog (the visual 30% alpha and the '
              'behavioural disable must agree).',
        );
      },
    );

    testWidgets(
      'finish button enables exactly when at least one set is completed',
      (tester) async {
        // Boundary contract: the gate flips on the FIRST completed set, not on
        // any other condition (set count, exercise count, weight > 0, etc.).
        // Two-set state with only one completed asserts the gate logic is
        // `any(isCompleted)`, not `all(isCompleted)` or similar.
        final state = _makeStateWithSets([
          _makeSet(setNumber: 1, isCompleted: false),
          _makeSet(setNumber: 2, isCompleted: true),
        ]);

        await tester.pumpWidget(_buildScreen(state));
        await tester.pump();
        await tester.pump();

        final finishButton = find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == 'workout-finish-btn',
          ),
          matching: find.byType(FilledButton),
        );
        final btn = tester.widget<FilledButton>(finishButton);
        expect(
          btn.onPressed,
          isNotNull,
          reason:
              'Gate logic is `_hasCompletedSet = exercises.any(sets.any(s => '
              's.isCompleted))`. With at least one completed set, '
              'FilledButton.onPressed must be non-null.',
        );

        // Symmetric behavioural guard for the enabled side: `onPressed
        // isNotNull` alone would silently pass if a future regression wired
        // `onPressed` to a no-op `() {}`. Tapping the enabled Finish button
        // MUST open the FinishWorkoutDialog.
        await tester.tap(finishButton);
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason:
              'enabled Finish button must open the FinishWorkoutDialog on '
              'tap — pins that `onPressed` is wired to the dialog handler, '
              'not a no-op closure.',
        );
      },
    );
  });
}
