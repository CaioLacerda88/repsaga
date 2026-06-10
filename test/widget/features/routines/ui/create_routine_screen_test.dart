import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/routines/ui/create_routine_screen.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/test_material_app.dart';

Exercise _makeExercise({
  String id = 'exercise-001',
  String name = 'Bench Press',
  String muscleGroup = 'chest',
}) {
  return Exercise.fromJson(
    TestExerciseFactory.create(id: id, name: name, muscleGroup: muscleGroup),
  );
}

Widget _buildScreen({Routine? routine}) {
  return ProviderScope(
    child: TestMaterialApp(
      theme: AppTheme.dark,
      home: CreateRoutineScreen(routine: routine),
    ),
  );
}

void main() {
  group('CreateRoutineScreen', () {
    testWidgets('Save button disabled when name is empty and no exercises', (
      tester,
    ) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Find the Save TextButton
      final saveButton = find.widgetWithText(TextButton, 'Save');
      expect(saveButton, findsOneWidget);

      // It should be disabled (onPressed is null)
      final button = tester.widget<TextButton>(saveButton);
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'Save button still disabled when name entered but no exercises',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        // Enter a name (first TextField — the notes field is second)
        await tester.enterText(find.byType(TextField).first, 'My Routine');
        await tester.pump();

        final saveButton = find.widgetWithText(TextButton, 'Save');
        final button = tester.widget<TextButton>(saveButton);
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('shows Add Exercise button', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Add Exercise'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows Create Routine title for new routine', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Create Routine'), findsOneWidget);
    });

    testWidgets('shows Edit Routine title when editing existing routine', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      expect(find.text('Edit Routine'), findsOneWidget);
    });

    testWidgets('pre-fills name and exercises when editing', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Name should be pre-filled (first TextField — notes field is second)
      final textField = tester.widget<TextField>(find.byType(TextField).first);
      expect(textField.controller?.text, 'Push Day');

      // Exercise name should appear
      expect(find.text('Bench Press'), findsOneWidget);
    });

    testWidgets('set count stepper shows correct value for editing routine', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Set count should be 4 (number of setConfigs)
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Sets'), findsOneWidget);
    });

    testWidgets('set count stepper increments on + tap', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Initially 3 sets
      expect(find.text('3'), findsOneWidget);

      // Find the IconButton with Icons.add (stepper +), not the OutlinedButton
      final stepperAdd = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(IconButton),
      );
      await tester.tap(stepperAdd.first);
      await tester.pump();

      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('set count stepper decrements on - tap', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
              const RoutineSetConfig(restSeconds: 90),
            ],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Initially 3 sets
      expect(find.text('3'), findsOneWidget);

      // Tap the - button
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('rest time chips are visible with default 1m 30s selected', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Rest time chips: 30s, 1m, 1m 30s, 2m, 3m, 4m
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('1m'), findsOneWidget);
      expect(find.text('1m 30s'), findsOneWidget);
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('3m'), findsOneWidget);
      expect(find.text('4m'), findsOneWidget);
    });

    testWidgets('tapping a rest chip changes selection', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      // Tap 2m chip
      await tester.tap(find.text('2m'));
      await tester.pump();

      // The 2m chip should now be selected (ChoiceChip)
      final chip2m = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('2m'), matching: find.byType(ChoiceChip)),
      );
      expect(chip2m.selected, isTrue);
    });

    testWidgets('shows the notes field on the create screen', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Placeholder with the load-bearing "(optional)" suffix.
      expect(
        find.text('Program intent, form cues, deload schedule… (optional)'),
        findsOneWidget,
      );
      // Two TextFields: name + notes.
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('pre-fills notes when editing a routine that has notes', (
      tester,
    ) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        notes: 'Brace before every rep.',
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      expect(find.text('Brace before every rep.'), findsOneWidget);
    });

    testWidgets(
      'notes are optional — Save stays enabled with name + exercise and '
      'empty notes',
      (tester) async {
        final routine = Routine(
          id: 'routine-001',
          name: 'Push Day',
          isDefault: false,
          exercises: [
            RoutineExercise(
              exerciseId: 'ex-1',
              setConfigs: [const RoutineSetConfig(restSeconds: 90)],
              exercise: _makeExercise(),
            ),
          ],
          createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        );

        await tester.pumpWidget(_buildScreen(routine: routine));
        await tester.pumpAndSettle();

        // Notes left blank — Save must still be enabled.
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Save'),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('notes counter is hidden at low length', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Short note');
      await tester.pump();

      // No "/ 600" counter while well below the 500-char threshold.
      expect(find.textContaining('/ 600'), findsNothing);
    });

    testWidgets('notes counter appears near the cap', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // 520 chars — past the 500-char threshold, under the 600 cap.
      await tester.enterText(find.byType(TextField).last, 'x' * 520);
      await tester.pump();

      expect(find.text('520 / 600'), findsOneWidget);
    });

    testWidgets('remove button removes exercise card', (tester) async {
      final routine = Routine(
        id: 'routine-001',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(),
          ),
          RoutineExercise(
            exerciseId: 'ex-2',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(
              id: 'exercise-002',
              name: 'OHP',
              muscleGroup: 'shoulders',
            ),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      await tester.pumpWidget(_buildScreen(routine: routine));
      await tester.pumpAndSettle();

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('OHP'), findsOneWidget);

      // Tap the first close button to remove Bench Press
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('Bench Press'), findsNothing);
      expect(find.text('OHP'), findsOneWidget);
    });

    // Keyboard behavior contract. Tapping the name / notes field must OVERLAY
    // the keyboard over the form — the screen behind stays untouched — instead
    // of resizing the body and reflowing the list (which shoved the exercises
    // under a rising empty band, AND left the cards unpainted because the
    // SingleChildScrollView mis-repaints on resize). `resizeToAvoidBottomInset:
    // false` is the single fix: no resize → no reflow → no mis-repaint. The
    // on-device rendering itself was verified manually because a widget test
    // cannot raise a real soft keyboard (see
    // feedback_visual_verification_physical_device).
    //
    // The body stays a SingleChildScrollView (NOT a ListView) on purpose: it
    // builds every exercise card eagerly, so all cards are in the widget tree /
    // AOM for E2E + screen readers even when scrolled off. A lazy ListView
    // dropped off-viewport cards from the DOM and broke the routine-create E2E.
    group('keyboard overlays the form (does not reflow)', () {
      Routine routineWithExercises() => Routine(
        id: 'routine-kbd',
        name: 'Push Day',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'ex-1',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(name: 'Bench Press'),
          ),
          RoutineExercise(
            exerciseId: 'ex-2',
            setConfigs: [const RoutineSetConfig(restSeconds: 90)],
            exercise: _makeExercise(
              id: 'exercise-002',
              name: 'OHP',
              muscleGroup: 'shoulders',
            ),
          ),
        ],
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );

      testWidgets('Scaffold does not resize for the keyboard', (tester) async {
        await tester.pumpWidget(_buildScreen(routine: routineWithExercises()));
        await tester.pumpAndSettle();

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.resizeToAvoidBottomInset,
          isFalse,
          reason:
              'the keyboard must overlay the form (screen behind untouched), '
              'not push the body up and reflow the exercise list',
        );
      });

      testWidgets('form body eagerly builds all exercise cards (no lazy viewport)', (
        tester,
      ) async {
        await tester.pumpWidget(_buildScreen(routine: routineWithExercises()));
        await tester.pumpAndSettle();

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.body,
          isA<SingleChildScrollView>(),
          reason:
              'the body must build every exercise card eagerly so all cards are '
              'in the tree/AOM for E2E + screen readers even when scrolled off; '
              'a lazy ListView dropped off-viewport cards and broke E2E',
        );
        // Both seeded exercise cards are in the tree, not just the on-screen one.
        expect(find.text('Bench Press'), findsOneWidget);
        expect(find.text('OHP'), findsOneWidget);
      });
    });
  });
}
