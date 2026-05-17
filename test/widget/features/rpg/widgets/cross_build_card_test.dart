/// Widget tests for [CrossBuildCard] — the heroGold-accented "Especial"
/// card that renders inside the "Próximos" region of the Titles screen
/// when the user is within 1 rank of every condition of a cross-build
/// title.
///
/// **Locked behaviors:**
///   * Renders the title name + localized "Especial" / "Special" badge
///     (`titlesCrossBuildEspecial`).
///   * Per-condition rows: met conditions render an `Icon(Icons.check)`,
///     unmet conditions render a `FractionallySizedBox` progress bar
///     (cluster_align_widthfactor_zerofill).
///   * Bottleneck sub-line `titlesCrossBuildBottleneck(bodyPartLabel)`.
///   * Wraps in `Semantics(container, explicitChildNodes, button,
///     identifier: 'titles-cross-build-card-{slug}')`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/cross_build_title_evaluator.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/widgets/cross_build_card.dart';

import '../../../../helpers/test_material_app.dart';

void main() {
  const colors = {
    BodyPart.chest: Color(0xFFFF6F61),
    BodyPart.back: Color(0xFF6FA3FF),
    BodyPart.legs: Color(0xFFB36DFF),
  };
  const labels = {
    BodyPart.chest: 'Peito',
    BodyPart.back: 'Costas',
    BodyPart.legs: 'Pernas',
  };

  testWidgets(
    'should render title name, Especial badge, and bottleneck sub-line',
    (tester) async {
      await tester.pumpWidget(
        const TestMaterialApp(
          locale: Locale('pt'),
          home: Scaffold(
            body: CrossBuildCard(
              slug: 'iron_bound',
              titleName: 'Acorrentado-ao-Ferro',
              stats: [
                CrossBuildStat(
                  bodyPart: BodyPart.chest,
                  current: 60,
                  floor: 60,
                ),
                CrossBuildStat(bodyPart: BodyPart.back, current: 60, floor: 60),
                CrossBuildStat(bodyPart: BodyPart.legs, current: 59, floor: 60),
              ],
              bottleneckBodyPart: BodyPart.legs,
              bottleneckLabel: 'Pernas',
              statColors: colors,
              statLabels: labels,
            ),
          ),
        ),
      );

      expect(find.text('Acorrentado-ao-Ferro'), findsOneWidget);
      expect(find.text('Especial'), findsOneWidget);
      expect(find.text('◆ Falta 1 rank em Pernas'), findsOneWidget);
    },
  );

  testWidgets(
    'should render check on met conditions and progress bar on unmet',
    (tester) async {
      await tester.pumpWidget(
        const TestMaterialApp(
          locale: Locale('pt'),
          home: Scaffold(
            body: CrossBuildCard(
              slug: 'iron_bound',
              titleName: 'Acorrentado-ao-Ferro',
              stats: [
                // chest met
                CrossBuildStat(
                  bodyPart: BodyPart.chest,
                  current: 60,
                  floor: 60,
                ),
                // back unmet
                CrossBuildStat(bodyPart: BodyPart.back, current: 59, floor: 60),
              ],
              bottleneckBodyPart: BodyPart.back,
              bottleneckLabel: 'Costas',
              statColors: colors,
              statLabels: labels,
            ),
          ),
        ),
      );

      // Exactly one met condition → one check icon.
      expect(find.byIcon(Icons.check), findsOneWidget);
      // Exactly one unmet condition → one progress bar.
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    },
  );

  testWidgets('should fire onTap when the card is tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      TestMaterialApp(
        locale: const Locale('pt'),
        home: Scaffold(
          body: CrossBuildCard(
            slug: 'iron_bound',
            titleName: 'Acorrentado-ao-Ferro',
            stats: const [
              CrossBuildStat(bodyPart: BodyPart.chest, current: 60, floor: 60),
              CrossBuildStat(bodyPart: BodyPart.back, current: 59, floor: 60),
            ],
            bottleneckBodyPart: BodyPart.back,
            bottleneckLabel: 'Costas',
            statColors: colors,
            statLabels: labels,
            onTap: () => tapped++,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Acorrentado-ao-Ferro').first);
    await tester.pump();

    expect(tapped, 1);
  });
}
