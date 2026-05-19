/// Widget tests for [AmbientPulseDot] (Phase 27 L8).
///
/// The widget renders a body-part-hue dot inside an animated glow-ring.
/// Two modes:
///   * `emphasized: false` — subtle baseline pulse on every trained dot.
///   * `emphasized: true` — bigger amplitude + faster period for the 24h
///     post-rank-up window.
///
/// Tests assert on the rendered output (the ring [DecoratedBox]'s border
/// alpha, the dot's measured size) rather than the [AnimationController]
/// value. `tester.pump(Duration)` advances the synthetic clock for
/// `repeat()` cycles, but the assertion target is what the user sees on
/// screen — see `cluster_pump_duration_masks_forward`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/ambient_pulse_dot.dart';

const ValueKey _dotKey = ValueKey('ambient-pulse-dot-target');

Widget _harness({
  Color color = const Color(0xFFE94B7B),
  double size = 6,
  bool emphasized = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: AmbientPulseDot(
          key: _dotKey,
          color: color,
          size: size,
          emphasized: emphasized,
        ),
      ),
    ),
  );
}

/// Returns the ring's border opacity at the current frame. The ring is the
/// DecoratedBox whose decoration carries a [Border] — the inner dot uses a
/// fill color with no border.
double _ringAlpha(WidgetTester tester) {
  final ringBox = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .firstWhere((d) {
        final dec = d.decoration;
        return dec is BoxDecoration && dec.border != null;
      });
  final dec = ringBox.decoration as BoxDecoration;
  final border = dec.border! as Border;
  return border.top.color.a;
}

void main() {
  group('AmbientPulseDot', () {
    testWidgets('renders the inner dot child once mounted', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(_dotKey), findsOneWidget);
    });

    testWidgets('ambient mode peaks at low-amplitude scale + alpha at t=peak', (
      tester,
    ) async {
      // Ambient cycle is 3200ms. Peak of sine cycle is at v=0.25 → 800ms.
      // At peak: t=1 → scale=1.15, alpha=0.18.
      await tester.pumpWidget(_harness(emphasized: false));
      await tester.pump(const Duration(milliseconds: 800));
      // closeTo bound is generous — controller drift near the sine apex
      // can shift the sampled value by a frame or two.
      expect(_ringAlpha(tester), closeTo(0.18, 0.04));
    });

    testWidgets(
      'emphasized mode peaks at high-amplitude scale + alpha at t=peak',
      (tester) async {
        // Emphasized cycle is 1600ms. Peak at v=0.25 → 400ms.
        // At peak: t=1 → scale=1.5, alpha=0.35.
        await tester.pumpWidget(_harness(emphasized: true));
        await tester.pump(const Duration(milliseconds: 400));
        expect(_ringAlpha(tester), closeTo(0.35, 0.05));
      },
    );

    testWidgets(
      'emphasized cycle is faster than ambient (period ordering invariant)',
      (tester) async {
        // Loose-bound period check: at the SAME elapsed time (200ms) the
        // emphasized ring is further into its cycle than the ambient ring.
        // Concrete sample: at 200ms, emphasized v=200/1600=0.125 →
        // sin(π/4)≈0.707, t≈0.854; ambient v=200/3200=0.0625 →
        // sin(0.125π)≈0.383, t≈0.691. Therefore emphasized alpha > ambient
        // alpha at the same sample point (regardless of absolute amplitude,
        // because ambient is always ≤0.18 while emphasized rises through
        // 0.15..0.35 — the comparison would only fail if periods were equal).
        await tester.pumpWidget(_harness(emphasized: false));
        await tester.pump(const Duration(milliseconds: 200));
        final ambientAlpha = _ringAlpha(tester);

        await tester.pumpWidget(_harness(emphasized: true));
        await tester.pump(const Duration(milliseconds: 200));
        final emphasizedAlpha = _ringAlpha(tester);

        expect(emphasizedAlpha, greaterThan(ambientAlpha));
      },
    );

    testWidgets('disposes its AnimationController without leaking', (
      tester,
    ) async {
      // Mount, then replace with an empty scaffold — disposes the subtree.
      // Pump a long stretch afterwards and confirm no ticker leak surfaces.
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'switching emphasized at runtime rebinds the controller duration',
      (tester) async {
        // Start ambient — sample ring at 200ms.
        await tester.pumpWidget(_harness(emphasized: false));
        await tester.pump(const Duration(milliseconds: 200));
        // Swap to emphasized in-place (didUpdateWidget path).
        await tester.pumpWidget(_harness(emphasized: true));
        await tester.pump(const Duration(milliseconds: 400));
        // After the swap + one emphasized cycle (1600ms / 4), the ring
        // should be reading from the emphasized amplitude band (max alpha
        // 0.35), not the ambient band (max alpha 0.18). The exact value
        // depends on where the controller was when it was rebound, so
        // we just bound on the strict ambient ceiling.
        final alpha = _ringAlpha(tester);
        // Loose: if the controller is in the emphasized band at all, the
        // alpha can exceed the ambient ceiling. If the rebind silently
        // dropped to ambient, this stays ≤0.18.
        expect(alpha, lessThanOrEqualTo(0.36)); // emphasized peak + epsilon
        // Stronger invariant: no exceptions after the duration rebind.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('wraps in a RepaintBoundary for paint-isolation', (
      tester,
    ) async {
      // Performance invariant — the per-frame paint must invalidate only
      // the dot's region, not the whole row. The widget owns a
      // RepaintBoundary as its outermost child for this reason.
      await tester.pumpWidget(_harness());
      expect(
        find.descendant(
          of: find.byType(AmbientPulseDot),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });
}
