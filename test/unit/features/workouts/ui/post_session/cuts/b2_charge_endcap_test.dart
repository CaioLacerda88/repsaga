/// Widget tests pinning the cinematic conditioning charge rune end-cap fused
/// onto the B2 hero beat (Phase Vitality-2 S4).
///
/// **Behavior-not-wiring.** We assert RENDERED output at the final animation
/// state (`AlwaysStoppedAnimation(1.0)`) — the lit rune segments (counted by
/// their hue glow), the `+N%` / MÁX trailing word, and the descriptive
/// subtitle. Avoids `pump(Duration)` masking a missing `forward()` (cluster:
/// pump-duration-masks-forward): the animation is pinned at 1.0 so the
/// rune-fill window (0.30→0.70) is fully past and every target segment is lit.
///
/// The three pinned states mirror the locked mockup
/// (`docs/phase-vitality2-mockups.html` cinematic frames i / ii / iii):
///   i  gainer        → rune lit to fraction + "▲ +N%" + recharged subtitle.
///   ii MÁX (held)    → full rune + "MÁX" + at-peak subtitle, never "+0".
///   -  no charge data → no rune end-cap, no charge line (unchanged beat).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/b2_bp_tally_cut.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/b2_elevated_cut.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/charge_rune.dart';

/// Count lit rune segments by their DecoratedBox boxShadow (lit segments carry
/// a hue glow, unlit ones don't). Same probe the summary-strip test uses.
int _litSegments(WidgetTester tester) {
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((d) {
    final deco = d.decoration as BoxDecoration;
    return deco.boxShadow != null && deco.boxShadow!.isNotEmpty;
  }).length;
}

