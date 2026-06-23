/// Widget tests pinning the user-visible contract on [B2CascadeCutWidget].
///
/// The single test below pins **Bug G** (commit 9da2ed2 — cluster
/// `spec-caption-vs-implementation-drift`): mockup §3 Variant C specified
/// that each cascade row renders with a colored left-bar in the row's
/// body-part hue plus an abyss panel background. The original
/// implementation rendered bare text rows; on-device verification flagged
/// the gap and the fix wrapped each row in a chrome [Container].
///
/// Without this assertion, a future refactor that drops the chrome
/// `Container` (e.g. revert to a bare `Row` to "simplify") wouldn't
/// fail any test in `flutter test` — it would only surface on the next
/// on-device visual gate. This pins what the user sees so the contract
/// survives implementation churn.
///
/// **Behavior-not-wiring per CLAUDE.md.** We assert on the rendered
/// decoration ([Container] with the spec'd [Border.left] + background
/// alpha), not on the widget construction. A future implementation that
/// produces the same decoration via a different widget tree shape (e.g.
/// `DecoratedBox`) would still satisfy the visual contract — and this
/// test would need updating in lockstep with the visual change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/utils/vitality_state_styles.dart';
import 'package:repsaga/features/workouts/domain/post_session_choreographer.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/b2_cascade_cut.dart';
import 'package:repsaga/features/workouts/ui/post_session/cuts/charge_rune.dart';

int _litSegments(WidgetTester tester) {
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((d) {
    final deco = d.decoration as BoxDecoration;
    return deco.boxShadow != null && deco.boxShadow!.isNotEmpty;
  }).length;
}

void main() {
  testWidgets(
    'cascade rows render with body-part-hued left bar + abyss panel BG '
    '(Bug G — cluster spec-caption-vs-implementation-drift)',
    (tester) async {
      const cut = B2CascadeCut(
        heroBodyPart: BodyPart.shoulders,
        heroXp: 320,
        heroProgressFractionAfter: 0.6,
        cascadeRows: [
          CascadeRow(bodyPart: BodyPart.chest, xpEarned: 220),
          CascadeRow(bodyPart: BodyPart.back, xpEarned: 150),
        ],
        truncatedCount: 0,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: B2CascadeCutWidget(
              animation: AlwaysStoppedAnimation(1.0),
              cut: cut,
              bodyPartLabels: {
                BodyPart.shoulders: 'OMBROS',
                BodyPart.chest: 'PEITO',
                BodyPart.back: 'COSTAS',
              },
              xpLabel: 'XP',
              truncatedPillLabel: '',
            ),
          ),
        ),
      );

      // Find every Container whose decoration carries a 2dp left border —
      // that's the cascade-row chrome shape per Bug G's fix. Any
      // implementation that drops the chrome (bare Row, no Border) makes
      // this finder return zero hits.
      final rowChromeFinder = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final deco = w.decoration;
        if (deco is! BoxDecoration) return false;
        final border = deco.border;
        if (border is! Border) return false;
        return border.left.width == 2.0;
      });

      expect(
        rowChromeFinder,
        findsNWidgets(2),
        reason:
            'Each cascade row must render the chrome Container '
            '(colored left-bar + panel BG) — Bug G fix.',
      );

      final containers = rowChromeFinder
          .evaluate()
          .map((e) => e.widget as Container)
          .toList();

      // First row → chest hue on the left border.
      final firstDeco = containers[0].decoration as BoxDecoration;
      expect(
        (firstDeco.border! as Border).left.color,
        VitalityStateStyles.bodyPartColor[BodyPart.chest],
        reason: 'First cascade row left-bar must use the chest body-part hue.',
      );

      // Second row → back hue on the left border.
      final secondDeco = containers[1].decoration as BoxDecoration;
      expect(
        (secondDeco.border! as Border).left.color,
        VitalityStateStyles.bodyPartColor[BodyPart.back],
        reason: 'Second cascade row left-bar must use the back body-part hue.',
      );

      // Both rows share the abyss panel BG at 55% alpha.
      final expectedBg = AppColors.abyss.withValues(alpha: 0.55);
      for (final container in containers) {
        final deco = container.decoration as BoxDecoration;
        expect(
          deco.color,
          expectedBg,
          reason: 'Cascade row chrome must use abyss @ 55% alpha as panel BG.',
        );
      }
    },
  );

  testWidgets('cascade renders the charge rune end-cap on the HERO ONLY '
      '(Phase Vitality-2 S4)', (tester) async {
    const cut = B2CascadeCut(
      heroBodyPart: BodyPart.core,
      heroXp: 480,
      heroProgressFractionAfter: 0.04,
      heroChargeFractionAfter: 0.55, // round(0.55*4) = 2 lit
      heroChargeIsMax: false,
      heroChargeDeltaPercent: 24,
      cascadeRows: [
        CascadeRow(bodyPart: BodyPart.back, xpEarned: 220),
        CascadeRow(bodyPart: BodyPart.arms, xpEarned: 150),
      ],
      truncatedCount: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: B2CascadeCutWidget(
            animation: AlwaysStoppedAnimation(1.0),
            cut: cut,
            bodyPartLabels: {
              BodyPart.core: 'CORE',
              BodyPart.back: 'COSTAS',
              BodyPart.arms: 'BRAÇOS',
            },
            xpLabel: 'XP',
            truncatedPillLabel: '',
            chargeDeltaLabel: _delta,
            chargeMaxLabel: 'MÁX',
            chargeRechargedLabel: 'Condicionamento recarregado',
            chargeAtPeakLabel: 'Condicionamento no pico',
          ),
        ),
      ),
    );

    // Exactly ONE rune end-cap (the hero) — secondary cascade rows stay
    // rank-only (mockup cinematic caption iii).
    expect(find.byType(B2ChargeEndCap), findsOneWidget);
    expect(find.text('+24%'), findsOneWidget);
    expect(find.text('CONDICIONAMENTO RECARREGADO'), findsOneWidget);
    // Hero 55% → 2 of 4 lit; no secondary-row runes contribute.
    expect(_litSegments(tester), 2);
  });

  testWidgets('cascade with no hero charge data renders no rune end-cap', (
    tester,
  ) async {
    const cut = B2CascadeCut(
      heroBodyPart: BodyPart.shoulders,
      heroXp: 320,
      heroProgressFractionAfter: 0.6,
      cascadeRows: [CascadeRow(bodyPart: BodyPart.chest, xpEarned: 220)],
      truncatedCount: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: B2CascadeCutWidget(
            animation: AlwaysStoppedAnimation(1.0),
            cut: cut,
            bodyPartLabels: {
              BodyPart.shoulders: 'OMBROS',
              BodyPart.chest: 'PEITO',
            },
            xpLabel: 'XP',
            truncatedPillLabel: '',
            // No charge copy → end-cap stays off (additive fuse).
          ),
        ),
      ),
    );

    expect(find.byType(B2ChargeEndCap), findsNothing);
    expect(_litSegments(tester), 0);
  });
}

String _delta(int pct) => '+$pct%';
