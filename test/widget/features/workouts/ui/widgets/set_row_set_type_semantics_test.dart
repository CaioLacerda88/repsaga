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
import 'package:repsaga/features/workouts/ui/widgets/set_row.dart';

import '../../../../../fixtures/test_factories.dart';
import '../../../../../helpers/test_material_app.dart';

/// Family 6 (i18n leak): the set-type micro-label rendered inside
/// `_SetNumberCell` (the persistent abbreviation below the digit) was
/// hard-coded to `set.setType.tinyAbbr` (English: WK / WU / DR / FL). This
/// test pins that the visible text is now resolved through the existing
/// localized `setTypeAbbr*` ARB keys — matching `workout_detail_screen.dart`
/// so both screens display the same per-locale convention (Path A in the
/// design split).
///
/// **Note on the parent Semantics label:** `setNumberSemantics(number, type)`
/// already takes the type name via `set.setType.localizedName(l10n)` and
/// produces e.g. "Set 1. Long press to change type: Working" (en) /
/// "Série 1. Toque e segure para mudar o tipo: De aquecimento" (pt). That
/// contract pre-dates this PR and is unchanged — Stage 2 only swaps the
/// VISIBLE micro-label.

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

ExerciseSet makeSet({
  String id = 'set-001',
  String workoutExerciseId = 'we-001',
  int setNumber = 1,
  double weight = 60.0,
  int reps = 10,
  SetType setType = SetType.working,
  bool isCompleted = false,
}) {
  return ExerciseSet.fromJson(
    TestSetFactory.create(
      id: id,
      workoutExerciseId: workoutExerciseId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      setType: setType.name,
      isCompleted: isCompleted,
    ),
  );
}

ProviderContainer makeContainer() {
  final mockStorage = MockWorkoutLocalStorage();
  when(() => mockStorage.loadActiveWorkout()).thenReturn(null);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
    ],
  );
}

Widget buildTestWidget(Widget child, {Locale? locale}) {
  return UncontrolledProviderScope(
    container: makeContainer(),
    child: TestMaterialApp(
      theme: AppTheme.dark,
      locale: locale,
      home: Scaffold(body: SizedBox(width: 800, child: child)),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeActiveWorkoutState());
  });

  group('SetRow set-type micro-label localization (Family 6)', () {
    group('en locale — uses ARB setTypeAbbr* values', () {
      testWidgets('working set renders "W" (l10n.setTypeAbbrWorking)', (
        tester,
      ) async {
        final set = makeSet(setType: SetType.working);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        expect(find.text('W'), findsOneWidget);
        // The hard-coded English `tinyAbbr` value MUST NOT be visible — that
        // would mean the localization swap regressed.
        expect(find.text('WK'), findsNothing);
      });

      testWidgets('warmup set renders "WU" (l10n.setTypeAbbrWarmup)', (
        tester,
      ) async {
        final set = makeSet(setType: SetType.warmup);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        // Both the hard-coded `tinyAbbr` and the ARB value happen to be "WU"
        // for en — this test still pins that the value flows from the ARB
        // (verified by the pt counterpart below where the values diverge).
        expect(find.text('WU'), findsOneWidget);
      });

      testWidgets('dropset renders "D" (l10n.setTypeAbbrDropset)', (
        tester,
      ) async {
        final set = makeSet(setType: SetType.dropset);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        expect(find.text('D'), findsOneWidget);
        expect(find.text('DR'), findsNothing);
      });

      testWidgets('failure renders "F" (l10n.setTypeAbbrFailure)', (
        tester,
      ) async {
        final set = makeSet(setType: SetType.failure);
        await tester.pumpWidget(
          buildTestWidget(SetRow(set: set, workoutExerciseId: 'we-001')),
        );
        expect(find.text('F'), findsOneWidget);
        expect(find.text('FL'), findsNothing);
      });
    });

    group(
      'pt locale — values diverge from the hard-coded English tinyAbbr',
      () {
        testWidgets('working set renders "N" (pt: setTypeAbbrWorking = N)', (
          tester,
        ) async {
          final set = makeSet(setType: SetType.working);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001'),
              locale: const Locale('pt'),
            ),
          );
          expect(find.text('N'), findsOneWidget);
          expect(find.text('WK'), findsNothing);
          expect(find.text('W'), findsNothing);
        });

        testWidgets('warmup set renders "AQ" (pt: setTypeAbbrWarmup = AQ)', (
          tester,
        ) async {
          final set = makeSet(setType: SetType.warmup);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001'),
              locale: const Locale('pt'),
            ),
          );
          expect(find.text('AQ'), findsOneWidget);
          expect(find.text('WU'), findsNothing);
        });

        testWidgets('dropset renders "D" (pt: setTypeAbbrDropset = D)', (
          tester,
        ) async {
          final set = makeSet(setType: SetType.dropset);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001'),
              locale: const Locale('pt'),
            ),
          );
          expect(find.text('D'), findsOneWidget);
          expect(find.text('DR'), findsNothing);
        });

        testWidgets('failure renders "F" (pt: setTypeAbbrFailure = F)', (
          tester,
        ) async {
          final set = makeSet(setType: SetType.failure);
          await tester.pumpWidget(
            buildTestWidget(
              SetRow(set: set, workoutExerciseId: 'we-001'),
              locale: const Locale('pt'),
            ),
          );
          expect(find.text('F'), findsOneWidget);
          expect(find.text('FL'), findsNothing);
        });
      },
    );
  });
}
