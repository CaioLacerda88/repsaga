/// Widget tests for [VitalityTrendChart].
///
/// The chart is six lines on a fixed 0..100 Y-axis. Five render as ghost
/// lines — each carrying its OWN body-part identity color at ~35% alpha,
/// 1sp stroke (Phase 26c). The **selected** body part renders vivid (its
/// `bodyPartColor`, 2.5sp) with a terminal dot at the right edge.
///
/// **Visual locks under test:**
///   * Six [LineChartBarData] entries — one per [activeBodyParts] body part.
///   * Selected line uses `bodyPartColor[selectedBodyPart]`; the five ghost
///     lines each carry their own body-part identity color at reduced alpha.
///   * `LineTouchData(enabled: false)` — touch is structurally off.
///   * No grid lines — `gridData.show == false`.
///   * No chart frame — `borderData.show == false`.
///   * Y-axis fixed 0..100; X-axis labels are hybrid per the spec.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/stats_deep_dive_state.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';
import 'package:repsaga/features/rpg/ui/widgets/vitality_trend_chart.dart';

import '../../../../helpers/test_material_app.dart';

/// Build a synthetic 90-day daily trace that linearly grows from 0 → 0.8.
List<TrendPoint> _ramp({
  required DateTime start,
  required int days,
  double end = 0.8,
}) {
  return [
    for (var i = 0; i < days; i++)
      TrendPoint(
        date: start.add(Duration(days: i)),
        pct: end * (i / (days - 1)),
      ),
  ];
}

Map<BodyPart, List<TrendPoint>> _allRamps({
  required DateTime start,
  required int days,
}) {
  return {
    for (final bp in activeBodyParts) bp: _ramp(start: start, days: days),
  };
}

