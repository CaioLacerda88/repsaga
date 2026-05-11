/// Widget tests pinning Material-compliant tap targets across the active-workout
/// flow on the smallest priority viewport (360×780).
///
/// Family 4 from the active-workout exploratory pass closes:
///   * AW-EX-A-BR1-01 (MAJOR) — done-mark cell was 32×32 px, below the 40×48
///     Material minimum. The visual ◆/✓ stays its current size; only the
///     hit-test box grows to ≥40×48.
///   * AW-EX-A-BR1-02 (minor) — Charter A measured the Add Set button at
///     40-tall on BR-1. Impact analysis flagged this as POSSIBLY stale —
///     `_AddSetButton` already declares `minimumSize: Size(double.infinity, 48)`.
///     This test PROVES the rendered size on a 360-wide viewport. It serves
///     as a regression guard regardless of the Charter verdict.
///   * AW-EX-F-BR1-09 (minor) — dialog `TextButton` actions render at Flutter's
///     default 36dp across Finish / Discard / Weight stepper input / Reps
///     stepper input / Remove exercise dialogs. A shared
///     `dialogTextButtonStyle` lifts them to ≥48dp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/core/theme/dialog_button_style.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/domain/pr_row_state.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/ui/widgets/discard_workout_dialog.dart';
import 'package:repsaga/features/workouts/ui/widgets/exercise_card.dart';
import 'package:repsaga/features/workouts/ui/widgets/finish_workout_dialog.dart';
import 'package:repsaga/features/workouts/ui/widgets/set_row.dart';
import 'package:repsaga/shared/widgets/reps_stepper.dart';
import 'package:repsaga/shared/widgets/weight_stepper.dart';

import '../../../../../fixtures/test_factories.dart';
import '../../../../../helpers/test_material_app.dart';

class _MockRepo extends Mock implements WorkoutRepository {}

class _MockStorage extends Mock implements WorkoutLocalStorage {}

class _FakeState extends Fake implements ActiveWorkoutState {}

// Mirror the provider stubs from `exercise_card_test.dart` so the Add Set
// measurement test can render the full ExerciseCard without hitting Supabase.
class _FixedActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _FixedActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Notifier that counts `completeSet` invocations without mutating state.
///
/// Exists ONLY to pin the gesture-arena single-fire contract on `_DoneCell`:
/// a single tap landing inside the inner 32×32 visual must invoke
/// `completeSet` exactly once. Mutating state would cause the row to repaint
/// and toggle visuals, masking the underlying bug (a double-fire produces
/// toggle-on → toggle-off → no visible change — the very symptom we're
/// guarding against).
///
/// `completeSet` is a no-op so the counter is the sole observable. The
/// notifier returns a fixed state from `build()` so the parent ExerciseCard
/// / SetRow can render normally.
class _CountingActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  _CountingActiveWorkoutNotifier(this.state_);
  final ActiveWorkoutState state_;
  int completeSetCallCount = 0;

  @override
  Future<ActiveWorkoutState?> build() async => state_;

  @override
  Future<void> completeSet(String workoutExerciseId, String setId) async {
    completeSetCallCount++;
    // Intentionally NO state mutation — see class doc.
  }

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

ExerciseSet _set({
  String id = 'set-001',
  int setNumber = 1,
  bool isCompleted = false,
}) {
  return ExerciseSet.fromJson(
    TestSetFactory.create(
      id: id,
      workoutExerciseId: 'we-001',
      setNumber: setNumber,
      weight: 60.0,
      reps: 10,
      setType: SetType.working.name,
      isCompleted: isCompleted,
    ),
  );
}

ProviderContainer _container() {
  final storage = _MockStorage();
  when(() => storage.loadActiveWorkout()).thenReturn(null);
  when(() => storage.saveActiveWorkout(any())).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(_MockRepo()),
      workoutLocalStorageProvider.overrideWithValue(storage),
    ],
  );
}

