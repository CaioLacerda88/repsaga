import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_discreet.dart';

/// Pins the Discreet variant — the no-photo cinematic still that auto-
/// selects on camera-denied + "Sem foto" paths.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 270, height: 480, child: child)),
    );
  }

  testWidgets('renders eyebrow + hero + sub-label + wordmark verbatim', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardDiscreet(
          dominantHue: AppColors.bodyPartChest,
          eyebrow: 'Peito · Rank 19',
          heroText: '+618',
          heroSubLabel: 'XP NESTA SAGA',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    expect(find.text('Peito · Rank 19'), findsOneWidget);
    expect(find.text('+618'), findsOneWidget);
    expect(find.text('XP NESTA SAGA'), findsOneWidget);
    expect(find.text('REPSAGA'), findsOneWidget);
  });

  testWidgets('renders the optional PR line + detail when both supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardDiscreet(
          dominantHue: AppColors.bodyPartChest,
          eyebrow: 'Peito · Rank 19',
          heroText: '+618',
          heroSubLabel: 'XP NESTA SAGA',
          prLine: '!! 95kg × 5',
          prDetail: 'Supino · novo recorde',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    expect(find.text('!! 95kg × 5'), findsOneWidget);
    expect(find.text('Supino · novo recorde'), findsOneWidget);
  });

  testWidgets(
    'omits the PR line + detail entirely when both are null (rank-up only)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardDiscreet(
            dominantHue: AppColors.bodyPartBack,
            eyebrow: 'Costas · Rank 18',
            heroText: '+420',
            heroSubLabel: 'XP NESTA SAGA',
            wordmark: 'REPSAGA',
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('share-card-discreet-pr-line')),
        findsNothing,
      );
      expect(find.textContaining('Supino'), findsNothing);
    },
  );

  testWidgets(
    'eyebrow color tracks the dominant hue (class-change override path)',
    (tester) async {
      // Caller passes hotViolet when isClassChange is true (mockup §6).
      await tester.pumpWidget(
        host(
          const ShareCardDiscreet(
            dominantHue: AppColors.hotViolet,
            eyebrow: 'BULWARK DESPERTOU.',
            heroText: '+420',
            heroSubLabel: 'XP NESTA SAGA',
            wordmark: 'REPSAGA',
          ),
        ),
      );

      final eyebrow = tester.widget<Text>(
        find.byKey(const ValueKey('share-card-discreet-eyebrow')),
      );
      expect(eyebrow.style!.color, AppColors.hotViolet);
    },
  );

  testWidgets('hero text uses Rajdhani-family numeric token at 44sp', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardDiscreet(
          dominantHue: AppColors.bodyPartChest,
          eyebrow: 'Peito · Rank 19',
          heroText: '+618',
          heroSubLabel: 'XP NESTA SAGA',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final hero = tester.widget<Text>(
      find.byKey(const ValueKey('share-card-discreet-hero')),
    );
    // We route through AppTextStyles.numeric (Rajdhani 700 tabular) and
    // assert the size override only — fontFamily is owned by AppTheme.
    expect(hero.style!.fontSize, 44);
    expect(hero.style!.fontFamily, 'Rajdhani');
    expect(hero.style!.fontWeight, FontWeight.w700);
  });
}
