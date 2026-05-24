import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_variant_b.dart';

/// Pins Variant B (Full-Bleed Collars) overlay rendering — collar geometry
/// (`ClipPath`), PR-tag conditionality, and content text.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 270, height: 480, child: child)),
    );
  }

  testWidgets(
    'renders top eyebrow + class + wordmark and bottom lift + bp/xp sub lines',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardVariantB(
            dominantHue: AppColors.bodyPartChest,
            bpEyebrow: 'Peito',
            className: 'BULWARK',
            wordmark: 'REPSAGA',
            prTag: '!! Recorde',
            lift: '95kg × 5',
            bpSub: 'Supino · Peito',
            xpSub: '+618 XP',
          ),
        ),
      );

      expect(find.text('Peito'), findsOneWidget);
      expect(find.text('BULWARK'), findsOneWidget);
      expect(find.text('REPSAGA'), findsOneWidget);
      expect(find.text('!! Recorde'), findsOneWidget);
      expect(find.text('95kg × 5'), findsOneWidget);
      expect(find.text('Supino · Peito'), findsOneWidget);
      expect(find.text('+618 XP'), findsOneWidget);
    },
  );

  testWidgets('omits the PR tag entirely when prTag is null', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantB(
          dominantHue: AppColors.bodyPartBack,
          bpEyebrow: 'Costas',
          className: 'BERSERKER',
          wordmark: 'REPSAGA',
          lift: 'Rank 18 · Costas',
          bpSub: 'Remada · Costas',
          xpSub: '+420 XP',
        ),
      ),
    );

    expect(find.text('!! Recorde'), findsNothing);
    // Non-PR session leads with rank info on the lift line.
    expect(find.text('Rank 18 · Costas'), findsOneWidget);
  });

  testWidgets('top collar uses a ClipPath (diagonal cut grammar)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantB(
          dominantHue: AppColors.bodyPartChest,
          bpEyebrow: 'Peito',
          className: 'BULWARK',
          wordmark: 'REPSAGA',
          lift: '95kg × 5',
          bpSub: 'Supino · Peito',
          xpSub: '+618 XP',
        ),
      ),
    );

    final topCollar = find.ancestor(
      of: find.byKey(const ValueKey('share-card-variant-b-top-collar')),
      matching: find.byType(ClipPath),
    );
    expect(topCollar, findsOneWidget);
  });

  testWidgets('bottom collar uses a ClipPath (diagonal cut grammar)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantB(
          dominantHue: AppColors.bodyPartChest,
          bpEyebrow: 'Peito',
          className: 'BULWARK',
          wordmark: 'REPSAGA',
          lift: '95kg × 5',
          bpSub: 'Supino · Peito',
          xpSub: '+618 XP',
        ),
      ),
    );

    final bottomCollar = find.ancestor(
      of: find.byKey(const ValueKey('share-card-variant-b-bottom-collar')),
      matching: find.byType(ClipPath),
    );
    expect(bottomCollar, findsOneWidget);
  });

  testWidgets(
    'top collar background is flat abyss at ~95% opacity (mockup §6 lock)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardVariantB(
            dominantHue: AppColors.bodyPartChest,
            bpEyebrow: 'Peito',
            className: 'BULWARK',
            wordmark: 'REPSAGA',
            lift: '95kg × 5',
            bpSub: 'Supino · Peito',
            xpSub: '+618 XP',
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('share-card-variant-b-top-collar')),
      );
      final color = container.color!;
      expect(color.red, AppColors.abyss.red);
      expect(color.green, AppColors.abyss.green);
      expect(color.blue, AppColors.abyss.blue);
      expect((color.alpha / 255 - 0.95).abs() < 0.01, isTrue);
    },
  );
}
