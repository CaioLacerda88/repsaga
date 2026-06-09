// Q1 (notes-edit-after) Surface-A refinements — NotesEditSheet behavior.
//
// Pins the user-visible contract the ui-ux-critic locked:
//   * the near-cap counter is HIDDEN at low length and SHOWN near the cap,
//   * the counter color escalates (textDim → warning → error) as the budget
//     runs out,
//   * the evocative in-field hint renders (distinct from the affordance),
//   * Cancel / Save are at least 48dp tall (tap-target floor),
//   * Save returns the typed text; Cancel returns null.
//
// The sheet takes its strings as constructor props, so no l10n harness is
// needed (Decoupling Rule 2 / widget_l10n_parameterization).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/widgets/notes_edit_sheet.dart';

import '../../../../../helpers/test_material_app.dart';

const _hint =
    'How was the session? Observations, how you felt, what you would '
    'adjust…';

String _counter(int current, int max) => '$current / $max';

/// Mutable holder for the value `NotesEditSheet.show` resolves with. The
/// sheet's future completes only when the user taps Save / Cancel (long after
/// the [showSheet] helper returns), so the result is captured into this holder
/// asynchronously and read back by tests after they drive the dismissal.
class SheetResult {
  NotesEditResult? result;
  bool resolved = false;
}

/// Pumps the sheet as a real modal so Navigator.pop returns through `show`.
/// Returns a holder the caller reads AFTER tapping Save / Cancel.
Future<SheetResult> showSheet(
  WidgetTester tester, {
  String? initialNotes,
  int maxLength = 2000,
  int counterThreshold = 1800,
}) async {
  final holder = SheetResult();

  await tester.pumpWidget(
    TestMaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              holder.result = await NotesEditSheet.show(
                context,
                initialNotes: initialNotes,
                title: 'Notes',
                hintText: _hint,
                saveLabel: 'Save',
                cancelLabel: 'Cancel',
                counterFormatter: _counter,
                maxLength: maxLength,
                counterThreshold: counterThreshold,
              );
              holder.resolved = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  return holder;
}

/// The visible counter text widget (excludes the hint / labels).
Finder counterFinder() => find.textContaining(' / ');

void main() {
  group('NotesEditSheet counter', () {
    testWidgets('is hidden while well below the cap', (tester) async {
      await showSheet(tester);

      await tester.enterText(find.byType(TextField), 'short note');
      await tester.pumpAndSettle();

      // Default threshold is 1800 — a 10-char note is nowhere near it.
      expect(counterFinder(), findsNothing);
    });

    testWidgets('appears once the length crosses the threshold', (
      tester,
    ) async {
      // Low threshold so the test types a small amount of text.
      await showSheet(tester, maxLength: 100, counterThreshold: 10);

      await tester.enterText(find.byType(TextField), 'x' * 5);
      await tester.pumpAndSettle();
      expect(counterFinder(), findsNothing);

      await tester.enterText(find.byType(TextField), 'x' * 12);
      await tester.pumpAndSettle();

      // 12 of 100 → counter visible, reads "12 / 100".
      expect(find.text('12 / 100'), findsOneWidget);
    });

    testWidgets('counter is textDim while remaining > 50', (tester) async {
      await showSheet(tester, maxLength: 100, counterThreshold: 10);

      // 40/100 → 60 remaining (> 50) → textDim.
      await tester.enterText(find.byType(TextField), 'x' * 40);
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('40 / 100'));
      expect(text.style?.color, AppColors.textDim);
    });

    testWidgets('counter turns warning when ≤ 50 remain', (tester) async {
      await showSheet(tester, maxLength: 100, counterThreshold: 10);

      // 60/100 → 40 remaining (≤ 50, > 0) → warning.
      await tester.enterText(find.byType(TextField), 'x' * 60);
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('60 / 100'));
      expect(text.style?.color, AppColors.warning);
    });

    testWidgets('counter turns error at the cap (0 remaining)', (tester) async {
      await showSheet(tester, maxLength: 100, counterThreshold: 10);

      // maxLength hard-stops at 100, so 100/100 → 0 remaining → error.
      await tester.enterText(find.byType(TextField), 'x' * 150);
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('100 / 100'));
      expect(text.style?.color, AppColors.error);
    });
  });

  group('NotesEditSheet hint + tap targets', () {
    testWidgets('renders the evocative in-field hint', (tester) async {
      await showSheet(tester);

      expect(find.text(_hint), findsOneWidget);
    });

    testWidgets('Cancel and Save meet the 48dp tap-target floor', (
      tester,
    ) async {
      await showSheet(tester);

      // tester.getSize captures Flutter's padded MaterialTapTargetSize —
      // boundingBox / minimumSize alone under-report (see
      // feedback_tap_target_measurement).
      final cancelSize = tester.getSize(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      final saveSize = tester.getSize(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(cancelSize.height, greaterThanOrEqualTo(48));
      expect(saveSize.height, greaterThanOrEqualTo(48));
    });
  });

  group('NotesEditSheet result', () {
    testWidgets('Save returns the typed text', (tester) async {
      final holder = await showSheet(tester);

      await tester.enterText(find.byType(TextField), 'Bumped 2.5kg');
      await tester.tap(find.bySemanticsIdentifier('workout-notes-save'));
      await tester.pumpAndSettle();

      expect(holder.resolved, isTrue);
      expect(holder.result?.notes, 'Bumped 2.5kg');
    });

    testWidgets('Cancel returns null', (tester) async {
      final holder = await showSheet(tester, initialNotes: 'original');

      await tester.tap(find.bySemanticsIdentifier('workout-notes-cancel'));
      await tester.pumpAndSettle();

      expect(holder.resolved, isTrue);
      expect(holder.result, isNull);
    });
  });
}