Widget _wrap({
  required Map<BodyPart, List<TrendPoint>> trendByBodyPart,
  required BodyPart selected,
  required DateTime windowStart,
  required DateTime windowEnd,
  required bool useNarrowWindow,
}) {
  return TestMaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: SizedBox(
          // The chart needs a finite width for its LayoutBuilder; 360 is the
          // mid-point of common phone viewports.
          width: 360,
          child: VitalityTrendChart(
            trendByBodyPart: trendByBodyPart,
            selectedBodyPart: selected,
            windowStart: windowStart,
            windowEnd: windowEnd,
            useNarrowWindow: useNarrowWindow,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('VitalityTrendChart', () {
    final today = DateTime.utc(2026, 4, 30);
    final windowStart = today.subtract(const Duration(days: 90));

    testWidgets('renders six LineChartBarData — one per active body part', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          trendByBodyPart: _allRamps(start: windowStart, days: 91),
          selected: BodyPart.chest,
          windowStart: windowStart,
          windowEnd: today,
          useNarrowWindow: false,
        ),
      );
      await tester.pump();

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.length, activeBodyParts.length);
    });

    testWidgets(
      'should render the selected line in bodyPartColor + 2.5sp and ghost lines in each body-part identity at <1.0 alpha + 1sp',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: _allRamps(start: windowStart, days: 91),
            selected: BodyPart.legs,
            windowStart: windowStart,
            windowEnd: today,
            useNarrowWindow: false,
          ),
        );
        await tester.pump();

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        final selectedColor = VitalityStateStyles.bodyPartColor[BodyPart.legs];
        final selectedBars = chart.data.lineBarsData
            .where((b) => b.color == selectedColor)
            .toList();
        expect(selectedBars.length, 1);
        expect(selectedBars.single.barWidth, 2.5);

        // Phase 26c (Task 7): each ghost now carries its OWN body-part
        // identity color at reduced alpha — was a single textDim ghost
        // pre-Task-7. We pull the ghost bars by color-inequality with
        // selectedColor, then assert per-body-part that exactly one ghost
        // bar matches its identity RGB at <1.0 alpha and 1sp stroke.
        final ghostBars = chart.data.lineBarsData
            .where((b) => b.color != selectedColor)
            .toList();
        expect(ghostBars.length, activeBodyParts.length - 1);

        for (final bp in activeBodyParts) {
          if (bp == BodyPart.legs) continue; // legs is the selected body part
          final expectedRgb = VitalityStateStyles.bodyPartColor[bp]!;
          final matching = ghostBars.where((b) {
            final c = b.color!;
            return (c.r * 255).round() == (expectedRgb.r * 255).round() &&
                (c.g * 255).round() == (expectedRgb.g * 255).round() &&
                (c.b * 255).round() == (expectedRgb.b * 255).round() &&
                c.a < 1.0 &&
                b.barWidth == 1.0;
          }).toList();
          expect(
            matching,
            hasLength(1),
            reason:
                'expected exactly one ghost bar matching ${bp.dbValue} '
                'identity color at <1.0 alpha and 1sp stroke',
          );
        }
      },
    );

    testWidgets('grid + border + touch are all disabled', (tester) async {
      await tester.pumpWidget(
        _wrap(
          trendByBodyPart: _allRamps(start: windowStart, days: 91),
          selected: BodyPart.chest,
          windowStart: windowStart,
          windowEnd: today,
          useNarrowWindow: false,
        ),
      );
      await tester.pump();

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.gridData.show, isFalse);
      expect(chart.data.borderData.show, isFalse);
      expect(chart.data.lineTouchData.enabled, isFalse);
    });

    testWidgets(
      'Y-axis labels anchor at 0%/100% with breathing room above 100%',
      (tester) async {
        // Vitality % is conceptually a 0..100 scale (the labels read "0%" and
        // "100%" — see the X/Y label widget filter). The chart's `maxY`
        // carries a small headroom margin so the terminal `%` callout and any
        // ghost line sustained at 100% (e.g. a body part at full vitality)
        // sit visibly inside the plot area instead of bleeding into the
        // section above. Regression guard for the L9 "ugly borders" fix —
        // killing the headroom puts the y=100 ghost line at the chart's
        // visual top edge again, where it reads as a frame artifact.
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: _allRamps(start: windowStart, days: 91),
            selected: BodyPart.chest,
            windowStart: windowStart,
            windowEnd: today,
            useNarrowWindow: false,
          ),
        );
        await tester.pump();

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        // L9 round-2: both top + bottom carry headroom so ghost lines at
        // exactly 0% or 100% don't hug the chart's visual edges. Y-axis
        // labels still anchor at 0/100 via value-equality filter.
        expect(chart.data.minY, lessThan(0));
        expect(chart.data.maxY, greaterThan(100));
      },
    );

    testWidgets(
      'body part with empty trace draws no line (no spurious flat-zero baseline)',
      (tester) async {
        // L9 regression: prior to the fix, `_buildSpots` returned a flat-zero
        // fallback `[(0, 0), (spanDays, 0)]` for body parts with no points in
        // the window. fl_chart painted those as a horizontal line at y=0
        // spanning the full chart width — read as an "ugly bottom border" in
        // the deep-dive screen screenshot. The fallback now returns an empty
        // spot list so fl_chart paints nothing.
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: const {BodyPart.chest: <TrendPoint>[]},
            selected: BodyPart.chest,
            windowStart: windowStart,
            windowEnd: today,
            useNarrowWindow: false,
          ),
        );
        await tester.pump();

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        // Every active body part still contributes a `LineChartBarData` so
        // the chart's bar count stays stable across selection changes — but
        // each empty-trend bar carries zero spots, drawing nothing.
        expect(chart.data.lineBarsData.length, activeBodyParts.length);
        for (final bar in chart.data.lineBarsData) {
          expect(
            bar.spots,
            isEmpty,
            reason:
                'empty trend should map to empty spots — a flat-zero '
                'fallback re-introduces the L9 bottom-border artifact',
          );
        }
      },
    );

    testWidgets('X-axis labels show "90 days ago" + "Today" in 90-day mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          trendByBodyPart: _allRamps(start: windowStart, days: 91),
          selected: BodyPart.chest,
          windowStart: windowStart,
          windowEnd: today,
          useNarrowWindow: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('90 days ago'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('X-axis labels show "<n> days ago" + "Today" in narrow mode', (
      tester,
    ) async {
      // 12 days of activity → narrow window from 12 days ago → today.
      final narrowStart = today.subtract(const Duration(days: 12));
      await tester.pumpWidget(
        _wrap(
          trendByBodyPart: _allRamps(start: narrowStart, days: 13),
          selected: BodyPart.chest,
          windowStart: narrowStart,
          windowEnd: today,
          useNarrowWindow: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('12 days ago'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets(
      'X-axis singular "1 day ago" pluralizes correctly (boundary case)',
      (tester) async {
        final yesterday = today.subtract(const Duration(days: 1));
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: {BodyPart.chest: _ramp(start: yesterday, days: 2)},
            selected: BodyPart.chest,
            windowStart: yesterday,
            windowEnd: today,
            useNarrowWindow: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1 day ago'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
      },
    );

    testWidgets(
      'changing selectedBodyPart re-paints with the new vivid color',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: _allRamps(start: windowStart, days: 91),
            selected: BodyPart.chest,
            windowStart: windowStart,
            windowEnd: today,
            useNarrowWindow: false,
          ),
        );
        await tester.pump();

        final firstChart = tester.widget<LineChart>(find.byType(LineChart));
        final chestVivid = firstChart.data.lineBarsData
            .where(
              (b) =>
                  b.color == VitalityStateStyles.bodyPartColor[BodyPart.chest],
            )
            .length;
        expect(chestVivid, 1);

        // Re-pump with a different selection — the chart should now have one
        // bar in legs' bodyPartColor (and zero in chest's).
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: _allRamps(start: windowStart, days: 91),
            selected: BodyPart.legs,
            windowStart: windowStart,
            windowEnd: today,
            useNarrowWindow: false,
          ),
        );
        await tester.pumpAndSettle();

        final secondChart = tester.widget<LineChart>(find.byType(LineChart));
        final legsVivid = secondChart.data.lineBarsData
            .where(
              (b) =>
                  b.color == VitalityStateStyles.bodyPartColor[BodyPart.legs],
            )
            .length;
        expect(legsVivid, 1);
        final chestStillVivid = secondChart.data.lineBarsData
            .where(
              (b) =>
                  b.color == VitalityStateStyles.bodyPartColor[BodyPart.chest],
            )
            .length;
        expect(chestStillVivid, 0);
      },
    );

    testWidgets('exposes vitality-trend-chart Semantics identifier', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          trendByBodyPart: _allRamps(start: windowStart, days: 91),
          selected: BodyPart.chest,
          windowStart: windowStart,
          windowEnd: today,
          useNarrowWindow: false,
        ),
      );
      await tester.pump();

      // E2E selectors locate this widget via its Semantics identifier; we
      // assert the widget tree carries one Semantics node with the
      // contracted identifier so the E2E layer (Playwright) can latch onto
      // it via flt-semantics-identifier.
      final semantics = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(VitalityTrendChart),
              matching: find.byType(Semantics),
            ),
          )
          .where((s) => s.properties.identifier == 'vitality-trend-chart')
          .toList();
      expect(semantics.length, 1);
    });

    group('Ghost line identity color + 180ms tween (Task 7)', () {
      testWidgets(
        'should color the back ghost line in bodyPartColor[back] at <1.0 alpha',
        (tester) async {
          await tester.pumpWidget(
            _wrap(
              trendByBodyPart: _allRamps(start: windowStart, days: 91),
              selected: BodyPart.chest,
              windowStart: windowStart,
              windowEnd: today,
              useNarrowWindow: false,
            ),
          );
          await tester.pump();

          final chart = tester.widget<LineChart>(find.byType(LineChart));
          final backRgb = VitalityStateStyles.bodyPartColor[BodyPart.back]!;
          final backBars = chart.data.lineBarsData.where((b) {
            final c = b.color;
            if (c == null) return false;
            return (c.r * 255).round() == (backRgb.r * 255).round() &&
                (c.g * 255).round() == (backRgb.g * 255).round() &&
                (c.b * 255).round() == (backRgb.b * 255).round();
          }).toList();
          expect(backBars, hasLength(1));
          expect(backBars.single.color!.a, lessThan(1.0));
          expect(backBars.single.barWidth, 1.0);
        },
      );

      testWidgets(
        'should color the legs ghost line in bodyPartColor[legs] at <1.0 alpha',
        (tester) async {
          await tester.pumpWidget(
            _wrap(
              trendByBodyPart: _allRamps(start: windowStart, days: 91),
              selected: BodyPart.chest,
              windowStart: windowStart,
              windowEnd: today,
              useNarrowWindow: false,
            ),
          );
          await tester.pump();

          final chart = tester.widget<LineChart>(find.byType(LineChart));
          final legsRgb = VitalityStateStyles.bodyPartColor[BodyPart.legs]!;
          final legsBars = chart.data.lineBarsData.where((b) {
            final c = b.color;
            if (c == null) return false;
            return (c.r * 255).round() == (legsRgb.r * 255).round() &&
                (c.g * 255).round() == (legsRgb.g * 255).round() &&
                (c.b * 255).round() == (legsRgb.b * 255).round();
          }).toList();
          expect(legsBars, hasLength(1));
          expect(legsBars.single.color!.a, lessThan(1.0));
          expect(legsBars.single.barWidth, 1.0);
        },
      );

      testWidgets('should run the cross-fade tween at 180ms', (tester) async {
        await tester.pumpWidget(
          _wrap(
            trendByBodyPart: _allRamps(start: windowStart, days: 91),
            selected: BodyPart.chest,
            windowStart: windowStart,
            windowEnd: today,
            useNarrowWindow: false,
          ),
        );
        await tester.pump();

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        expect(chart.duration, const Duration(milliseconds: 180));
      });
    });
  });
}
