import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/xp_segmented_bar.dart';

void main() {
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
            child: XpSegmentedBar(segments: segments),
          ),
        ),
      ),
    );
  }

  group('XpSegmentedBar', () {
    testWidgets('renders single-segment full-width hue block', (tester) async {
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

    testWidgets('bar height is 16dp (round-3 spec)', (tester) async {
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

      final barSize = tester.getSize(find.byType(XpSegmentedBar));
      expect(
        barSize.height,
        16.0,
        reason:
            'UX-critic round-3 locks the bar at 16dp tall (bumped from 14dp '
            'pre-round-3 alongside the label removal).',
      );
      // The exposed const must stay in sync.
      expect(XpSegmentedBar.barHeight, 16.0);
    });

    testWidgets('segments paint as plain hue blocks with no inner text', (
      tester,
    ) async {
      // Round-3: labels were dropped because reverse-printed BP names
      // crowded narrow segments and duplicated the labeling already
      // carried by the per-BP rank delta rows below.
      await pumpBar(
        tester,
        segments: const [
          XpBarSegment(
            bodyPart: BodyPart.chest,
            hue: AppColors.bodyPartChest,
            xp: 500,
          ),
          XpBarSegment(
            bodyPart: BodyPart.back,
            hue: AppColors.bodyPartBack,
            xp: 500,
          ),
        ],
      );

      final innerTexts = find.descendant(
        of: find.byType(XpSegmentedBar),
        matching: find.byType(Text),
      );
      expect(
        innerTexts,
        findsNothing,
        reason:
            'No Text widgets should render inside the bar — labels were '
            'dropped per UX-critic round-3.',
      );
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

      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 2);

      final expandeds = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(Expanded),
            ),
          )
          .toList();
      expect(expandeds.map((e) => e.flex).toList(), [100, 100]);
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

      final coloredBoxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(coloredBoxes.length, 3);

      // Walk the bar's row children — Expandeds carry the flex.
      final expandeds = tester
          .widgetList<Expanded>(
            find.descendant(
              of: find.byType(XpSegmentedBar),
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
            xp: 300,
          ),
          XpBarSegment(
            bodyPart: BodyPart.legs,
            hue: AppColors.success,
            xp: 200,
          ),
          XpBarSegment(bodyPart: BodyPart.arms, hue: AppColors.error, xp: 200),
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
  });
}
