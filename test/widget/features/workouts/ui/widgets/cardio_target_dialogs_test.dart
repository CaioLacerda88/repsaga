/// Widget tests for the cardio target dialogs (Phase 38h blocker fixes).
///
/// Pins the two blocker-bug regressions:
///   1a. The format guidance (`helperText`) renders even when the field is
///       pre-filled (the old `hintText` was masked by the pre-fill).
///   1b. Validate-before-close: a non-empty unparseable entry shows an inline
///       `errorText` AND does NOT pop (the dialog stays open, the target is
///       unchanged) — instead of silently popping `null`, which the caller
///       treats identically to Cancel (a no-op that reads as a broken OK).
///       A valid entry pops the parsed value; an empty entry pops null
///       (cancel-equivalent no-op, preserving pre-38h behavior).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/widgets/cardio_target_dialogs.dart';

import '../../../../../helpers/test_material_app.dart';

/// Pumps a host with a single button that opens the duration dialog and
/// captures whatever it pops into [result].
Future<int?> _openDuration(
  WidgetTester tester, {
  int initialSeconds = 1680, // 28:00 pre-fill
}) async {
  int? result;
  var popped = false;
  await tester.pumpWidget(
    TestMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCardioDurationDialog(
                  context,
                  initialSeconds: initialSeconds,
                );
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // `popped` is read by callers that need to confirm the future completed.
  expect(popped, isFalse, reason: 'dialog should be open, not yet popped');
  return result;
}

Future<double?> _openDistance(
  WidgetTester tester, {
  double? initialMeters,
}) async {
  double? result;
  await tester.pumpWidget(
    TestMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCardioDistanceDialog(
                  context,
                  initialMeters: initialMeters,
                  distanceUnit: 'km',
                  locale: 'en',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('Duration dialog — helper guidance (1a)', () {
    testWidgets('the helper renders even with a pre-filled field', (
      tester,
    ) async {
      await _openDuration(tester); // pre-filled with 28:00
      // The field carries the pre-fill, yet the format helper is visible.
      expect(find.text('28:00'), findsOneWidget);
      expect(find.text('mm:ss or minutes — e.g. 28:00'), findsOneWidget);
    });
  });

  group('Duration dialog — validate before close (1b)', () {
    Future<void> openAndType(WidgetTester tester, String text) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    Future<void> host(WidgetTester tester, void Function(int?) onResult) async {
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    onResult(
                      await showCardioDurationDialog(
                        context,
                        initialSeconds: 1680,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('valid mm:ss (28:45) pops 1725 and closes', (tester) async {
      int? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '28:45');

      expect(completed, isTrue);
      expect(captured, 1725);
      expect(find.text('Enter duration'), findsNothing);
    });

    testWidgets('bare minutes (28) pops 1680 and closes', (tester) async {
      int? captured;
      await host(tester, (v) => captured = v);
      await openAndType(tester, '28');
      expect(captured, 1680);
    });

    testWidgets('very large bare minutes (999) pops 59940 and closes', (
      tester,
    ) async {
      // No upper clamp in parseDuration — a 999-minute target is accepted as
      // 59940s. Pins that "very large" is a valid target, not silently eaten.
      int? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '999');
      expect(completed, isTrue);
      expect(captured, 59940);
      expect(find.text('Enter duration'), findsNothing);
    });

    // PRODUCT-AMBIGUITY FLAG (zero duration target): parseDuration('0') and
    // ('0:00') both return 0 (NOT null), so the dialog accepts zero as a valid
    // target and pops 0. Whether a 0-second cardio target is meaningful is a
    // product call — these tests pin the CURRENT behavior (zero is accepted).
    // If product later decides zero should be rejected, parseDuration must
    // gain a `> 0` guard and these expectations flip to the invalid-path
    // (errorText shown, no pop). Flagged in the QA report.
    testWidgets('zero bare (0) is accepted and pops 0', (tester) async {
      int? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '0');
      expect(completed, isTrue);
      expect(captured, 0);
      expect(find.text('Enter duration'), findsNothing);
    });

    testWidgets('zero mm:ss (0:00) is accepted and pops 0', (tester) async {
      int? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '0:00');
      expect(completed, isTrue);
      expect(captured, 0);
      expect(find.text('Enter duration'), findsNothing);
    });

    for (final invalid in <String>['28:90', '28,5', 'abc', ':30']) {
      testWidgets('invalid "$invalid" shows errorText and does NOT pop', (
        tester,
      ) async {
        var completed = false;
        await host(tester, (_) => completed = true);
        await openAndType(tester, invalid);

        // Dialog stays open — the future never completed.
        expect(
          completed,
          isFalse,
          reason: 'an unparseable entry must not pop the dialog',
        );
        expect(find.text('Enter duration'), findsOneWidget);
        expect(find.text('Use mm:ss — e.g. 28:00'), findsOneWidget);
        // The format helper is replaced by the error in the error state.
        expect(find.text('mm:ss or minutes — e.g. 28:00'), findsNothing);
      });
    }

    testWidgets('whitespace-only entry is treated as empty → pops null', (
      tester,
    ) async {
      int? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '   ');

      // Empty/whitespace = cancel-equivalent no-op: pops null, closes, no error.
      expect(completed, isTrue);
      expect(captured, isNull);
      expect(find.text('Enter duration'), findsNothing);
      expect(find.text('Use mm:ss — e.g. 28:00'), findsNothing);
    });

    testWidgets('empty field on OK pops null (clear-equivalent no-op)', (
      tester,
    ) async {
      int? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(captured, isNull);
      expect(find.text('Enter duration'), findsNothing);
    });

    testWidgets('editing after an error clears the error state', (
      tester,
    ) async {
      await host(tester, (_) {});
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '28:90');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Use mm:ss — e.g. 28:00'), findsOneWidget);

      // Typing again clears the sticky error and restores the helper.
      await tester.enterText(find.byType(TextField), '30');
      await tester.pumpAndSettle();
      expect(find.text('Use mm:ss — e.g. 28:00'), findsNothing);
      expect(find.text('mm:ss or minutes — e.g. 28:00'), findsOneWidget);
    });

    testWidgets('Cancel pops null without validating', (tester) async {
      int? captured = 999;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc'); // invalid
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(captured, isNull);
      expect(find.text('Enter duration'), findsNothing);
    });
  });

  group('Distance dialog — helper guidance (1c)', () {
    testWidgets('the helper example renders', (tester) async {
      await _openDistance(tester, initialMeters: 5000);
      expect(find.text('e.g. 5.2'), findsOneWidget);
    });
  });

  group('Distance dialog — validate before close (1b)', () {
    Future<void> host(
      WidgetTester tester,
      void Function(double?) onResult,
    ) async {
      await tester.pumpWidget(
        TestMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    onResult(
                      await showCardioDistanceDialog(
                        context,
                        initialMeters: null,
                        distanceUnit: 'km',
                        locale: 'en',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openAndType(WidgetTester tester, String text) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('valid 5.2 pops 5200m and closes', (tester) async {
      double? captured;
      await host(tester, (v) => captured = v);
      await openAndType(tester, '5.2');
      expect(captured, 5200.0);
      expect(find.text('Enter distance'), findsNothing);
    });

    testWidgets('comma decimal 5,2 pops 5200m', (tester) async {
      double? captured;
      await host(tester, (v) => captured = v);
      await openAndType(tester, '5,2');
      expect(captured, 5200.0);
    });

    testWidgets('whole number 5 pops 5000m', (tester) async {
      double? captured;
      await host(tester, (v) => captured = v);
      await openAndType(tester, '5');
      expect(captured, 5000.0);
    });

    testWidgets('zero 0 is valid (>= 0) and pops 0m', (tester) async {
      double? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '0');
      expect(completed, isTrue);
      expect(captured, 0.0);
    });

    testWidgets('very large distance (999) pops 999000m and closes', (
      tester,
    ) async {
      // No upper clamp — a 999 km target converts to 999000m and is accepted.
      double? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await openAndType(tester, '999');
      expect(completed, isTrue);
      expect(captured, 999000.0);
      expect(find.text('Enter distance'), findsNothing);
    });

    for (final invalid in <String>['-3', 'abc']) {
      testWidgets('invalid "$invalid" shows errorText and does NOT pop', (
        tester,
      ) async {
        var completed = false;
        await host(tester, (_) => completed = true);
        await openAndType(tester, invalid);

        expect(completed, isFalse);
        expect(find.text('Enter distance'), findsOneWidget);
        expect(find.text('Enter a valid distance'), findsOneWidget);
      });
    }

    testWidgets('empty field on OK pops null (no error)', (tester) async {
      double? captured;
      var completed = false;
      await host(tester, (v) {
        captured = v;
        completed = true;
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(captured, isNull);
      expect(find.text('Enter a valid distance'), findsNothing);
      expect(find.text('Enter distance'), findsNothing);
    });

    testWidgets('editing after an error clears the distance error state', (
      tester,
    ) async {
      await host(tester, (_) {});
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '-3'); // invalid
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid distance'), findsOneWidget);

      // Typing a valid value clears the sticky error and restores the helper.
      await tester.enterText(find.byType(TextField), '5.2');
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid distance'), findsNothing);
      expect(find.text('e.g. 5.2'), findsOneWidget);
    });
  });
}
