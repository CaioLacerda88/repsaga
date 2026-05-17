/// Widget tests for [EarnedTitleRow] — the earned-but-not-equipped row that
/// renders below [EquippedTitleCard] on the Titles screen.
///
/// **Locked behaviors:**
///   * Renders the title name, body-part·threshold meta line, and the
///     "Equipar" / "Equip" CTA from `titlesRowEquipCta`.
///   * Tap-on-row invokes `onTap` (opens the lore bottom sheet).
///   * Tap-on-CTA invokes `onEquip` (fires the equip mutation).
///   * Wraps in `Semantics(container, explicitChildNodes, button,
///     identifier: 'titles-earned-row-{slug}')` so Playwright's role=button
///     selector resolves and forwards the click to the InkWell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/earned_title_row.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  testWidgets(
    'should render title name, body-part-threshold meta, and Equipar CTA',
    (tester) async {
      await tester.pumpWidget(
        const TestMaterialApp(
          locale: Locale('pt'),
          home: Scaffold(
            body: EarnedTitleRow(
              slug: 'plate_bearer',
              titleName: 'Portador-da-Placa',
              bodyPartLabel: 'Costas',
              thresholdLabel: 'Rank 5',
              accentColor: Color(0xFF6FA3FF),
            ),
          ),
        ),
      );

      expect(find.text('Portador-da-Placa'), findsOneWidget);
      expect(find.textContaining('Costas'), findsOneWidget);
      expect(find.textContaining('Rank 5'), findsOneWidget);
      expect(find.text('Equipar'), findsOneWidget);
    },
  );

  testWidgets('should fire onEquip when the CTA is tapped', (tester) async {
    var equipTapped = 0;
    var rowTapped = 0;
    await tester.pumpWidget(
      TestMaterialApp(
        locale: const Locale('pt'),
        home: Scaffold(
          body: EarnedTitleRow(
            slug: 'plate_bearer',
            titleName: 'Portador-da-Placa',
            bodyPartLabel: 'Costas',
            thresholdLabel: 'Rank 5',
            accentColor: const Color(0xFF6FA3FF),
            onTap: () => rowTapped++,
            onEquip: () => equipTapped++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Equipar'));
    await tester.pump();

    expect(equipTapped, 1);
    expect(rowTapped, 0);
  });

  testWidgets('should fire onTap when the row body is tapped', (tester) async {
    var rowTapped = 0;
    await tester.pumpWidget(
      TestMaterialApp(
        locale: const Locale('pt'),
        home: Scaffold(
          body: EarnedTitleRow(
            slug: 'plate_bearer',
            titleName: 'Portador-da-Placa',
            bodyPartLabel: 'Costas',
            thresholdLabel: 'Rank 5',
            accentColor: const Color(0xFF6FA3FF),
            onTap: () => rowTapped++,
            onEquip: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Portador-da-Placa').first);
    await tester.pump();

    expect(rowTapped, 1);
  });
}
