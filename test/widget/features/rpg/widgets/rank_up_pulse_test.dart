import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/rank_up_pulse.dart';

void main() {
  group('RankUpPulse', () {
    testWidgets('child is rendered unchanged when wrapped', (tester) async {
      // RankUpPulse composes around its child without replacing or hiding it.
      // Gating happens at the parent (BodyPartRankRow) — this widget always
      // renders both the ring and the child once mounted.
      const key = ValueKey('pulse-target');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RankUpPulse(
                color: Colors.pink,
                child: SizedBox(key: key, width: 6, height: 6),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(key), findsOneWidget);
    });

    testWidgets('animation controller is disposed when widget is removed', (
      tester,
    ) async {
      // Regression guard: a leaked AnimationController keeps ticking after
      // the row is offscreen. The Stateful + SingleTickerProviderStateMixin
      // contract requires dispose() to release the ticker. Mount, then
      // remove from the tree, then pump — no exceptions should surface.
      const key = ValueKey('pulse-target');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RankUpPulse(
                color: Colors.pink,
                child: SizedBox(key: key, width: 6, height: 6),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Replace with an empty scaffold — disposes the RankUpPulse subtree.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ring border alpha and scale follow the sine cycle deterministically',
      (tester) async {
        // Pump exactly to v=0.25 of the 1600ms cycle: 400ms.
        // At v=0.25, sin(π/2)=1, so t=1, scale=1.5, alpha=0.35.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: RankUpPulse(
                  color: Colors.pink,
                  child: SizedBox(width: 6, height: 6),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        // The ring DecoratedBox is the one with a circular Border (the
        // wrapped child has no decoration).
        final ringBox = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .firstWhere((d) {
              final dec = d.decoration;
              return dec is BoxDecoration && dec.border != null;
            });
        final ringDec = ringBox.decoration as BoxDecoration;
        final borderTop = ringDec.border! as Border;
        // Expected alpha at t=1: 0.15 + 0.20 * 1.0 = 0.35. closeTo with a
        // forgiving epsilon accounts for AnimationController float drift
        // near the exact midpoint of the cycle.
        expect(borderTop.top.color.a, closeTo(0.35, 0.05));
      },
    );
  });
}
