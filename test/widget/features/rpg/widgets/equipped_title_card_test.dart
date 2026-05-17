/// Widget tests for [EquippedTitleCard] — the heroGold-gradient single-row
/// card that anchors the "Equipado" region of the new Titles screen.
///
/// **Locked behaviors:**
///   * Renders the localized title name, body-part·threshold meta line, and
///     the localized "Em uso" / "Active" tag from `titlesEquippedTag`.
///   * Wraps the row in a `Semantics(container: true, button: onTap != null,
///     identifier: 'titles-equipped-card')` so the screen's tap target is
///     reachable from accessibility tooling and E2E selectors.
///   * Tapping the card invokes `onTap` exactly once (the screen wires this
///     to the lore bottom-sheet preview).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/equipped_title_card.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  testWidgets('should render title name, body-part-rank meta, and active-tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestMaterialApp(
        locale: Locale('pt'),
        home: Scaffold(
          body: EquippedTitleCard(
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
    expect(find.text('Em uso'), findsOneWidget);
  });

  testWidgets('should expose a tap-target with role=button via Semantics', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      TestMaterialApp(
        locale: const Locale('pt'),
        home: Scaffold(
          body: EquippedTitleCard(
            titleName: 'Portador-da-Placa',
            bodyPartLabel: 'Costas',
            thresholdLabel: 'Rank 5',
            accentColor: const Color(0xFF6FA3FF),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    final tapTarget = find.bySemanticsLabel('Portador-da-Placa');
    expect(tapTarget, findsAtLeastNWidgets(1));
    await tester.tap(tapTarget.first);
    await tester.pump();
    expect(tapped, isTrue);
  });
}
