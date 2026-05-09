import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/shared/widgets/weight_stepper.dart';

import '../../../helpers/test_material_app.dart';

/// A11y + i18n regression-guard tests for [WeightStepper].
///
/// Family 3 / Family 6 (combined PR): the +/- IconButtons must expose a
/// localized accessible name so screen-reader users can identify them, and
/// the value-zone Semantics label must read through `AppLocalizations` —
/// not the previously hard-coded English literal at `weight_stepper.dart:187`.
///
/// **Risk pinned by this group:** the +/- gestures are wrapped in a parent
/// `GestureDetector(onLongPressStart: _startRepeating)`. Adding a Material
/// `Tooltip` (via `IconButton.tooltip:`) would compete with that long-press
/// in the gesture arena. The tooltip-vs-longpress test below asserts the
/// rapid-increment-repeat behavior survives whichever a11y mechanism we
/// pick (tooltip OR explicit `Semantics(button: true, label: ...)` wrapper).
Widget buildTestWidget(Widget child, {Locale? locale}) {
  return TestMaterialApp(
    locale: locale,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('WeightStepper a11y / i18n', () {
    group('decrement / increment accessible name (Family 3)', () {
      testWidgets(
        'decrement button is reachable via "Decrease weight" semantics label (en)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(WeightStepper(value: 60.0, onChanged: (_) {})),
          );

          // Either a Tooltip lifts the message into the accessible name OR an
          // explicit Semantics wrapper does. Either way, the screen reader
          // sees "Decrease weight" on the minus button.
          expect(find.bySemanticsLabel('Decrease weight'), findsOneWidget);
        },
      );

      testWidgets(
        'increment button is reachable via "Increase weight" semantics label (en)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(WeightStepper(value: 60.0, onChanged: (_) {})),
          );

          expect(find.bySemanticsLabel('Increase weight'), findsOneWidget);
        },
      );

      testWidgets(
        'decrement button is reachable via "Diminuir peso" under pt locale',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(
              WeightStepper(value: 60.0, onChanged: (_) {}),
              locale: const Locale('pt'),
            ),
          );

          expect(find.bySemanticsLabel('Diminuir peso'), findsOneWidget);
        },
      );
    });

    group('value-zone semantics label (Family 6 — i18n leak)', () {
      // **Why a regex (not exact-string) matcher:** the value-zone Semantics
      // wraps the visible Text(formatted) — Flutter's semantic merge folds
      // that Text's content into the parent's label, producing a final
      // node label like "Weight value: 80.5 kg. Tap to enter weight.\n80.5".
      // The regex matches the localized prefix; the trailing merge is part
      // of the rendered AOM and not part of the contract this test pins.
      testWidgets(
        'value zone Semantics label is localized (en) — uses ARB key, not English literal',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(
              WeightStepper(value: 80.5, onChanged: (_) {}, unit: 'kg'),
            ),
          );

          expect(
            find.bySemanticsLabel(
              RegExp(r'Weight value: 80\.5 kg\. Tap to enter weight\.'),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('value zone Semantics label switches to pt under pt locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestWidget(
            WeightStepper(value: 80.5, onChanged: (_) {}, unit: 'kg'),
            locale: const Locale('pt'),
          ),
        );

        // pt-BR: "Valor do peso: 80,5 kg. Toque para inserir o peso."
        // The number formatter switches the decimal separator under pt.
        expect(
          find.bySemanticsLabel(
            RegExp(r'Valor do peso: 80,5 kg\. Toque para inserir o peso\.'),
          ),
          findsOneWidget,
        );
      });
    });

    group('long-press fire regression guard (tooltip-vs-longpress arena)', () {
      // **Why this test exists:** if we adopt `IconButton.tooltip:` for the
      // +/- buttons, Flutter's Tooltip widget injects its own
      // GestureDetector. That detector competes with the existing parent
      // `GestureDetector(onLongPressStart: _startRepeating)` in the gesture
      // arena. If the tooltip wins the arena on long-press, the rapid-
      // increment-repeat behavior (400ms hold delay → 150ms periodic) breaks
      // silently — the user holds, the tooltip pops up, and the value
      // doesn't change.
      //
      // **Test design note:** `tester.longPress` simulates a pointer-down +
      // 500ms hold + pointer-up. Once the pointer lifts, `onLongPressEnd`
      // fires `_stopRepeating()` and the periodic timer is cancelled — so
      // we can't easily assert the periodic-tick contract under
      // `tester.longPress` (the timer is dead by the time pumpAndSettle
      // returns). Instead, we pin the contract that matters: a long-press
      // gesture causes the GestureDetector to receive `onLongPressStart`
      // and call `_decrement` / `_increment` at least once. If a Tooltip
      // wins the gesture arena, this single fire would NOT happen — the
      // tooltip would absorb the long-press and `onChanged` would stay at
      // zero entries.

      testWidgets(
        'long-pressing the increment button fires onChanged at least once',
        (tester) async {
          final emitted = <double>[];
          await tester.pumpWidget(
            buildTestWidget(
              WeightStepper(
                value: 60.0,
                increment: 2.5,
                onChanged: emitted.add,
              ),
            ),
          );

          await tester.longPress(find.byIcon(Icons.add));
          await tester.pumpAndSettle();

          expect(
            emitted.length,
            greaterThanOrEqualTo(1),
            reason:
                'Long-pressing + must fire onChanged at least once via '
                '`_startRepeating(_increment)`. If this is 0, the tooltip '
                'or another competing gesture captured the long-press '
                'before the GestureDetector could fire onLongPressStart.',
          );
          expect(emitted.first, 62.5);
        },
      );

      testWidgets(
        'long-pressing the decrement button fires onChanged at least once',
        (tester) async {
          final emitted = <double>[];
          await tester.pumpWidget(
            buildTestWidget(
              WeightStepper(
                value: 100.0,
                increment: 2.5,
                onChanged: emitted.add,
              ),
            ),
          );

          await tester.longPress(find.byIcon(Icons.remove));
          await tester.pumpAndSettle();

          expect(
            emitted.length,
            greaterThanOrEqualTo(1),
            reason:
                'Long-pressing − must fire onChanged at least once. If 0, '
                'a competing gesture captured the long-press.',
          );
          expect(emitted.first, 97.5);
        },
      );

      testWidgets(
        'parent GestureDetector(onLongPressStart) survives the a11y wrap',
        (tester) async {
          // Structural pin: the +/- IconButtons must remain inside a
          // GestureDetector that declares `onLongPressStart`. If a future
          // refactor replaces the wrapper with one that lacks long-press
          // (e.g., a `Tooltip` wrapper used as the only ancestor of the
          // IconButton), the rapid-repeat behavior is dead — this test
          // catches that regression at compile-against-tree time.
          await tester.pumpWidget(
            buildTestWidget(WeightStepper(value: 60.0, onChanged: (_) {})),
          );

          final longPressGestures = tester
              .widgetList<GestureDetector>(find.byType(GestureDetector))
              .where((g) => g.onLongPressStart != null)
              .toList();
          expect(
            longPressGestures.length,
            greaterThanOrEqualTo(2),
            reason:
                'WeightStepper must keep TWO GestureDetectors with '
                'onLongPressStart wired (one per +/- button) so the '
                'rapid-repeat behavior survives the a11y label wrap.',
          );
        },
      );
    });
  });
}
