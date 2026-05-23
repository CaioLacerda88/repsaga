import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/title_equip_row.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required Future<void> Function() onEquipPressed,
    VoidCallback? onLaterPressed,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TitleEquipRow(
            eyebrowLabel: 'Novo título',
            titleName: 'Pilar de Ferro',
            equipLabel: 'EQUIPAR',
            laterLabel: 'depois',
            equippedLabel: 'Equipado ✓',
            onEquipPressed: onEquipPressed,
            onLaterPressed: onLaterPressed,
          ),
        ),
      ),
    );
  }

  testWidgets('renders title name and labels', (tester) async {
    await pumpRow(tester, onEquipPressed: () async {});
    expect(find.text('Pilar de Ferro'), findsOneWidget);
    expect(find.text('EQUIPAR'), findsOneWidget);
    expect(find.text('depois'), findsOneWidget);
  });

  testWidgets('tap EQUIPAR invokes callback exactly once', (tester) async {
    var calls = 0;
    await pumpRow(
      tester,
      onEquipPressed: () async {
        calls += 1;
      },
    );
    await tester.tap(find.text('EQUIPAR'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('successful equip transitions to "Equipado ✓"', (tester) async {
    await pumpRow(tester, onEquipPressed: () async {});
    await tester.tap(find.text('EQUIPAR'));
    await tester.pumpAndSettle();
    expect(find.text('Equipado ✓'), findsOneWidget);
    expect(find.text('EQUIPAR'), findsNothing);
    expect(find.text('depois'), findsNothing);
  });

  testWidgets('tap "depois" collapses the row', (tester) async {
    await pumpRow(tester, onEquipPressed: () async {});
    expect(find.text('Pilar de Ferro'), findsOneWidget);
    await tester.tap(find.text('depois'));
    await tester.pumpAndSettle();
    expect(find.text('Pilar de Ferro'), findsNothing);
  });

  testWidgets('tap "depois" invokes onLaterPressed callback when provided', (
    tester,
  ) async {
    var laterCalls = 0;
    await pumpRow(
      tester,
      onEquipPressed: () async {},
      onLaterPressed: () => laterCalls += 1,
    );
    await tester.tap(find.text('depois'));
    await tester.pumpAndSettle();
    expect(laterCalls, 1);
  });

  testWidgets('EQUIPAR does NOT trigger again while in-flight RPC is pending', (
    tester,
  ) async {
    var calls = 0;
    final completer = Completer<void>();
    await pumpRow(
      tester,
      onEquipPressed: () async {
        calls += 1;
        await completer.future;
      },
    );
    await tester.tap(find.text('EQUIPAR'));
    await tester.pump();
    expect(calls, 1);
    // While loading, the FilledButton's onPressed is null so a re-tap is
    // a no-op — confirm by tapping the button widget directly.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(calls, 1);
    completer.complete();
    await tester.pumpAndSettle();
  });
}
