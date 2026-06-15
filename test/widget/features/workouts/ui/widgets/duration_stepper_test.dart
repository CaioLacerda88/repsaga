/// Widget tests for [DurationStepper] in isolation (Phase 38b).
///
/// The CardioEntryCard tests cover the stepper through the card; this file
/// pins the stepper-only contracts that don't need the provider harness:
/// mm:ss rendering, the long-press hold-to-repeat ramp (mirrors
/// WeightStepper's 400ms + 150ms cadence), dialog input validation, and the
/// zero floor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/widgets/duration_stepper.dart';

import '../../../../../helpers/test_material_app.dart';

void main() {
  Future<int> pumpStepper(WidgetTester tester, {int initial = 1800}) async {
    var value = initial;
    await tester.pumpWidget(
      TestMaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DurationStepper(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return value;
  }

  group('DurationStepper', () {
    testWidgets('renders mm:ss with zero-padded seconds', (tester) async {
      await pumpStepper(tester, initial: 1725);
      expect(find.text('28:45'), findsOneWidget);
    });

    testWidgets('long-pressing + repeats the 30s increment (hold-to-repeat '
        'ramp)', (tester) async {
      await pumpStepper(tester);

      // Press and HOLD the + button: one immediate fire, then after the
      // 400ms initial delay the 150ms periodic timer takes over. Holding
      // for ~1 second must advance the value several steps — the
      // user-visible contract is "holding dials fast".
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.add)),
      );
      // Timeline on the synthetic clock: long-press recognizes at ~500ms →
      // immediate fire; the 400ms hold delay then arms the 150ms periodic.
      // Pump in 150ms steps (rather than one big jump) because the test
      // clock fires a periodic timer at most once per pump — small steps
      // let the repeat cadence actually tick.
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.text('30:00'),
        findsNothing,
        reason: 'holding + must have advanced the value',
      );
      // 30:00 + immediate fire + >= 2 repeats => at least 31:30.
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .firstWhere((s) => RegExp(r'^\d+:\d{2}$').hasMatch(s));
      final parts = shown.split(':');
      final seconds = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      expect(
        seconds,
        greaterThanOrEqualTo(1800 + 3 * 30),
        reason:
            'one immediate fire + periodic repeats over ~1s of hold '
            '(got $shown)',
      );
    });

    testWidgets('minus floors at 0:30 and disables — 0:00 is unreachable', (
      tester,
    ) async {
      await pumpStepper(tester, initial: 60);

      // 1:00 → 0:30, then floored: decrementing again stays at 0:30.
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(find.text('0:30'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(
        find.text('0:30'),
        findsOneWidget,
        reason: 'the stepper floors at one increment (30s), never 0:00',
      );
      expect(find.text('0:00'), findsNothing);

      final minus = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        minus.onPressed,
        isNull,
        reason: 'at the 30s floor the minus button is a no-op',
      );
    });

    testWidgets('dialog rejects malformed input and keeps the old value', (
      tester,
    ) async {
      await pumpStepper(tester);

      await tester.tap(find.text('30:00'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '28:99');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        find.text('30:00'),
        findsOneWidget,
        reason: 'seconds >= 60 is invalid — the value must not change',
      );
    });

    testWidgets('dialog accepts bare minutes', (tester) async {
      await pumpStepper(tester);

      await tester.tap(find.text('30:00'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '45');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('45:00'), findsOneWidget);
    });
  });
}
