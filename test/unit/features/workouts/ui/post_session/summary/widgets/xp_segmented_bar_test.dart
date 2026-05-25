import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/xp_segmented_bar.dart';

void main() {
  const labels = <BodyPart, String>{
    BodyPart.chest: 'Peito',
    BodyPart.back: 'Costas',
    BodyPart.legs: 'Pernas',
    BodyPart.shoulders: 'Ombros',
    BodyPart.arms: 'Braços',
    BodyPart.core: 'Core',
  };

  Future<void> pumpBar(
    WidgetTester tester, {
    required List<XpBarSegment> segments,
    Size viewport = const Size(360, 800),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: XpSegmentedBar(bodyPartLabels: labels, segments: segments),
          ),
        ),
      ),
    );
  }

  group('XpSegmentedBar', () {
    testWidgets('renders single-segment full-width hue + label', (
      tester,
    ) async {
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(
            bodyPart: BodyPart.chest,
            hue: AppColors.bodyPartChest,
            xp: 618,
          ),
        ],
      );

      // Single segment label visible (uppercased).
      expect(find.text('PEITO'), findsOneWidget);
      // The Expanded segment fills the available width (no other ColoredBox
      // children fighting for flex).
      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 1);
      expect(coloredBoxes.single.color, AppColors.bodyPartChest);
    });

    testWidgets('renders 2-segment 50/50 with equal flex', (tester) async {
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(
            bodyPart: BodyPart.chest,
            hue: AppColors.bodyPartChest,
            xp: 100,
          ),
          XpBarSegment(
            bodyPart: BodyPart.back,
            hue: AppColors.bodyPartBack,
            xp: 100,
          ),
        ],
      );

      // Both labels render.
      expect(find.text('PEITO'), findsOneWidget);
      expect(find.text('COSTAS'), findsOneWidget);

      // Two segments visible.
      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 2);
    });

    testWidgets('renders 3-segment proportional 60/30/10 flex values', (
      tester,
    ) async {
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(
            bodyPart: BodyPart.chest,
            hue: AppColors.bodyPartChest,
            xp: 60,
          ),
          XpBarSegment(
            bodyPart: BodyPart.back,
            hue: AppColors.bodyPartBack,
            xp: 30,
          ),
          XpBarSegment(bodyPart: BodyPart.legs, hue: AppColors.success, xp: 10),
        ],
      );

      // Three labels.
      expect(find.text('PEITO'), findsOneWidget);
      expect(find.text('COSTAS'), findsOneWidget);
      expect(find.text('PERNAS'), findsOneWidget);

      // Three colored bar segments.
      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 3);

      // Flex ratios on the bar segments — find the Expanded children of
      // the 6dp-tall Row (the first SizedBox(height: 6) holds the bar).
      final barSizedBox = tester.widget<SizedBox>(
        find.byWidgetPredicate((w) => w is SizedBox && w.height == 6).first,
      );
      // Walk the bar's row children — Expandeds carry the flex.
      final expandeds = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byWidget(barSizedBox),
              matching: find.byType(Expanded),
            ),
          )
          .toList();
      expect(expandeds.map((e) => e.flex).toList(), [60, 30, 10]);
    });

    testWidgets('renders 4-segment proportional bar', (tester) async {
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(
            bodyPart: BodyPart.chest,
            hue: AppColors.bodyPartChest,
            xp: 400,
          ),
          XpBarSegment(
            bodyPart: BodyPart.back,
            hue: AppColors.bodyPartBack,
            xp: 200,
          ),
          XpBarSegment(
            bodyPart: BodyPart.legs,
            hue: AppColors.success,
            xp: 100,
          ),
          XpBarSegment(bodyPart: BodyPart.arms, hue: AppColors.error, xp: 50),
        ],
      );

      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 4);
      expect(find.text('BRAÇOS'), findsOneWidget);
    });

    testWidgets('empty segments list renders nothing', (tester) async {
      await pumpBar(tester, segments: const []);

      expect(
        find.descendant(
          of: find.byType(XpSegmentedBar),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
      // Outer widget collapses to 0×0.
      final size = tester.getSize(find.byType(XpSegmentedBar));
      expect(size.height, 0);
    });

    testWidgets('total XP 0 renders nothing (defensive)', (tester) async {
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(bodyPart: BodyPart.chest, hue: Colors.pink, xp: 0),
          XpBarSegment(bodyPart: BodyPart.back, hue: Colors.blue, xp: 0),
        ],
      );

      expect(
        find.descendant(
          of: find.byType(XpSegmentedBar),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
      final size = tester.getSize(find.byType(XpSegmentedBar));
      expect(size.height, 0);
    });

    testWidgets('narrow segment still paints; label truncates with ellipsis', (
      tester,
    ) async {
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(
            bodyPart: BodyPart.chest,
            hue: AppColors.bodyPartChest,
            xp: 1000,
          ),
          // Tiny narrow segment: 1 / 1001 of the bar.
          XpBarSegment(
            bodyPart: BodyPart.back,
            hue: AppColors.bodyPartBack,
            xp: 1,
          ),
        ],
      );

      // Both segments paint.
      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 2);

      // Narrow label is present but its Text widget should be configured
      // to ellipsis at single line.
      final costasText = tester.widget<Text>(find.text('COSTAS'));
      expect(costasText.overflow, TextOverflow.ellipsis);
      expect(costasText.maxLines, 1);
    });
  });
}
