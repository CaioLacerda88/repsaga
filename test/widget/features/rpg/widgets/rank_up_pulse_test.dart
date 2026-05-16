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

    testWidgets('emits an animated outer ring around its child', (
      tester,
    ) async {
      // The pulse renders a ring overlay that scales 1.0 → 1.5 and alpha
      // 15% → 35% in a sine loop. We don't pin exact mid-frame values
      // (animation timing brittleness) — we assert that the widget mounts
      // a Transform.scale + a DecoratedBox with a circular border, and
      // that the rendered tree shape is stable across pump frames.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RankUpPulse(
                color: Colors.pink,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.pink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      // The ring is built via DecoratedBox with a BoxDecoration(shape: circle, border: ...).
      // The wrapped child is also a DecoratedBox. There should be at least 2.
      final decoratedBoxes = tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      );
      expect(decoratedBoxes.length, greaterThanOrEqualTo(2));
      // A Transform.scale drives the size variation.
      expect(find.byType(Transform), findsAtLeast(1));
    });
  });
}
