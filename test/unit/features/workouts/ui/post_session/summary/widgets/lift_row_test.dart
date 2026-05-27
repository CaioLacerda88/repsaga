import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/lift_row.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required String exerciseName,
    required double peakWeightKg,
    required int peakReps,
    String? prLabel,
    Color bodyPartHue = AppColors.bodyPartChest,
    String weightUnitLabel = 'kg',
    Size viewport = const Size(360, 800),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: LiftRow(
              bodyPartHue: bodyPartHue,
              exerciseName: exerciseName,
              peakReps: peakReps,
              peakWeightKg: peakWeightKg,
              prLabel: prLabel,
              weightUnitLabel: weightUnitLabel,
            ),
          ),
        ),
      ),
    );
  }

  group('LiftRow', () {
    testWidgets('renders dot, exercise name, weight × reps, no PR flag', (
      tester,
    ) async {
      await pumpRow(
        tester,
        exerciseName: 'Supino',
        peakWeightKg: 95,
        peakReps: 5,
      );

      expect(find.text('Supino'), findsOneWidget);
      expect(find.text('95kg × 5'), findsOneWidget);
      expect(find.text('PR'), findsNothing);
    });

    testWidgets('weight × reps uses textCream when prLabel is null', (
      tester,
    ) async {
      await pumpRow(
        tester,
        exerciseName: 'Supino',
        peakWeightKg: 80,
        peakReps: 8,
      );

      final weightText = tester.widget<Text>(find.text('80kg × 8'));
      expect(weightText.style?.color, AppColors.textCream);
    });

    testWidgets(
      'weight × reps uses heroGold + renders PR flag when prLabel set',
      (tester) async {
        await pumpRow(
          tester,
          exerciseName: 'Supino',
          peakWeightKg: 95,
          peakReps: 5,
          prLabel: 'PR',
        );

        final weightText = tester.widget<Text>(find.text('95kg × 5'));
        expect(weightText.style?.color, AppColors.heroGold);
        final prText = tester.widget<Text>(find.text('PR'));
        expect(prText.style?.color, AppColors.heroGold);
      },
    );

    testWidgets('BP hue dot color matches bodyPartHue param', (tester) async {
      await pumpRow(
        tester,
        exerciseName: 'Agachamento',
        peakWeightKg: 120,
        peakReps: 5,
        bodyPartHue: AppColors.bodyPartBack,
      );

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('lift-row-hue-dot')),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.bodyPartBack);
    });

    testWidgets('long exercise name truncates with ellipsis at 360dp', (
      tester,
    ) async {
      const longName = 'Levantamento Terra Romeno com Halter Unilateral';
      await pumpRow(
        tester,
        exerciseName: longName,
        peakWeightKg: 65,
        peakReps: 10,
      );

      final text = tester.widget<Text>(find.text(longName));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 2);
    });

    testWidgets('long exercise name wraps to 2 lines and row grows past 32dp '
        'on a narrow viewport', (tester) async {
      const longName = 'Levantamento Terra Romeno Unilateral com Halter Pesado';
      await pumpRow(
        tester,
        exerciseName: longName,
        peakWeightKg: 65,
        peakReps: 10,
        viewport: const Size(240, 800),
      );

      // Row's intrinsic size grows above the 32dp floor when wrapping.
      final rowSize = tester.getSize(find.byType(LiftRow));
      expect(rowSize.height, greaterThan(32));
      expect(rowSize.height, lessThanOrEqualTo(48));
    });
  });
}