/// Pumps a SetRow on a strict 360-wide test viewport so tap-target measurements
/// reflect the smallest priority device (Galaxy A14, 360×780).
Future<void> _pumpSetRowAt360(WidgetTester tester, {required ExerciseSet set}) {
  // Forcing the rendered Flutter view to 360 dp wide pins all hit-test
  // measurements to the bug-repro envelope. Without this, the harness uses
  // an 800-wide test surface that masks the regression.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(),
      child: TestMaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          // Wrap in a 360dp-wide column so the SetRow lays out exactly as on
          // the BR-1 viewport. The frame's outer constraints come from the
          // view, but pinning the parent width here makes the test's intent
          // explicit and stable across MediaQuery shifts.
          body: SizedBox(
            width: 360,
            child: SetRow(set: set, workoutExerciseId: 'we-001'),
          ),
        ),
      ),
    ),
  );
}

/// Returns the bounding-box `Size` of the *first* widget matched by [finder].
/// `tester.getSize` resolves to the rendered RenderBox size at layout time —
/// matches what a Playwright `boundingBox()` call sees in the browser.
Size _sizeOf(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  return tester.getSize(finder);
}

/// Best-effort `Container.width` extraction. The widget exposes `width` only
/// indirectly through `constraints` — but `_DoneCell` declares
/// `Container(width: 52, ...)` which Flutter forwards into a wrapped
/// `ConstrainedBox(BoxConstraints.tightFor(width: 52))`. We read the tight
/// width to identify the cell unambiguously.
double? _containerWidth(Container c) {
  final cons = c.constraints;
  if (cons == null) return null;
  if (cons.hasTightWidth) return cons.maxWidth;
  return null;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeState());
  });

  group('Active workout — Family 4 tap targets (360dp viewport)', () {
    // -------------------------------------------------------------------
    // Bug AW-EX-A-BR1-01 — done-mark tap target is below 40×48dp on BR-1.
    // -------------------------------------------------------------------
    group('done-mark cell (AW-EX-A-BR1-01)', () {
      testWidgets(
        'pending-non-PR done-mark hit area is at least 48 wide AND 48 tall '
        '(PR-2 H1 — was 40 wide, below Material floor)',
        (tester) async {
          await _pumpSetRowAt360(tester, set: _set(isCompleted: false));

          // The `_DoneCell` is structurally the only 52-wide Container in
          // the row that holds a Checkbox as a descendant. Anchor on it,
          // then anchor the outer hit-box on its EXACT (40, 48) constraint
          // pair — using `.first` over a generic SizedBox finder would
          // silently measure the wrong widget if a refactor inserted any
          // other SizedBox above it (e.g. a padding wrapper).
          final cellFinder = find.byWidgetPredicate(
            (w) => w is Container && _containerWidth(w) == 52,
            description: 'done-cell Container(width: 52)',
          );
          expect(cellFinder, findsOneWidget);

          final outerHitBox = find.descendant(
            of: cellFinder,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width == 52 && w.height == 48,
              description:
                  'outer 52×48 hit-test SizedBox (PR-2 H1 widened '
                  'from 40 to full 52dp Container width to clear Material '
                  '2.5.5 / WCAG floor)',
            ),
          );
          final size = _sizeOf(tester, outerHitBox);

          expect(
            size.width,
            greaterThanOrEqualTo(48),
            reason:
                'Done-mark hit area must be >=48dp wide on a 360dp viewport. '
                'Material 2.5.5 / WCAG floor. PR-2 H1 widened from 40 → 52dp '
                '(full Container width). Pre-fix: 40dp horizontal '
                'failed the floor for the most time-critical tap.',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason:
                'Done-mark hit area must be >=48dp tall on a 360dp viewport. '
                'Material 2.5.5 AAA target size + Charter A finding '
                'AW-EX-A-BR1-01.',
          );
        },
      );

      // PR-2 H1 — the predicted-PR variant swaps Checkbox →
      // `_PredictedPrUncheckedMark` (the gold ◆ rune), but the OUTER
      // 52×48 hit-test box wraps both variants. Pin the parent tap area
      // for the predicted-PR path explicitly so a future refactor that
      // moves the outer SizedBox INSIDE the Checkbox-only branch (and
      // skips it for the predicted-PR branch) flips this assertion.
      testWidgets(
        'predicted-PR pending done-mark parent tap area is at least 48×48dp '
        '(PR-2 H1)',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: _container(),
              child: TestMaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: SizedBox(
                    width: 360,
                    child: SetRow(
                      set: _set(isCompleted: false),
                      workoutExerciseId: 'we-001',
                      display: const PrRowDisplay.plain(
                        PrRowState.pendingPredictedPr,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          final cellFinder = find.byWidgetPredicate(
            (w) => w is Container && _containerWidth(w) == 52,
            description: 'done-cell Container(width: 52)',
          );
          expect(cellFinder, findsOneWidget);

          final outerHitBox = find.descendant(
            of: cellFinder,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width == 52 && w.height == 48,
              description:
                  'outer 52×48 hit-test SizedBox '
                  '(predicted-PR variant)',
            ),
          );
          final size = _sizeOf(tester, outerHitBox);
          expect(
            size.width,
            greaterThanOrEqualTo(48),
            reason:
                '_PredictedPrUncheckedMark parent tap area must be >=48dp '
                'wide. PR-2 H1 mandates Material 2.5.5 across BOTH the '
                'Checkbox and predicted-PR done-mark variants.',
          );
          expect(size.height, greaterThanOrEqualTo(48));
        },
      );

      testWidgets(
        'completed done-mark hit area is at least 48 wide AND 48 tall '
        '(PR-2 H1)',
        (tester) async {
          await _pumpSetRowAt360(tester, set: _set(isCompleted: true));

          final cellFinder = find.byWidgetPredicate(
            (w) => w is Container && _containerWidth(w) == 52,
            description: 'done-cell Container(width: 52)',
          );
          expect(cellFinder, findsOneWidget);

          final outerHitBox = find.descendant(
            of: cellFinder,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width == 52 && w.height == 48,
              description:
                  'outer 52×48 hit-test SizedBox (PR-2 H1 widened '
                  'from 40 to full 52dp Container width to clear Material '
                  '2.5.5 / WCAG floor)',
            ),
          );
          final size = _sizeOf(tester, outerHitBox);

          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        },
      );

      // -----------------------------------------------------------------
      // Gesture-arena single-fire pin (PR #181 reviewer-round-2).
      //
      // The `_DoneCell` nests TWO discrete-tap GestureDetectors:
      //   * outer 40×48 widening (added for AW-EX-A-BR1-01)
      //   * inner Checkbox (or `_PredictedPrUncheckedMark` for the
      //     pending-predicted-PR variant)
      //
      // **Investigation finding (Phase 1 systematic debugging):** the
      // reviewer flagged a theoretical double-fire if the outer detector
      // uses `HitTestBehavior.translucent`. Empirically, that does NOT
      // happen today: Flutter's `GestureArena.sweep` resolves two
      // competing `onTap`-only recognizers by accepting the FIRST member
      // (innermost child) and rejecting all others (`arena.dart` lines
      // 170-178). So `completeSet` fires exactly once whether the outer
      // is `translucent` OR `deferToChild`.
      //
      // The fix is still `HitTestBehavior.deferToChild` — for STRUCTURAL
      // rather than runtime reasons. With `deferToChild` only the
      // recognizer whose visual region was hit is added to the arena
      // for that pointer; the contract no longer depends on
      // first-member-wins arena semantics. This is robust to future
      // refactors that introduce competing non-tap recognizers (e.g. a
      // long-press on the outer detector) — those paths could cause
      // both recognizers to resolve as accepted and double-fire
      // `_onComplete` (a TOGGLE of `isCompleted`, NOT idempotent → silent
      // no-op).
      //
      // These tests pin the single-fire CONTRACT by counting
      // `completeSet` invocations on a no-mutation fake notifier. They
      // pass under both `translucent` and `deferToChild` today; they
      // would FAIL if a future refactor breaks the contract by adding a
      // competing recognizer that the arena can't resolve to a single
      // winner.
      // -----------------------------------------------------------------
      group('gesture-arena single-fire pin', () {
        Future<int> tapCenterOfDoneCellAndCount(
          WidgetTester tester, {
          required bool isCompleted,
          PrRowDisplay display = const PrRowDisplay.plain(PrRowState.none),
        }) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final exercise = Exercise(
            id: 'exercise-001',
            name: 'Barbell Bench Press',
            muscleGroup: MuscleGroup.chest,
            equipmentType: EquipmentType.barbell,
            isDefault: true,
            createdAt: DateTime(2026),
          );
          final theSet = _set(isCompleted: isCompleted);
          final activeExercise = ActiveWorkoutExercise(
            workoutExercise: WorkoutExercise(
              id: 'we-001',
              workoutId: 'workout-001',
              exerciseId: 'exercise-001',
              order: 1,
              exercise: exercise,
            ),
            sets: [theSet],
          );
          final workout = Workout(
            id: 'workout-001',
            userId: 'user-001',
            name: 'Push Day',
            startedAt: DateTime.now().toUtc(),
            isActive: true,
            createdAt: DateTime.now().toUtc(),
          );
          final state = ActiveWorkoutState(
            workout: workout,
            exercises: [activeExercise],
          );

          final notifier = _CountingActiveWorkoutNotifier(state);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                activeWorkoutProvider.overrideWith(() => notifier),
                restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
                profileProvider.overrideWith(() => _KgProfileNotifier()),
              ],
              child: TestMaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: SizedBox(
                    width: 360,
                    child: SetRow(
                      set: theSet,
                      workoutExerciseId: 'we-001',
                      display: display,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // Anchor on the outer 52×48 hit-test box (PR-2 H1 widened from
          // 40 to 52dp), then tap its CENTER — that's the visual center
          // of the inner 32×32 box and the exact pixel where both
          // gesture detectors would fire if the arena ever resolved
          // both as winners.
          final outerHitBox = find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 52 && w.height == 48,
            description: 'outer 52×48 hit-test SizedBox',
          );
          expect(outerHitBox, findsOneWidget);
          await tester.tap(outerHitBox);
          await tester.pump();

          return notifier.completeSetCallCount;
        }

        testWidgets(
          'tap on inner Checkbox region invokes completeSet exactly once',
          (tester) async {
            final fireCount = await tapCenterOfDoneCellAndCount(
              tester,
              isCompleted: false,
            );
            expect(
              fireCount,
              1,
              reason:
                  'A single tap inside the inner 32×32 visual must invoke '
                  'completeSet exactly once. completeSet is a toggle '
                  '(`!isCompleted`), so a double-fire would silently net '
                  'to no change — the same symptom the wider tap target '
                  'was meant to fix. Pin guards against future refactors '
                  'that could break the gesture-arena single-winner '
                  'contract on this nested layout.',
            );
          },
        );

        testWidgets('tap on inner _PredictedPrUncheckedMark region invokes '
            'completeSet exactly once', (tester) async {
          // The pendingPredictedPr branch swaps Checkbox → an inner
          // GestureDetector(opaque) on `_PredictedPrUncheckedMark`.
          // Pin the same single-fire contract on this code path too.
          final fireCount = await tapCenterOfDoneCellAndCount(
            tester,
            isCompleted: false,
            display: const PrRowDisplay.plain(PrRowState.pendingPredictedPr),
          );
          expect(
            fireCount,
            1,
            reason:
                'A single tap inside the inner 32×32 visual on a '
                'predicted-PR row must invoke completeSet exactly once. '
                'See Checkbox-variant test for full reasoning.',
          );
        });

        // -----------------------------------------------------------------
        // PR-2 H1 — tap in the slack zone (outside the inner 32dp visual,
        // inside the new 52dp outer hit-test box) must reach the outer
        // GestureDetector and invoke completeSet exactly once.
        //
        // This is the regression that motivated widening the outer
        // SizedBox from 40 → 52dp: pre-fix, a tap at the cell's left or
        // right edge (within the 52dp Container but outside the 40dp
        // inner SizedBox) fell on the Container's empty padding area
        // and missed completion entirely. The pin uses the same
        // counting-notifier plumbing as the inner-region pin so any
        // future refactor that drops slack-region routing (e.g. by
        // narrowing the outer SizedBox or swapping `deferToChild` to
        // `opaque`) flips this assertion.
        // -----------------------------------------------------------------
        testWidgets('tap in slack zone (outer 52dp, outside inner 32dp visual) '
            'invokes completeSet exactly once (PR-2 H1)', (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final exercise = Exercise(
            id: 'exercise-001',
            name: 'Barbell Bench Press',
            muscleGroup: MuscleGroup.chest,
            equipmentType: EquipmentType.barbell,
            isDefault: true,
            createdAt: DateTime(2026),
          );
          final theSet = _set(isCompleted: false);
          final activeExercise = ActiveWorkoutExercise(
            workoutExercise: WorkoutExercise(
              id: 'we-001',
              workoutId: 'workout-001',
              exerciseId: 'exercise-001',
              order: 1,
              exercise: exercise,
            ),
            sets: [theSet],
          );
          final workout = Workout(
            id: 'workout-001',
            userId: 'user-001',
            name: 'Push Day',
            startedAt: DateTime.now().toUtc(),
            isActive: true,
            createdAt: DateTime.now().toUtc(),
          );
          final state = ActiveWorkoutState(
            workout: workout,
            exercises: [activeExercise],
          );

          final notifier = _CountingActiveWorkoutNotifier(state);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                activeWorkoutProvider.overrideWith(() => notifier),
                restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
                profileProvider.overrideWith(() => _KgProfileNotifier()),
              ],
              child: TestMaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: SizedBox(
                    width: 360,
                    child: SetRow(set: theSet, workoutExerciseId: 'we-001'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // Anchor on the outer 52×48 hit-test box. The inner visual is
          // 32dp centered → leaves (52-32)/2 = 10dp of slack on each
          // side. A tap 4dp inside the right edge (offset +22 from
          // center horizontally) sits in the slack zone: outside the
          // inner 32dp Checkbox visual, inside the outer 52dp box.
          final outerHitBox = find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 52 && w.height == 48,
            description: 'outer 52×48 hit-test SizedBox',
          );
          expect(outerHitBox, findsOneWidget);
          final center = tester.getCenter(outerHitBox);
          // Slack zone tap: +22dp x-offset puts us 6dp inside the
          // right edge (52/2 - 22 = 4dp from edge, well inside the
          // slack ring outside the inner 32dp).
          await tester.tapAt(Offset(center.dx + 22, center.dy));
          await tester.pump();

          expect(
            notifier.completeSetCallCount,
            1,
            reason:
                'A tap in the slack zone (between the inner 32dp visual '
                'and the outer 52dp hit-test box) must reach the outer '
                'GestureDetector and toggle completion. Pre-PR-2 the '
                'outer was 40dp wide → slack-zone taps at the cell edges '
                'fell on the empty Container padding and missed entirely. '
                'Widening to 52dp closes the gap. If a future refactor '
                'narrows the outer SizedBox or breaks `deferToChild` '
                'routing, this pin fires.',
          );
        });
      });
    });

    // -------------------------------------------------------------------
    // Bug AW-EX-A-BR1-02 — Add Set button measured 40dp tall on BR-1.
    // Impact analysis flagged this as POSSIBLY stale because
    // `_AddSetButton` already declares `minimumSize: Size(double.infinity, 48)`.
    // This test PROVES the rendered size on a 360-wide viewport. Whether
    // the original Charter A finding was a measurement error or a real
    // regression, this test stays as a regression guard.
    // -------------------------------------------------------------------
    group('Add Set button (AW-EX-A-BR1-02)', () {
      testWidgets(
        'Add Set OutlinedButton is at least 48dp tall on a 360dp viewport',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          // Build an ExerciseCard with one set so the Add Set button
          // renders. The provider plumbing mirrors `exercise_card_test.dart`.
          final exercise = Exercise(
            id: 'exercise-001',
            name: 'Barbell Bench Press',
            muscleGroup: MuscleGroup.chest,
            equipmentType: EquipmentType.barbell,
            isDefault: true,
            createdAt: DateTime(2026),
          );
          final activeExercise = ActiveWorkoutExercise(
            workoutExercise: WorkoutExercise(
              id: 'we-001',
              workoutId: 'workout-001',
              exerciseId: 'exercise-001',
              order: 1,
              exercise: exercise,
            ),
            sets: [_set()],
          );
          final workout = Workout(
            id: 'workout-001',
            userId: 'user-001',
            name: 'Push Day',
            startedAt: DateTime.now().toUtc(),
            isActive: true,
            createdAt: DateTime.now().toUtc(),
          );
          final state = ActiveWorkoutState(
            workout: workout,
            exercises: [activeExercise],
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                activeWorkoutProvider.overrideWith(
                  () => _FixedActiveWorkoutNotifier(state),
                ),
                restTimerProvider.overrideWith(() => _NullRestTimerNotifier()),
                profileProvider.overrideWith(() => _KgProfileNotifier()),
                exercisePRsProvider.overrideWith((ref, _) => Future.value([])),
                lastWorkoutSetsProvider.overrideWith(
                  (ref, _) => Future.value({}),
                ),
              ],
              child: TestMaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  // Pin to 360dp so the rendered button mirrors BR-1.
                  body: SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: ExerciseCard(
                        activeExercise: activeExercise,
                        reorderMode: false,
                        isFirst: true,
                        isLast: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(); // drain async provider build

          final addSet = find.byType(OutlinedButton);
          expect(addSet, findsOneWidget);
          final size = tester.getSize(addSet);

          // Print measured size so the AW-EX-A-BR1-02 verdict is on the
          // record (stale vs real). The expectation enforces the floor;
          // the print body lets the orchestrator capture the actual.
          // ignore: avoid_print
          print(
            'AW-EX-A-BR1-02 measurement: Add Set OutlinedButton = '
            '${size.width.toStringAsFixed(1)}w × '
            '${size.height.toStringAsFixed(1)}h dp',
          );

          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason:
                'Add Set button must be >=48dp tall on a 360dp viewport. '
                'AW-EX-A-BR1-02 + Material 2.5.5.',
          );
        },
      );
    });

    // -------------------------------------------------------------------
    // Bug AW-EX-F-BR1-09 — dialog TextButton actions render at 36dp.
    // -------------------------------------------------------------------
    group('dialog action buttons (AW-EX-F-BR1-09)', () {
      Future<void> pumpDialogHost(
        WidgetTester tester,
        Future<void> Function(BuildContext) opener,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          TestMaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => opener(ctx),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      void expectActionsTallEnough(WidgetTester tester, List<String> labels) {
        for (final label in labels) {
          // Any TextButton or FilledButton whose label matches.
          final btnFinder = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) => w is TextButton || w is FilledButton,
            ),
          );
          expect(
            btnFinder,
            findsWidgets,
            reason: 'Expected to find a button with label "$label".',
          );
          final size = tester.getSize(btnFinder.first);
          // ignore: avoid_print
          print(
            'AW-EX-F-BR1-09 measurement: dialog action "$label" = '
            '${size.width.toStringAsFixed(1)}w × '
            '${size.height.toStringAsFixed(1)}h dp',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason:
                'Dialog action "$label" must be >=48dp tall on a 360dp '
                'viewport. AW-EX-F-BR1-09 + Material 2.5.5.',
          );
        }
      }

      testWidgets('FinishWorkoutDialog actions are >=48dp tall', (
        tester,
      ) async {
        await pumpDialogHost(tester, (ctx) async {
          await FinishWorkoutDialog.show(ctx, incompleteCount: 0);
        });

        expectActionsTallEnough(tester, const ['Keep Going', 'Save & Finish']);
      });

      testWidgets('DiscardWorkoutDialog actions are >=48dp tall', (
        tester,
      ) async {
        await pumpDialogHost(tester, (ctx) async {
          await DiscardWorkoutDialog.show(
            ctx,
            elapsedDuration: const Duration(minutes: 5),
          );
        });

        expectActionsTallEnough(tester, const ['Cancel', 'Discard']);
      });

      testWidgets('Weight stepper input dialog actions are >=48dp tall', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          TestMaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Center(child: WeightStepper(value: 60, onChanged: (_) {})),
            ),
          ),
        );

        await tester.tap(find.text('60'));
        await tester.pumpAndSettle();

        expectActionsTallEnough(tester, const ['Cancel', 'OK']);
      });

      testWidgets('Reps stepper input dialog actions are >=48dp tall', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          TestMaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Center(child: RepsStepper(value: 10, onChanged: (_) {})),
            ),
          ),
        );

        await tester.tap(find.text('10'));
        await tester.pumpAndSettle();

        expectActionsTallEnough(tester, const ['Cancel', 'OK']);
      });

      // -----------------------------------------------------------------
      // Defense-in-depth pin: `dialogTextButtonStyle` actively overrides
      // theme defaults (PR #181 reviewer-round-2 warning #2).
      //
      // The other dialog tests above pass even WITHOUT
      // `dialogTextButtonStyle` because Material 3's
      // `MaterialTapTargetSize.padded` default already inflates the
      // hit-test region to 48dp. So removing the style from a call site
      // would silently NOT cause those tests to fail — they only verify
      // the floor is met, not that the new style is doing the work.
      //
      // This test pumps a TextButton under a theme that aggressively
      // shrinks tap targets (`MaterialTapTargetSize.shrinkWrap`). Without
      // `dialogTextButtonStyle`, the button drops below 48dp. WITH the
      // style, the explicit `minimumSize: Size(64, 48)` floor wins. This
      // pins the structural defense-in-depth contract: the style isn't
      // theatrical — it actively guards against future theme regressions.
      // -----------------------------------------------------------------
      testWidgets(
        'dialogTextButtonStyle holds 48dp floor even under shrinkWrap theme '
        '(defense-in-depth, AW-EX-F-BR1-09)',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          // Theme that flips `materialTapTargetSize` to `shrinkWrap` —
          // this drops Material's default 48dp inflation. Without an
          // explicit `minimumSize`, a TextButton renders at ~36dp.
          final shrinkTheme = AppTheme.dark.copyWith(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );

          // Sanity baseline (locked into the test as a comparison anchor):
          // a bare TextButton under shrinkWrap is below 48dp. If a future
          // Flutter version changes that default and this anchor passes,
          // the defense-in-depth contract becomes vacuous and we'll know.
          await tester.pumpWidget(
            TestMaterialApp(
              theme: shrinkTheme,
              home: Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Bare'),
                  ),
                ),
              ),
            ),
          );
          final bareSize = tester.getSize(find.byType(TextButton));
          expect(
            bareSize.height,
            lessThan(48),
            reason:
                'Sanity anchor: under MaterialTapTargetSize.shrinkWrap a '
                'bare TextButton must render <48dp tall. If this passes, '
                'the defense-in-depth premise no longer holds and the '
                'real assertion below becomes vacuous.',
          );

          // Now the real pin: with `dialogTextButtonStyle` applied, the
          // TextButton MUST stay ≥48dp tall even under the shrinkWrap
          // theme. The explicit `minimumSize: Size(64, 48)` wins over the
          // theme's tap-target-size shrink.
          await tester.pumpWidget(
            TestMaterialApp(
              theme: shrinkTheme,
              home: Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {},
                    style: dialogTextButtonStyle,
                    child: const Text('Styled'),
                  ),
                ),
              ),
            ),
          );
          final styledSize = tester.getSize(find.byType(TextButton));
          expect(
            styledSize.height,
            greaterThanOrEqualTo(48),
            reason:
                'dialogTextButtonStyle must keep dialog actions >=48dp '
                'tall regardless of ancestor theme defaults. This is the '
                'structural reason the style exists — not because '
                'Material 3 defaults already do it, but because they '
                'might NOT in some future theme override.',
          );
        },
      );
    });
  });
}
