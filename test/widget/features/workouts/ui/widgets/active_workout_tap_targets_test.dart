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
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
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
        'pending-non-PR done-mark hit area is at least 40 wide AND 48 tall',
        (tester) async {
          await _pumpSetRowAt360(tester, set: _set(isCompleted: false));

          // The `_DoneCell` is structurally the only 52-wide Container in
          // the row that holds a Checkbox as a descendant. Anchor on it,
          // then take the OUTERMOST SizedBox descendant — `find.descendant`
          // walks the tree depth-first parent-before-child, so `.first`
          // is the topmost hit-test SizedBox (post-fix: 40×48; pre-fix:
          // the only one, 32×32).
          final cellFinder = find.byWidgetPredicate(
            (w) => w is Container && _containerWidth(w) == 52,
            description: 'done-cell Container(width: 52)',
          );
          expect(cellFinder, findsOneWidget);

          final outerHitBox = find
              .descendant(of: cellFinder, matching: find.byType(SizedBox))
              .first;
          final size = _sizeOf(tester, outerHitBox);

          expect(
            size.width,
            greaterThanOrEqualTo(40),
            reason:
                'Done-mark hit area must be >=40dp wide on a 360dp viewport. '
                'Material 2.5.5 AAA target size + Charter A finding '
                'AW-EX-A-BR1-01.',
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

      testWidgets(
        'completed done-mark hit area is at least 40 wide AND 48 tall',
        (tester) async {
          await _pumpSetRowAt360(tester, set: _set(isCompleted: true));

          final cellFinder = find.byWidgetPredicate(
            (w) => w is Container && _containerWidth(w) == 52,
            description: 'done-cell Container(width: 52)',
          );
          expect(cellFinder, findsOneWidget);

          final outerHitBox = find
              .descendant(of: cellFinder, matching: find.byType(SizedBox))
              .first;
          final size = _sizeOf(tester, outerHitBox);

          expect(size.width, greaterThanOrEqualTo(40));
          expect(size.height, greaterThanOrEqualTo(48));
        },
      );
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
    });
  });
}
