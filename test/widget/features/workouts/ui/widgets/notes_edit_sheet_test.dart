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
    // The keyboard-layout contract — VALUE-asserting AND device-faithful.
    //
    // `showModalBottomSheet(isScrollControlled: true)` constrains the sheet to
    // the area ABOVE the keyboard (maxHeight == screen − viewInsets.bottom). The
    // shipped bug added `viewInsets.bottom` AGAIN as bottom padding, double-
    // counting the keyboard: on a real 384x832 device (358dp keyboard) the
    // Column was squeezed to 79dp, overflowed, and the sheet filled the screen
    // top-to-keyboard with content jammed at y=0.
    //
    // This test reproduces that constraint chain by raising the keyboard
    // (FakeViewPadding) BEFORE the modal opens — see layoutAt. The earlier
    // version set viewInsets AFTER the sheet had settled, so the modal never
    // reduced the content area and the test gave a FALSE GREEN that let the bug
    // ship. (Keyboard-inset rendering is also verified on a physical device —
    // see feedback_visual_verification_physical_device — because a single
    // widget viewport can't model every real keyboard height / font scale.)
    const kbInset = 260.0;

    /// Lays the sheet out inside the EXACT constraint chain the modal produces
    /// on a real device when the keyboard is up:
    ///   * the content area is bounded to maxHeight == screen − keyboard (the
    ///     framework already lifts an isScrollControlled sheet above the IME —
    ///     proven on-device: 384×832 screen, 358dp keyboard → 473.6dp area),
    ///   * AND `MediaQuery.viewInsets.bottom == keyboard` is still readable.
    ///
    /// Driving `showModalBottomSheet` in a widget test does NOT reproduce this:
    /// the test harness never reduces the sheet's content area, so the sheet
    /// renders to the true screen bottom and the bug can't surface (that false
    /// green is exactly what let the double-inset ship). Pumping the sheet
    /// directly into the device's constraint chain DOES reproduce it: with a
    /// manual `Padding(bottom: viewInsets.bottom)` the content + a second
    /// keyboard inset overflow the bounded area; without it the
    /// SingleChildScrollView fits or scrolls. This is the regression guard.
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
    layoutAt(WidgetTester tester, Size screen, {String? note}) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: kbInset);
      addTearDown(tester.view.reset);

      final longNote =
          note ??
          List.generate(
            14,
            (i) =>
                'Line ${i + 1}: felt strong today, bumped the working weight.',
          ).join('\n');

      await tester.pumpWidget(
        TestMaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                // Keyboard is up: the sheet can still read viewInsets, so a
                // re-introduced manual inset would overflow here.
                data: MediaQuery.of(
                  context,
                ).copyWith(viewInsets: const EdgeInsets.only(bottom: kbInset)),
                child: Column(
                  children: [
                    // The above-keyboard area: the modal bounds the sheet to
                    // exactly this height on a real device.
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: NotesEditSheet(
                          initialNotes: longNote,
                          title: 'Notes',
                          hintText: _hint,
                          saveLabel: 'Save',
                          cancelLabel: 'Cancel',
                          counterFormatter: _counter,
                        ),
                      ),
                    ),
                    // The keyboard itself.
                    const SizedBox(height: kbInset),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
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
      // Reaching here means NO RenderFlex overflow — the core regression guard.
      // The shipped double-inset bug adds `viewInsets.bottom` as padding INSIDE
      // the already-keyboard-bounded area (this harness reproduces both: maxH ==
      // screen − keyboard AND a readable viewInsets), so the content + a second
      // keyboard inset can't fit → pumpAndSettle throws here. The fix fits or
      // scrolls, so it survives.
      //
      // The device-agnostic positional contract is about the sheet BOX (its
      // internal SingleChildScrollView may scroll to the focused field on a
      // genuinely too-small area, which is correct — content stays reachable):
      //   1. the whole sheet sits ABOVE the keyboard (bottom <= keyboard top),
      //   2. the sheet's top is ON-SCREEN (>= 0) — the double-inset made the box
      //      taller than the area so its top clipped off the top,
      //   3. the sheet never exceeds the above-keyboard area (no double-count).
      const epsilon = 0.5;
      expect(
        l.sheet.bottom,
        lessThanOrEqualTo(l.keyboardTop + epsilon),
        reason:
            'the whole sheet must sit above the keyboard '
            '(bottom ${l.sheet.bottom} > keyboard top ${l.keyboardTop})',
      );
      expect(
        l.sheet.top,
        greaterThanOrEqualTo(-epsilon),
        reason:
            'the sheet top must be on-screen, not clipped above y=0 — the '
            'double-inset bug made the sheet taller than the available area',
      );
      expect(
        l.sheet.height,
        lessThanOrEqualTo(screen.height - kbInset + epsilon),
        reason:
            'the sheet must fit within the area above the keyboard; a larger '
            'height means the keyboard inset was double-counted',
      );
    }

    testWidgets('sheet sits above the keyboard at 320x534 (smallest phone)', (
      tester,
    ) async {
      const screen = Size(320, 534);
      final l = await layoutAt(tester, screen);
      assertContract(l, screen);
    });

    testWidgets('sheet sits above the keyboard at 412x915 (large phone)', (
      tester,
    ) async {
      const screen = Size(412, 915);
      final l = await layoutAt(tester, screen);
      assertContract(l, screen);

      // On a roomy phone the content fits without scrolling, so every part —
      // eyebrow, field, Save, Cancel — must be visible above the keyboard.
      for (final part in [
        ('eyebrow', l.eyebrow),
        ('field', l.field),
        ('save', l.save),
        ('cancel', l.cancel),
      ]) {
        expect(
          part.$2.bottom,
          lessThanOrEqualTo(l.keyboardTop + 0.5),
          reason:
              '${part.$1} must be visible above the keyboard on a large phone '
              '(bottom ${part.$2.bottom} > keyboard top ${l.keyboardTop})',
        );
      }
    });

    testWidgets('no keyboard-sized dead gap below the buttons', (tester) async {
      // A SHORT note so the sheet shrink-wraps with no scroll: the distance
      // from the Save button to the sheet's bottom edge is then exactly the
      // bottom padding. The shipped double-inset bug re-adds a FULL keyboard
      // inset (260dp) as bottom padding, leaving a keyboard-sized empty region
      // below the buttons. A SingleChildScrollView absorbs that by scrolling
      // instead of overflowing, so the overflow- and box-level checks can't see
      // it — ONLY this gap assertion catches the regression. (kbInset / 2
      // cleanly separates the ~20dp fix from the 260dp+ bug, no device budget.)
      final l = await layoutAt(
        tester,
        const Size(412, 915),
        note: 'Quick note',
      );
      final gapBelowButtons = l.sheet.bottom - l.save.bottom;
      expect(
        gapBelowButtons,
        lessThan(kbInset / 2),
        reason:
            'the bottom padding must not re-add the keyboard inset '
            '(dead gap below buttons was $gapBelowButtons)',
      );
    });
  });
}
