/// Widget tests for [NextTitleRow] — the progress row that renders inside
/// the "Próximos" region of the Titles screen.
///
/// **Locked behaviors:**
///   * Renders the title name, tabular `current / threshold` figure, a
///     body-part-hue progress bar (FractionallySizedBox, NOT Align — see
///     cluster_align_widthfactor_zerofill), and the ICU-plural sub-line.
///   * Singular vs plural sub-line copy switches at `remaining == 1`.
///   * The progress-bar `widthFactor` equals `currentValue / thresholdValue`.
///   * Wraps in `Semantics(container, explicitChildNodes, button,
///     identifier: 'titles-next-row-{slug}')`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/next_title_row.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  testWidgets(
    'should render title name, tabular current/threshold, and progress bar',
    (tester) async {
      await tester.pumpWidget(
        const TestMaterialApp(
          locale: Locale('pt'),
          home: Scaffold(
            body: NextTitleRow(
              slug: 'iron_back_v',
              titleName: 'Dorso-de-Ferro V',
              accentColor: Color(0xFF6FA3FF),
              currentValue: 16,
              thresholdValue: 20,
              bodyPartLabel: 'Costas',
              isCharacterLevel: false,
            ),
          ),
        ),
      );

      expect(find.text('Dorso-de-Ferro V'), findsOneWidget);
      expect(find.text('16 / 20'), findsOneWidget);

      final fsb = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fsb.widthFactor, closeTo(0.8, 1e-9));
    },
  );

  testWidgets('should render singular sub-line when remaining is 1', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestMaterialApp(
        locale: Locale('pt'),
        home: Scaffold(
          body: NextTitleRow(
            slug: 'iron_back_v',
            titleName: 'Dorso-de-Ferro V',
            accentColor: Color(0xFF6FA3FF),
            currentValue: 19,
            thresholdValue: 20,
            bodyPartLabel: 'Costas',
            isCharacterLevel: false,
          ),
        ),
      ),
    );

    expect(find.text('Costas · falta 1 rank'), findsOneWidget);
  });

  testWidgets(
    'should render plural sub-line when remaining is greater than 1',
    (tester) async {
      await tester.pumpWidget(
        const TestMaterialApp(
          locale: Locale('pt'),
          home: Scaffold(
            body: NextTitleRow(
              slug: 'iron_back_v',
              titleName: 'Dorso-de-Ferro V',
              accentColor: Color(0xFF6FA3FF),
              currentValue: 16,
              thresholdValue: 20,
              bodyPartLabel: 'Costas',
              isCharacterLevel: false,
            ),
          ),
        ),
      );

      expect(find.text('Costas · faltam 4 ranks'), findsOneWidget);
    },
  );

  testWidgets(
    'should render character sub-line when isCharacterLevel is true',
    (tester) async {
      await tester.pumpWidget(
        const TestMaterialApp(
          locale: Locale('pt'),
          home: Scaffold(
            body: NextTitleRow(
              slug: 'apprentice',
              titleName: 'Aprendiz',
              accentColor: Color(0xFF6A2FA8),
              currentValue: 7,
              thresholdValue: 10,
              bodyPartLabel: 'Personagem',
              isCharacterLevel: true,
            ),
          ),
        ),
      );

      expect(find.text('Personagem · faltam 3 níveis'), findsOneWidget);
    },
  );

  testWidgets('should fire onTap when the row is tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      TestMaterialApp(
        locale: const Locale('pt'),
        home: Scaffold(
          body: NextTitleRow(
            slug: 'iron_back_v',
            titleName: 'Dorso-de-Ferro V',
            accentColor: const Color(0xFF6FA3FF),
            currentValue: 16,
            thresholdValue: 20,
            bodyPartLabel: 'Costas',
            isCharacterLevel: false,
            onTap: () => tapped++,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Dorso-de-Ferro V').first);
    await tester.pump();

    expect(tapped, 1);
  });
}
