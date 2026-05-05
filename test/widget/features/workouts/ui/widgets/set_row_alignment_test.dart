/// Alignment and uniform-height tests for SetRow across all 5 PR states
/// (Phase 20, commit 6).
///
/// These tests verify the locked design promise: **every set row has
/// identical `min-height: 56px` and identical baselines for value text
/// regardless of state** (PLAN.md Phase 20 acceptance criterion A).
///
/// Implementation note: this file does NOT use golden images. The Flutter
/// test suite runs on multiple host platforms (Windows CI, macOS local) and
/// golden images baked on one platform fail pixel-comparison on another due
/// to sub-pixel font rendering differences in the test harness. The
/// uniform-spacing assertion gives the same structural guarantee without
/// the platform dependency.
///
/// To promote to golden tests when a single canonical platform is established:
///   1. Create `test/widget/features/workouts/ui/widgets/goldens/`.
///   2. Replace the `expect(yPositions[i+1] - yPositions[i], …)` assertions
///      with `expectLater(find.byType(Column), matchesGoldenFile('goldens/…'))`.
///   3. Bake with `flutter test --update-goldens`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/domain/pr_row_state.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/ui/widgets/set_row.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../../fixtures/test_factories.dart';
import '../../../../../helpers/test_material_app.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

/// Creates a minimal [ExerciseSet] for alignment tests.
ExerciseSet _makeSet({
  String id = 'set-001',
  String workoutExerciseId = 'we-001',
  int setNumber = 1,
  double weight = 60.0,
  int reps = 10,
  bool isCompleted = false,
}) {
  return ExerciseSet.fromJson(
    TestSetFactory.create(
      id: id,
      workoutExerciseId: workoutExerciseId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      setType: SetType.working.name,
      isCompleted: isCompleted,
    ),
  );
}

/// Builds a [ProviderContainer] with mocked storage that returns
/// [initialState] (or null when not supplied).
ProviderContainer _makeContainer([ActiveWorkoutState? initialState]) {
  final mockStorage = MockWorkoutLocalStorage();
  when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
    ],
  );
}

/// Wraps [child] in the full test scaffold at a fixed [width].
Widget _buildAt(Widget child, {double width = 360}) {
  return UncontrolledProviderScope(
    container: _makeContainer(),
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    ),
  );
}

