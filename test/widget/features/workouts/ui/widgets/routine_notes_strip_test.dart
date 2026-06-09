import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/widgets/exercise_list.dart';
import 'package:repsaga/features/workouts/ui/widgets/routine_notes_strip.dart';

import '../../../../../helpers/test_material_app.dart';

void main() {
  // ExerciseList is exercised with an EMPTY exercise list so no provider-heavy
  // ExerciseCard is built — the notes strip (index 0) is the only item, which
  // is exactly the user-visible contract under test: strip present iff the
  // source routine has notes, absent otherwise (identical-to-today when none).
  Widget buildList({String? routineNotes}) {
    return TestMaterialApp(
      home: Scaffold(
        body: ExerciseList(
          exercises: const [],
          reorderMode: false,
          routineNotes: routineNotes,
        ),
      ),
    );
  }

  group('Active-workout routine notes header strip', () {
    testWidgets('renders the strip when the routine has notes', (tester) async {
      await tester.pumpWidget(
        buildList(routineNotes: 'Brace before every rep.'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoutineNotesStrip), findsOneWidget);
      // Eyebrow label visible on the strip.
      expect(find.text('TRAINING NOTES'), findsOneWidget);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    });

    testWidgets('shows NO strip when routine notes are null (ad-hoc workout)', (
      tester,
    ) async {
      await tester.pumpWidget(buildList());
      await tester.pumpAndSettle();

      // Zero-chrome contract: ad-hoc workout / no routine notes → no strip.
      expect(find.byType(RoutineNotesStrip), findsNothing);
      expect(find.text('TRAINING NOTES'), findsNothing);
    });

    testWidgets('shows NO strip when routine notes are blank/whitespace', (
      tester,
    ) async {
      await tester.pumpWidget(buildList(routineNotes: '   '));
      await tester.pumpAndSettle();

      expect(find.byType(RoutineNotesStrip), findsNothing);
    });

    testWidgets('tapping the strip opens a read-only sheet with the notes', (
      tester,
    ) async {
      const notesBody =
          'Program: 5x5. Deload week 4. Keep the bar over mid-foot.';
      await tester.pumpWidget(buildList(routineNotes: notesBody));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(RoutineNotesStrip));
      await tester.pumpAndSettle();

      // Sheet shows the full notes body, exposed for E2E via this identifier.
      expect(find.text(notesBody), findsOneWidget);
      expect(
        find.bySemanticsLabel('TRAINING NOTES'),
        findsWidgets,
        reason: 'eyebrow appears on both the strip and the open sheet',
      );
    });
  });
}
