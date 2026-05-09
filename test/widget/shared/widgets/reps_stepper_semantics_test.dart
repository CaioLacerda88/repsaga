import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/shared/widgets/reps_stepper.dart';

import '../../../helpers/test_material_app.dart';

/// A11y + i18n regression-guard tests for [RepsStepper] — symmetric with
/// `weight_stepper_semantics_test.dart`. See that file for the rationale on
/// the tooltip-vs-longpress arena risk.
Widget buildTestWidget(Widget child, {Locale? locale}) {
  return TestMaterialApp(
    locale: locale,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('RepsStepper a11y / i18n', () {
    group('decrement / increment accessible name (Family 3)', () {
      testWidgets(
        'decrement button is reachable via "Decrease reps" semantics label (en)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(RepsStepper(value: 8, onChanged: (_) {})),
          );

          expect(find.bySemanticsLabel('Decrease reps'), findsOneWidget);
        },
      );

      testWidgets(
        'increment button is reachable via "Increase reps" semantics label (en)',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(RepsStepper(value: 8, onChanged: (_) {})),
          );

          expect(find.bySemanticsLabel('Increase reps'), findsOneWidget);
        },
      );

      testWidgets(
        'decrement button is reachable via "Diminuir repetições" under pt locale',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(
              RepsStepper(value: 8, onChanged: (_) {}),
              locale: const Locale('pt'),
            ),
          );

          expect(find.bySemanticsLabel('Diminuir repetições'), findsOneWidget);
        },
      );
    });

    group('value-zone semantics label (Family 6 — i18n leak)', () {
      // Regex matcher rather than exact-string — see
      // `weight_stepper_semantics_test.dart` for the rationale on why the
      // visible Text content merges into the parent Semantics label.
      testWidgets(
        'value zone Semantics label is localized (en) — uses ARB key, not English literal',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(RepsStepper(value: 10, onChanged: (_) {})),
          );

          expect(
            find.bySemanticsLabel(
              RegExp(r'Reps value: 10\. Tap to enter reps\.'),
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
            RepsStepper(value: 10, onChanged: (_) {}),
            locale: const Locale('pt'),
          ),
        );

        expect(
          find.bySemanticsLabel(
            RegExp(
              r'Valor das repetições: 10\. Toque para inserir as repetições\.',
            ),
          ),
          findsOneWidget,
        );
      });
    });

    group('long-press fire regression guard (tooltip-vs-longpress arena)', () {
      // See `weight_stepper_semantics_test.dart` for the rationale on why
      // this group asserts at-least-one fire (not the periodic-tick count).
      testWidgets(
        'long-pressing the increment button fires onChanged at least once',
        (tester) async {
          final emitted = <int>[];
          await tester.pumpWidget(
            buildTestWidget(
              RepsStepper(value: 8, increment: 1, onChanged: emitted.add),
            ),
          );

          await tester.longPress(find.byIcon(Icons.add));
          await tester.pumpAndSettle();

          expect(emitted.length, greaterThanOrEqualTo(1));
          expect(emitted.first, 9);
        },
      );

      testWidgets(
        'long-pressing the decrement button fires onChanged at least once',
        (tester) async {
          final emitted = <int>[];
          await tester.pumpWidget(
            buildTestWidget(
              RepsStepper(value: 20, increment: 1, onChanged: emitted.add),
            ),
          );

          await tester.longPress(find.byIcon(Icons.remove));
          await tester.pumpAndSettle();

          expect(emitted.length, greaterThanOrEqualTo(1));
          expect(emitted.first, 19);
        },
      );

      testWidgets(
        'parent GestureDetector(onLongPressStart) survives the a11y wrap',
        (tester) async {
          await tester.pumpWidget(
            buildTestWidget(RepsStepper(value: 8, onChanged: (_) {})),
          );

          final longPressGestures = tester
              .widgetList<GestureDetector>(find.byType(GestureDetector))
              .where((g) => g.onLongPressStart != null)
              .toList();
          expect(
            longPressGestures.length,
            greaterThanOrEqualTo(2),
            reason:
                'RepsStepper must keep TWO GestureDetectors with '
                'onLongPressStart wired (one per +/- button) so the '
                'rapid-repeat behavior survives the a11y label wrap.',
          );
        },
      );
    });
  });
}