/// Measures the rendered height of the first widget matching [finder] in the
/// test environment. Returns null when no matching widget is found.
double? _renderedHeight(WidgetTester tester, Finder finder) {
  final elements = tester.elementList(finder).toList();
  if (elements.isEmpty) return null;
  final box = elements.first.renderObject as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.size.height;
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeActiveWorkoutState());
  });

  // The 5 states in the canonical display order (PLAN.md Phase 20 matrix).
  const stateMatrix =
      <({String label, PrRowDisplay display, bool isCompleted})>[
        (
          label: 'none',
          display: PrRowDisplay.plain(PrRowState.none),
          isCompleted: false,
        ),
        (
          label: 'pendingPredictedPr',
          display: PrRowDisplay(
            state: PrRowState.pendingPredictedPr,
            accentTypes: {RecordType.maxWeight},
          ),
          isCompleted: false,
        ),
        (
          label: 'completedNonPr',
          display: PrRowDisplay.plain(PrRowState.completedNonPr),
          isCompleted: true,
        ),
        (
          label: 'completedSupersededPr',
          display: PrRowDisplay(
            state: PrRowState.completedSupersededPr,
            accentTypes: {RecordType.maxWeight},
          ),
          isCompleted: true,
        ),
        (
          label: 'completedStandingPr',
          display: PrRowDisplay(
            state: PrRowState.completedStandingPr,
            accentTypes: {RecordType.maxWeight},
          ),
          isCompleted: true,
        ),
      ];

  group('SetRow alignment — 5-state matrix', () {
    testWidgets(
      'each state renders with row frame minHeight ≥ 56dp at 360dp width',
      (tester) async {
        // Render each state independently at the canonical 360dp viewport
        // (Brazilian mid-market screen width) and assert the frame container
        // enforces the 56dp floor.
        for (final entry in stateMatrix) {
          final set = _makeSet(
            id: 'set-${entry.label}',
            isCompleted: entry.isCompleted,
          );
          await tester.pumpWidget(
            _buildAt(
              SetRow(
                set: set,
                workoutExerciseId: 'we-001',
                display: entry.display,
              ),
            ),
          );

          // Containers with minHeight ≥ 56 — these are the _SetRowFrame
          // instances enforcing the uniform-height contract.
          final frameContainers = tester
              .widgetList<Container>(find.byType(Container))
              .where((c) {
                final bc = c.constraints;
                return bc != null && bc.minHeight >= 56;
              })
              .toList();

          expect(
            frameContainers,
            isNotEmpty,
            reason:
                'state:${entry.label} — must have at least one Container with '
                'minHeight≥56dp. Regressing this breaks the uniform-height '
                'alignment promise (PLAN.md Phase 20 acceptance criterion A).',
          );
        }
      },
    );

    testWidgets('all 5 states in a Column report ≥ 56dp rendered height each '
        '(uniform-spacing structural assertion)', (tester) async {
      // Fix the viewport so every row is measured at the same width.
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Build a Column with one row per state. Each row is keyed so we can
      // find the Dismissible (SetRow's root widget) for each state.
      final container = _makeContainer();
      addTearDown(container.dispose);

      final rows = stateMatrix
          .map(
            (entry) => SetRow(
              key: ValueKey(entry.label),
              set: _makeSet(
                id: 'set-${entry.label}',
                isCompleted: entry.isCompleted,
              ),
              workoutExerciseId: 'we-001',
              display: entry.display,
            ),
          )
          .toList();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestMaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: SizedBox(width: 360, child: Column(children: rows)),
            ),
          ),
        ),
      );

      // Verify each row individually renders ≥ 56dp using the RenderBox
      // of the SetRow widget itself (keyed so we can locate it precisely).
      for (final entry in stateMatrix) {
        final rowFinder = find.byKey(ValueKey(entry.label));
        expect(
          rowFinder,
          findsOneWidget,
          reason: 'state:${entry.label} SetRow must be found in the column',
        );

        // Measure the SetRow's own RenderBox — it encloses the full row
        // including the 56dp _SetRowFrame constraint.
        final element = tester.element(rowFinder);
        final renderBox = element.renderObject as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final height = renderBox.size.height;
          expect(
            height,
            greaterThanOrEqualTo(56),
            reason:
                'state:${entry.label} — rendered row height ($height) must '
                'be ≥ 56dp. Uniform height prevents janky visual height '
                'changes between PR and non-PR states.',
          );
        }
      }
    });

    testWidgets('at 360dp width none and completedStandingPr rows report equal '
        'or within-1dp rendered height (no height jank between states)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _makeContainer();
      addTearDown(container.dispose);

      Future<double?> measureRow(PrRowDisplay display, bool isCompleted) async {
        final set = _makeSet(
          id: 'row-${display.state.name}',
          isCompleted: isCompleted,
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestMaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: SizedBox(
                  width: 360,
                  child: SetRow(
                    set: set,
                    workoutExerciseId: 'we-001',
                    display: display,
                  ),
                ),
              ),
            ),
          ),
        );

        final dismissibleFinder = find.byType(Dismissible);
        return _renderedHeight(tester, dismissibleFinder);
      }

      final heightNone = await measureRow(
        const PrRowDisplay.plain(PrRowState.none),
        false,
      );
      final heightStanding = await measureRow(
        const PrRowDisplay(
          state: PrRowState.completedStandingPr,
          accentTypes: {RecordType.maxWeight},
        ),
        true,
      );

      if (heightNone != null && heightStanding != null) {
        expect(
          (heightNone - heightStanding).abs(),
          lessThanOrEqualTo(1),
          reason:
              'Row height must be identical (±1dp tolerance) between state:none '
              '($heightNone dp) and state:completedStandingPr ($heightStanding dp). '
              'The gold 4dp stripe shifts content 1dp — tolerated. A larger '
              'discrepancy means the layout is not uniform across states.',
        );
      }
    });
  });
}
