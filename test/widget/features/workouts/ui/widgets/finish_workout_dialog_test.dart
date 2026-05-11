import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/finish_workout_dialog.dart';
import '../../../../../helpers/test_material_app.dart';

Widget buildTestWidget(Widget child) {
  return TestMaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: Center(child: child)),
  );
}

/// Pumps the dialog as an overlay attached to a real Scaffold so
/// [Navigator.of(context).pop] works correctly.
Future<FinishWorkoutResult?> showDialog(
  WidgetTester tester, {
  required int incompleteCount,
}) async {
  FinishWorkoutResult? result;

  await tester.pumpWidget(
    TestMaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await FinishWorkoutDialog.show(
                context,
                incompleteCount: incompleteCount,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  group('FinishWorkoutDialog', () {
    group('incomplete set warning', () {
      testWidgets('shows warning when incompleteCount is greater than 0', (
        tester,
      ) async {
        await showDialog(tester, incompleteCount: 3);

        expect(find.text('You have 3 incomplete sets'), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      });

      testWidgets('uses singular "set" when incompleteCount is 1', (
        tester,
      ) async {
        await showDialog(tester, incompleteCount: 1);

        expect(find.text('You have 1 incomplete set'), findsOneWidget);
      });

      testWidgets('hides warning when incompleteCount is 0', (tester) async {
        await showDialog(tester, incompleteCount: 0);

        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
        expect(find.textContaining('incomplete'), findsNothing);
      });
    });

    group('dialog structure', () {
      testWidgets('shows title "Seal this session?"', (tester) async {
        // PR-7 brand-voice revisit: pre-fix the dialog title was the
        // generic Material confirm prompt "Finish Workout?". The new copy
        // anchors to the saga / chapter framing the rest of the app uses
        // ("Seal" → bind / close a chapter) without going LARP-y.
        await showDialog(tester, incompleteCount: 0);

        expect(find.text('Seal this session?'), findsOneWidget);
        expect(find.text('Finish Workout?'), findsNothing);
      });

      testWidgets('shows notes text field', (tester) async {
        await showDialog(tester, incompleteCount: 0);

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Add notes (optional)'), findsOneWidget);
      });

      testWidgets('clamps workout notes input to 1000 characters', (
        tester,
      ) async {
        await showDialog(tester, incompleteCount: 0);

        final overLimit = 'x' * 1500;
        await tester.enterText(find.byType(TextField), overLimit);
        await tester.pumpAndSettle();

        // The controller should hold exactly 1000 chars — MaxLengthEnforcement
        // default on mobile/web is `truncateAfterCompositionEnds` / `enforced`.
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text.length, 1000);
      });

      testWidgets('shows "Keep Going" and "Save & Finish" buttons', (
        tester,
      ) async {
        await showDialog(tester, incompleteCount: 0);

        expect(find.text('Keep Going'), findsOneWidget);
        expect(find.text('Save & Finish'), findsOneWidget);
      });
    });

    group('"Keep Going" button', () {
      testWidgets('dismisses dialog and returns null', (tester) async {
        FinishWorkoutResult? captured;

        await tester.pumpWidget(
          TestMaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    captured = await FinishWorkoutDialog.show(
                      context,
                      incompleteCount: 2,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Keep Going'));
        await tester.pumpAndSettle();

        expect(captured, isNull);
        expect(find.text('Seal this session?'), findsNothing);
      });
    });

    group('"Save & Finish" button', () {
      testWidgets(
        'returns FinishWorkoutResult with null notes when field is empty',
        (tester) async {
          FinishWorkoutResult? captured;

          await tester.pumpWidget(
            TestMaterialApp(
              theme: AppTheme.dark,
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      captured = await FinishWorkoutDialog.show(
                        context,
                        incompleteCount: 0,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Save & Finish'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(captured!.notes, isNull);
        },
      );

      testWidgets(
        'returns FinishWorkoutResult with notes when text is entered',
        (tester) async {
          FinishWorkoutResult? captured;

          await tester.pumpWidget(
            TestMaterialApp(
              theme: AppTheme.dark,
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      captured = await FinishWorkoutDialog.show(
                        context,
                        incompleteCount: 0,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'Great session today');
          await tester.tap(find.text('Save & Finish'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(captured!.notes, 'Great session today');
        },
      );

      testWidgets('trims whitespace-only notes to null', (tester) async {
        FinishWorkoutResult? captured;

        await tester.pumpWidget(
          TestMaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    captured = await FinishWorkoutDialog.show(
                      context,
                      incompleteCount: 0,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '   ');
        await tester.tap(find.text('Save & Finish'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!.notes, isNull);
      });

      testWidgets('dismisses dialog after confirming', (tester) async {
        await tester.pumpWidget(
          TestMaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      FinishWorkoutDialog.show(context, incompleteCount: 0),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save & Finish'));
        await tester.pumpAndSettle();

        expect(find.text('Seal this session?'), findsNothing);
      });
    });
  });
}
