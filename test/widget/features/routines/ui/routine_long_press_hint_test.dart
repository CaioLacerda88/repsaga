import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/routines/providers/routine_hint_provider.dart';
import 'package:repsaga/features/routines/ui/widgets/routine_long_press_hint.dart';

import '../../../../helpers/test_material_app.dart';

/// Hive-free fake so the widget tests assert visibility behavior without
/// standing up a Hive box. Seeds the gate boolean and records calls.
class _FakeRoutineHintNotifier extends RoutineHintNotifier {
  _FakeRoutineHintNotifier(this._initial);

  final bool _initial;
  int recordViewCalls = 0;

  @override
  bool build() => _initial;

  @override
  Future<void> recordView() async {
    recordViewCalls++;
  }

  @override
  Future<void> markSeen() async {
    state = false;
  }
}

Widget _harness({required bool initialShow, _FakeRoutineHintNotifier? fake}) {
  return ProviderScope(
    overrides: [
      routineHintProvider.overrideWith(
        () => fake ?? _FakeRoutineHintNotifier(initialShow),
      ),
    ],
    child: const TestMaterialApp(
      home: Scaffold(
        body: RoutineLongPressHint(label: 'Press and hold to edit'),
      ),
    ),
  );
}

void main() {
  group('RoutineLongPressHint', () {
    testWidgets('renders the hint row when the gate is open', (tester) async {
      await tester.pumpWidget(_harness(initialShow: true));
      await tester.pump(); // settle the post-frame recordView callback

      expect(find.text('Press and hold to edit'), findsOneWidget);
      expect(find.byIcon(Icons.touch_app), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Press and hold to edit')),
        findsOneWidget,
      );
    });

    testWidgets('renders nothing when the gate is closed', (tester) async {
      await tester.pumpWidget(_harness(initialShow: false));
      await tester.pump();

      expect(find.text('Press and hold to edit'), findsNothing);
      expect(find.byIcon(Icons.touch_app), findsNothing);
    });

    testWidgets('disappears after the gate flips closed (markSeen)', (
      tester,
    ) async {
      final fake = _FakeRoutineHintNotifier(true);
      await tester.pumpWidget(_harness(initialShow: true, fake: fake));
      await tester.pump();

      // Visible to start.
      expect(find.text('Press and hold to edit'), findsOneWidget);

      // A confirmed long-press elsewhere flips the gate.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RoutineLongPressHint)),
      );
      await container.read(routineHintProvider.notifier).markSeen();
      await tester.pump();

      // The hint row is gone — user-perceptible outcome, not a wiring trace.
      expect(find.text('Press and hold to edit'), findsNothing);
      expect(find.byIcon(Icons.touch_app), findsNothing);
    });

    testWidgets('records exactly one surface view on mount', (tester) async {
      final fake = _FakeRoutineHintNotifier(true);
      await tester.pumpWidget(_harness(initialShow: true, fake: fake));
      await tester.pump();

      expect(fake.recordViewCalls, 1);
    });

    testWidgets('aligns to a custom card edge via horizontalPadding', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routineHintProvider.overrideWith(
              () => _FakeRoutineHintNotifier(true),
            ),
          ],
          child: const TestMaterialApp(
            home: Scaffold(
              body: RoutineLongPressHint(
                label: 'Press and hold to edit',
                horizontalPadding: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Icon hugs the left edge (x ≈ 0) when horizontalPadding is 0.
      final iconLeft = tester.getTopLeft(find.byIcon(Icons.touch_app)).dx;
      expect(iconLeft, lessThan(1));
    });
  });
}
