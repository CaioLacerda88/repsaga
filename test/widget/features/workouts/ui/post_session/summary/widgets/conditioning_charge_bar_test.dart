import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/summary/widgets/conditioning_charge_bar.dart';

/// Fixed outer width so segment widths are deterministic. The bar fills its
/// parent, so a 200px-wide host means `was`-width == 200 * beforeFraction.
const double _hostWidth = 200.0;

Future<void> _pumpBar(
  WidgetTester tester, {
  required double before,
  required double after,
  bool animate = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _hostWidth,
            child: ConditioningChargeBar(
              beforeFraction: before,
              afterFraction: after,
              eyebrowLabel: 'Conditioning charged',
              deltaLabel: '+14%',
              captionLabel: 'The rune recharges over ~7 days.',
              animate: animate,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The two `Positioned` fill segments inside the bar, in paint order:
/// [0] = dim `was`, [1] = solid `now`. Filters out the `Positioned.fill`
/// track (which has all insets non-null).
List<Positioned> _segments(WidgetTester tester) {
  return tester
      .widgetList<Positioned>(find.byType(Positioned))
      .where((p) => p.left != null && p.width != null)
      .toList();
}

void main() {
  group('ConditioningChargeBar', () {
    testWidgets('renders the delta label and the eyebrow', (tester) async {
      await _pumpBar(tester, before: 0.58, after: 0.72, animate: false);
      expect(find.text('+14%'), findsOneWidget);
      expect(find.textContaining('CONDITIONING CHARGED'), findsOneWidget);
      expect(find.text('The rune recharges over ~7 days.'), findsOneWidget);
    });

    testWidgets('renders a two-tone fill — dim was + solid now', (
      tester,
    ) async {
      await _pumpBar(tester, before: 0.58, after: 0.72, animate: false);
      await tester.pumpAndSettle();

      final segs = _segments(tester);
      expect(segs.length, 2, reason: 'one dim was + one solid now segment');

      // Segment colors via their ColoredBox children.
      final wasBox = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byWidget(segs[0]),
          matching: find.byType(ColoredBox),
        ),
      );
      final nowBox = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byWidget(segs[1]),
          matching: find.byType(ColoredBox),
        ),
      );
      // `was` is dim teal (alpha 0.28), `now` is solid teal — distinct.
      expect(nowBox.color, AppColors.bodyPartCardio);
      expect(wasBox.color, isNot(AppColors.bodyPartCardio));
      expect(wasBox.color.a, closeTo(0.28, 0.01));
    });

    testWidgets(
      'count-up reaches the correct final now width (rendered geometry)',
      (tester) async {
        // Assert the RENDERED output at the END of the animation, not the
        // controller value (cluster: pump-duration-masks-forward).
        await _pumpBar(tester, before: 0.40, after: 0.70, animate: true);
        // Mid-flight: pump a small slice — the now sliver has not yet
        // reached its final width.
        await tester.pump(const Duration(milliseconds: 100));
        final midSegs = _segments(tester);
        final midNowRight = midSegs[1].left! + midSegs[1].width!;

        // Settle to the end of the count-up.
        await tester.pumpAndSettle();
        final endSegs = _segments(tester);

        // was segment: 0 → 0.40 * 200 = 80px.
        expect(endSegs[0].left, 0);
        expect(endSegs[0].width, closeTo(0.40 * _hostWidth, 0.5));

        // now segment starts at the was tick (80px) and extends to
        // 0.70 * 200 = 140px → width 60px.
        expect(endSegs[1].left, closeTo(0.40 * _hostWidth, 0.5));
        expect(endSegs[1].width, closeTo((0.70 - 0.40) * _hostWidth, 0.5));

        // The fill only ever grew rightward: the final now-right edge
        // exceeds the mid-flight one.
        final endNowRight = endSegs[1].left! + endSegs[1].width!;
        expect(endNowRight, greaterThan(midNowRight));
        expect(endNowRight, closeTo(0.70 * _hostWidth, 0.5));
      },
    );

    testWidgets('now never recedes below was (rebuild-only)', (tester) async {
      // Defensive: an after < before must not render a now segment that
      // shrinks left of the was tick — the bar can only grow rightward.
      await _pumpBar(tester, before: 0.60, after: 0.50, animate: false);
      await tester.pumpAndSettle();
      final segs = _segments(tester);
      // now sliver collapses to zero width (clamped at the was tick), never
      // negative.
      expect(segs[1].width, greaterThanOrEqualTo(0));
      expect(segs[1].left, closeTo(0.60 * _hostWidth, 0.5));
    });
  });
}
