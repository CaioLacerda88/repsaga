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

  group('NotesEditSheet layout (keyboard up)', () {
    // The keyboard-layout contract — VALUE-asserting, not value-blind. The
    // previous test only checked `takeException() == null`, which passed even
    // while the sheet rendered FULL-HEIGHT with the eyebrow shoved off the top
    // and the buttons buried under the keyboard. This drives the REAL modal
    // route (the only harness where the BottomSheet hands its child
    // maxHeight == full screen, which is what makes a bare SingleChildScrollView
    // greedily fill and pin content to the top). With a long note + keyboard
    // inset it asserts the actual user-visible outcome:
    //   1. the sheet is CONTENT-SIZED (height < screen) — not full-height,
    //   2. the eyebrow's top edge is on-screen (not clipped above y=0),
    //   3. every part (eyebrow + field + Save + Cancel) sits ABOVE the
    //      keyboard (bottom <= keyboard top).
    //
    // Pre-fix on a 320x534 phone with a long note this was: sheet 0->534
    // (full), eyebrow top at y=6 (jammed against the screen edge), Save/Cancel
    // bottom at y=291 — BELOW the 274 keyboard top (buried). All three
    // assertions below failed.
    const kbInset = 260.0;

    /// Opens the real modal at [screen] with [kbInset] keyboard inset and a
    /// long prefilled note, then returns the laid-out rects.
    Future<
      ({
        Rect sheet,
        Rect eyebrow,
        Rect field,
        Rect save,
        Rect cancel,
        double keyboardTop,
      })
    >
    layoutAt(WidgetTester tester, Size screen) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final longNote = List.generate(
        14,
        (i) => 'Line ${i + 1}: felt strong today, bumped the working weight.',
      ).join('\n');

      await tester.pumpWidget(
        TestMaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => NotesEditSheet.show(
                    context,
                    initialNotes: longNote,
                    title: 'Notes',
                    hintText: _hint,
                    saveLabel: 'Save',
                    cancelLabel: 'Cancel',
                    counterFormatter: _counter,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Raise the keyboard: inject a bottom viewInset the sheet reads via
      // MediaQuery.viewInsetsOf to lift itself above the IME.
      tester.view.viewInsets = const FakeViewPadding(bottom: kbInset);
      await tester.pumpAndSettle();

      return (
        sheet: tester.getRect(
          find.bySemanticsIdentifier('workout-notes-edit-sheet'),
        ),
        eyebrow: tester.getRect(find.text('NOTES')),
        field: tester.getRect(find.byType(TextField)),
        save: tester.getRect(find.bySemanticsIdentifier('workout-notes-save')),
        cancel: tester.getRect(
          find.bySemanticsIdentifier('workout-notes-cancel'),
        ),
        keyboardTop: screen.height - kbInset,
      );
    }

    void assertContract(
      ({
        Rect sheet,
        Rect eyebrow,
        Rect field,
        Rect save,
        Rect cancel,
        double keyboardTop,
      })
      l,
      Size screen,
    ) {
      // 1. Content-sized sheet: the laid-out content (eyebrow top -> buttons
      //    bottom) is far shorter than the screen. (The sheet's RENDER box may
      //    extend behind the keyboard because its bottom inset Padding paints
      //    there, but the keyboard overlays it — what matters is the CONTENT
      //    extent stays small.) Pre-fix the field expanded to ~200dp and the
      //    content spanned nearly the whole screen. Post-fix the content
      //    extent settles at ~156dp on the 320x534 worst-case viewport.
      final contentExtent = l.save.bottom - l.eyebrow.top;
      expect(
        contentExtent,
        lessThan(screen.height - kbInset),
        reason:
            'content must fit in the space above the keyboard, not fill '
            'the whole screen (was full-height pre-fix)',
      );

      // 2. Eyebrow top is on-screen (not clipped above the top edge).
      expect(
        l.eyebrow.top,
        greaterThanOrEqualTo(0),
        reason: 'eyebrow must not be pushed off the top of the screen',
      );

      // 3. Every part sits above the keyboard.
      for (final part in [
        ('eyebrow', l.eyebrow),
        ('field', l.field),
        ('save', l.save),
        ('cancel', l.cancel),
      ]) {
        expect(
          part.$2.bottom,
          lessThanOrEqualTo(l.keyboardTop),
          reason:
              '${part.$1} must sit above the keyboard '
              '(bottom ${part.$2.bottom} > keyboard top ${l.keyboardTop})',
        );
      }
    }

    testWidgets('content sits above the keyboard at 320x534 (smallest phone)', (
      tester,
    ) async {
      const screen = Size(320, 534);
      final l = await layoutAt(tester, screen);
      assertContract(l, screen);
    });

    testWidgets('content sits above the keyboard at 412x915 (large phone)', (
      tester,
    ) async {
      const screen = Size(412, 915);
      final l = await layoutAt(tester, screen);
      assertContract(l, screen);
    });
  });
}