void main() {
  group('B2BpTallyCut — charge rune end-cap', () {
    testWidgets('gainer hero renders rune lit to fraction + "+N%" line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2BpTallyCut(
              animation: const AlwaysStoppedAnimation(1.0),
              bodyPart: BodyPart.back,
              bodyPartLabel: 'Costas',
              xpEarned: 340,
              xpLabel: 'XP',
              progressFractionAfter: 0.64,
              rankAfter: 9,
              isFirstAwakening: false,
              // Back charged to 64% this session, +17 points.
              chargeFractionAfter: 0.64,
              isChargeMax: false,
              chargeDeltaPercent: 17,
              chargeDeltaLabel: (pct) => '+$pct%',
              chargeMaxLabel: 'MÁX',
              chargeRechargedLabel: 'Condicionamento recarregado',
              chargeAtPeakLabel: 'Condicionamento no pico',
            ),
          ),
        ),
      );

      // The +17% delta line is present.
      expect(find.text('+17%'), findsOneWidget);
      // The past-tense descriptive subtitle (uppercased by the widget).
      expect(find.text('CONDICIONAMENTO RECARREGADO'), findsOneWidget);
      // No MÁX word on a gainer.
      expect(find.text('MÁX'), findsNothing);
      // 64% → round(0.64*4) = 3 of 4 segments lit, asserted at the t=1 state.
      expect(_litSegments(tester), 3);
    });

    testWidgets('MÁX hero shows full rune + MÁX, no "+0" + at-peak subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2BpTallyCut(
              animation: const AlwaysStoppedAnimation(1.0),
              bodyPart: BodyPart.legs,
              bodyPartLabel: 'Pernas',
              xpEarned: 210,
              xpLabel: 'XP',
              progressFractionAfter: 0.88,
              rankAfter: 14,
              isFirstAwakening: false,
              chargeFractionAfter: 1.0,
              isChargeMax: true,
              chargeDeltaPercent: 0,
              chargeDeltaLabel: (pct) => '+$pct%',
              chargeMaxLabel: 'MÁX',
              chargeRechargedLabel: 'Condicionamento recarregado',
              chargeAtPeakLabel: 'Condicionamento no pico',
            ),
          ),
        ),
      );

      expect(find.text('MÁX'), findsOneWidget);
      // Never a dead +0 on a maxed part.
      expect(find.text('+0%'), findsNothing);
      // At-peak descriptive subtitle (uppercased).
      expect(find.text('CONDICIONAMENTO NO PICO'), findsOneWidget);
      // Held full — all 4 segments lit (pre-lit, no climb).
      expect(_litSegments(tester), 4);
    });

    testWidgets('no charge data → no rune end-cap, no charge line '
        '(unchanged beat)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: B2BpTallyCut(
              animation: AlwaysStoppedAnimation(1.0),
              bodyPart: BodyPart.chest,
              bodyPartLabel: 'Peito',
              xpEarned: 118,
              xpLabel: 'XP',
              progressFractionAfter: 0.12,
              rankAfter: 1,
              isFirstAwakening: true,
              firstAwakeningSuffix: ' · Desperto',
              // No charge props → additive fuse stays off.
            ),
          ),
        ),
      );

      // The original beat still renders (eyebrow + awakening suffix).
      expect(find.text('PEITO · DESPERTO'), findsOneWidget);
      // No rune end-cap → no lit charge segments at all.
      expect(_litSegments(tester), 0);
      // No charge line / MÁX word.
      expect(find.text('MÁX'), findsNothing);
      expect(find.byType(B2ChargeEndCap), findsNothing);
    });
  });

  group('B2ElevatedCut — charge rune end-cap', () {
    testWidgets('gainer rank-up shows completed rune + "+N%" at the slam', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: B2ElevatedCut(
              animation: const AlwaysStoppedAnimation(1.0),
              bodyPart: BodyPart.core,
              bodyPartLabel: 'Core',
              newRank: 12,
              rankCopy: 'CORE · RANK 12',
              chargeFractionAfter: 0.55, // round(0.55*4) = 2 lit
              isChargeMax: false,
              chargeDeltaPercent: 24,
              chargeDeltaLabel: (pct) => '+$pct%',
              chargeMaxLabel: 'MÁX',
              chargeRechargedLabel: 'Condicionamento recarregado',
              chargeAtPeakLabel: 'Condicionamento no pico',
            ),
          ),
        ),
      );

      expect(find.text('+24%'), findsOneWidget);
      expect(find.text('CONDICIONAMENTO RECARREGADO'), findsOneWidget);
      // 0.55 → 2 of 4 lit; rune is held-full-relative (bar already crossed
      // 100% in phase A, fill = 1.0 → every target segment lit).
      expect(_litSegments(tester), 2);
    });

    testWidgets('no charge data → no rune end-cap on the elevated beat', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: B2ElevatedCut(
              animation: AlwaysStoppedAnimation(1.0),
              bodyPart: BodyPart.chest,
              bodyPartLabel: 'Peito',
              newRank: 19,
              rankCopy: 'PEITO · RANK 19',
            ),
          ),
        ),
      );

      expect(find.byType(B2ChargeEndCap), findsNothing);
      expect(_litSegments(tester), 0);
      // The rank slam still renders — beat unchanged.
      expect(find.text('19'), findsOneWidget);
    });
  });

  testWidgets('end-cap rune uses the body-part identity hue', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: B2BpTallyCut(
            animation: const AlwaysStoppedAnimation(1.0),
            bodyPart: BodyPart.back,
            bodyPartLabel: 'Costas',
            xpEarned: 340,
            xpLabel: 'XP',
            progressFractionAfter: 0.64,
            rankAfter: 9,
            isFirstAwakening: false,
            chargeFractionAfter: 1.0,
            isChargeMax: true,
            chargeDeltaPercent: 0,
            chargeDeltaLabel: (pct) => '+$pct%',
            chargeMaxLabel: 'MÁX',
            chargeRechargedLabel: 'Condicionamento recarregado',
            chargeAtPeakLabel: 'Condicionamento no pico',
          ),
        ),
      ),
    );

    final backHue = VitalityStateStyles.bodyPartColor[BodyPart.back];
    // Every lit segment paints in the back identity hue.
    final litColors = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration as BoxDecoration)
        .where((deco) => deco.boxShadow != null && deco.boxShadow!.isNotEmpty)
        .map((deco) => deco.color)
        .toSet();
    expect(litColors, {backHue});
  });
}
