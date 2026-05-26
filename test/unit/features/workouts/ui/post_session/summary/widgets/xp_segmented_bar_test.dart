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

      // Single segment label visible (uppercased), reverse-printed in
      // abyss inside the colored segment.
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

    // -----------------------------------------------------------------
    // Phase 31 Bug B — mockup-spec compliance regression guards
    // -----------------------------------------------------------------

    testWidgets(
      'bar height is 14dp per mockup §S2 (Phase 31 Bug B regression)',
      (tester) async {
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
          14.0,
          reason:
              'Mockup §S2 locks the bar at 14dp tall; pre-fix the widget '
              'used a 6dp height that was effectively invisible on the '
              'abyss background.',
        );
        // The exposed const must stay in sync.
        expect(XpSegmentedBar.barHeight, 14.0);
      },
    );

    testWidgets(
      'labels render INSIDE the colored segment, reverse-printed in abyss '
      '(Phase 31 Bug B mockup compliance)',
      (tester) async {
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

        // Find the PEITO label's color — must be abyss so the dark
        // text reverse-prints on the hue background.
        final labelText = tester.widget<Text>(find.text('PEITO'));
        expect(
          labelText.style?.color,
          AppColors.abyss,
          reason:
              'Mockup §S2 specifies labels reverse-printed in abyss '
              'inside the hue block.',
        );

        // The label Text must be a descendant of the ColoredBox that
        // paints its segment (NOT a sibling row beneath it).
        final coloredBox = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byType(XpSegmentedBar),
            matching: find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.bodyPartChest,
            ),
          ),
        );
        final labelAncestors = find.ancestor(
          of: find.text('PEITO'),
          matching: find.byWidget(coloredBox),
        );
        expect(
          labelAncestors,
          findsOneWidget,
          reason:
              'Each label must paint INSIDE its segment ColoredBox, not '
              'in a separate row beneath the bar.',
        );
      },
    );

    testWidgets(
      'narrow segments drop their label so the colored block stays clean '
      '(Phase 31 Bug B narrow-segment defensive)',
      (tester) async {
        // 1000 vs 1 — the second segment paints at ~0.3dp wide on a
        // 320dp viewport; the label can't fit.
        await pumpBar(
          tester,
          segments: const [
            XpBarSegment(
              bodyPart: BodyPart.chest,
              hue: AppColors.bodyPartChest,
              xp: 1000,
            ),
            XpBarSegment(
              bodyPart: BodyPart.back,
              hue: AppColors.bodyPartBack,
              xp: 1,
            ),
          ],
        );

        // Wide segment label renders.
        expect(find.text('PEITO'), findsOneWidget);
        // Narrow segment label drops (no Text rendered) — the block
        // still paints, observable as a second ColoredBox.
        expect(find.text('COSTAS'), findsNothing);

        final coloredBoxes = tester
            .widgetList<ColoredBox>(
              find.descendant(
                of: find.byType(XpSegmentedBar),
                matching: find.byType(ColoredBox),
              ),
            )
            .toList();
        expect(
          coloredBoxes.length,
          2,
          reason:
              'Both segments must still paint — only the narrow label '
              'drops; the colored block stays so the BP contribution '
              'remains visible.',
        );
      },
    );

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
      // the 14dp-tall bar (Phase 31 Bug B mockup spec; the single
      // SizedBox(height: 14) inside the LayoutBuilder holds the bar).
      final barSizedBox = tester.widget<SizedBox>(
        find.byWidgetPredicate((w) => w is SizedBox && w.height == 14).first,
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
      // XP shares chosen so every segment paints at >= 24dp on a 360dp
      // viewport (the minimum-label-width threshold). At 360dp - 40dp
      // padding - 6dp gaps = 314dp paintable across 4 segments.
      // Smallest segment (200/1100 of total) → ~57dp; well above the
      // 24dp floor so the label renders.
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

    testWidgets(
      'visible label uses single-line clip + softWrap false (overflow does '
      'not bleed when the segment is borderline width)',
      (tester) async {
        // 5/6 split — both segments wide enough to show labels; pin the
        // text-flow configuration that prevents wraps under the new
        // labels-inside-segment layout.
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
              xp: 600,
            ),
          ],
        );

        for (final label in const ['PEITO', 'COSTAS']) {
          final text = tester.widget<Text>(find.text(label));
          expect(text.maxLines, 1);
          expect(text.softWrap, false);
          expect(text.overflow, TextOverflow.clip);
        }
      },
    );
  });
}
