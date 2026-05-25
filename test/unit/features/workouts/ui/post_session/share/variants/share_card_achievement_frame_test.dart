import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/share_card_typography.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_achievement_frame.dart';

/// Pins the D3 Achievement Frame overlay (Phase 31) — the single photo-
/// overlay variant. Tests render the widget on a 9:16 host and assert
/// observable behavior at the rendered-output level (text + chrome colors
/// + structure), not wiring traces.
///
/// **Behavior, not wiring.** Each test asserts a rendered Text / ColoredBox
/// / Container property the user actually sees. The collar + side-bar
/// `ValueKey`s exist so chrome contracts can be probed at the boundary
/// without painter mocking.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: AppColors.abyss,
        body: SizedBox(
          // 9:16 share card aspect at a stable size.
          width: 270,
          height: 480,
          child: child,
        ),
      ),
    );
  }

  testWidgets('renders both collars + both side bars + center content', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.bodyPartChest,
          className: 'BULWARK',
          sagaEyebrow: 'SAGA 76',
          xpHero: '+618 XP',
          liftDetail: '95kg × 5 · Supino',
          hasPr: true,
          bpRank: 'Peito · Rank 19',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    // Both collars present at their ValueKey boundary.
    expect(
      find.byKey(const ValueKey('share-card-achievement-frame-top-collar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('share-card-achievement-frame-bottom-collar')),
      findsOneWidget,
    );
    // Both side bars present.
    expect(
      find.byKey(const ValueKey('share-card-achievement-frame-left-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('share-card-achievement-frame-right-bar')),
      findsOneWidget,
    );

    // Content rendered verbatim (no l10n lookup inside the widget).
    expect(find.text('BULWARK'), findsOneWidget);
    expect(find.text('SAGA 76'), findsOneWidget);
    expect(find.text('+618 XP'), findsOneWidget);
    expect(find.text('95kg × 5 · Supino'), findsOneWidget);
    expect(find.text('Peito · Rank 19'), findsOneWidget);
    expect(find.text('REPSAGA'), findsOneWidget);
  });

  testWidgets('left side bar color tracks the dominant body-part hue on non '
      'class-change sessions', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.bodyPartBack,
          className: 'BERSERKER',
          xpHero: '+618 XP',
          bpRank: 'Costas · Rank 19',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final leftBar = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('share-card-achievement-frame-left-bar')),
    );
    expect(leftBar.color, AppColors.bodyPartBack);
  });

  testWidgets('right side bar is always hotViolet (brand anchor)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.success,
          className: 'BULWARK',
          xpHero: '+412 XP',
          bpRank: 'Pernas · Rank 8',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final rightBar = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('share-card-achievement-frame-right-bar')),
    );
    expect(rightBar.color, AppColors.hotViolet);
  });

  testWidgets(
    'class-change override swaps the left bar to heroGold so both bars '
    'do not collapse to the same hue (drained → highlighted)',
    (tester) async {
      // On class-change the caller's dominantHue is already hotViolet
      // (per SharePayload.dominantHue's class-change override). Without
      // a left-bar swap, both bars would read as hotViolet — drained.
      // The widget's isClassChange flag swaps the left bar to heroGold.
      await tester.pumpWidget(
        host(
          const ShareCardAchievementFrame(
            dominantHue: AppColors.hotViolet,
            className: 'BULWARK',
            xpHero: '+420 XP',
            bpRank: 'Peito · Rank 18',
            wordmark: 'REPSAGA',
            isClassChange: true,
          ),
        ),
      );

      final leftBar = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('share-card-achievement-frame-left-bar')),
      );
      final rightBar = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('share-card-achievement-frame-right-bar')),
      );
      expect(leftBar.color, AppColors.heroGold);
      expect(rightBar.color, AppColors.hotViolet);
    },
  );

  testWidgets('lift detail renders in heroGold when hasPr is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.bodyPartChest,
          className: 'BULWARK',
          xpHero: '+618 XP',
          liftDetail: '95kg × 5 · Supino',
          hasPr: true,
          bpRank: 'Peito · Rank 19',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final lift = tester.widget<Text>(find.text('95kg × 5 · Supino'));
    expect(lift.style?.color, AppColors.heroGold);
  });

  testWidgets('lift detail renders in textCream when hasPr is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.bodyPartChest,
          className: 'BULWARK',
          xpHero: '+320 XP',
          liftDetail: '60kg × 8 · Supino',
          bpRank: 'Peito · Rank 12',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final lift = tester.widget<Text>(find.text('60kg × 8 · Supino'));
    expect(lift.style?.color, AppColors.textCream);
  });

  testWidgets('omits the lift-detail line when liftDetail is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.bodyPartChest,
          className: 'BULWARK',
          xpHero: '+320 XP',
          bpRank: 'Peito · Rank 12',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    // No "kg" / "×" appears — the slot is collapsed entirely (no
    // hero-gold reward accent leaking on a baseline session).
    expect(find.textContaining('kg'), findsNothing);
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets(
    'omits the saga eyebrow when sagaEyebrow is null (class-change Q4 lock)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardAchievementFrame(
            dominantHue: AppColors.hotViolet,
            className: 'BULWARK',
            xpHero: '+420 XP',
            bpRank: 'Peito · Rank 18',
            wordmark: 'REPSAGA',
            isClassChange: true,
          ),
        ),
      );

      // Top collar reads class name only — no eyebrow above it.
      // (REPSAGA wordmark intentionally contains "SAGA" so we match the
      // eyebrow's expected format "SAGA <n>" instead of a broader regex.)
      expect(find.text('BULWARK'), findsOneWidget);
      expect(find.textContaining(RegExp(r'SAGA \d+')), findsNothing);
    },
  );

  testWidgets('BP rank label renders in dominantHue', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.warning,
          className: 'BULWARK',
          xpHero: '+200 XP',
          bpRank: 'Ombros · Rank 4',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final rank = tester.widget<Text>(find.text('Ombros · Rank 4'));
    expect(rank.style?.color, AppColors.warning);
  });

  testWidgets('long exercise name in lift detail truncates with ellipsis '
      '(single-line bottom-collar constraint)', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.success,
          className: 'BULWARK',
          xpHero: '+540 XP',
          liftDetail: 'Levantamento Terra Romeno com Halteres em Pé · Costas',
          hasPr: true,
          bpRank: 'Costas · Rank 12',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    // The Text widget is configured for single-line ellipsis truncation.
    final liftText = tester.widget<Text>(
      find.text('Levantamento Terra Romeno com Halteres em Pé · Costas'),
    );
    expect(liftText.maxLines, 1);
    expect(liftText.overflow, TextOverflow.ellipsis);
  });

  testWidgets(
    'export target uses mockup §6 D3 sizes — XP hero 64px / class name '
    '36px / wordmark 18px',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardAchievementFrame(
            dominantHue: AppColors.bodyPartChest,
            className: 'BULWARK',
            sagaEyebrow: 'SAGA 76',
            xpHero: '+618 XP',
            bpRank: 'Peito · Rank 19',
            wordmark: 'REPSAGA',
            renderTarget: ShareCardRenderTarget.export,
          ),
        ),
      );

      expect(tester.widget<Text>(find.text('+618 XP')).style?.fontSize, 64);
      expect(tester.widget<Text>(find.text('BULWARK')).style?.fontSize, 36);
      expect(tester.widget<Text>(find.text('REPSAGA')).style?.fontSize, 18);
    },
  );

  testWidgets(
    'preview target uses scaled-down sizes so the FittedBox-shrunk visible '
    'preview reads (XP hero 38sp / class name 24sp / wordmark 11sp)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardAchievementFrame(
            dominantHue: AppColors.bodyPartChest,
            className: 'BULWARK',
            sagaEyebrow: 'SAGA 76',
            xpHero: '+618 XP',
            bpRank: 'Peito · Rank 19',
            wordmark: 'REPSAGA',
            renderTarget: ShareCardRenderTarget.preview,
          ),
        ),
      );

      expect(tester.widget<Text>(find.text('+618 XP')).style?.fontSize, 38);
      expect(tester.widget<Text>(find.text('BULWARK')).style?.fontSize, 24);
      expect(tester.widget<Text>(find.text('REPSAGA')).style?.fontSize, 11);
    },
  );

  testWidgets('collars render with abyss at ~92% opacity', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardAchievementFrame(
          dominantHue: AppColors.bodyPartChest,
          className: 'BULWARK',
          xpHero: '+320 XP',
          bpRank: 'Peito · Rank 12',
          wordmark: 'REPSAGA',
        ),
      ),
    );

    final topCollar = tester.widget<Container>(
      find.byKey(const ValueKey('share-card-achievement-frame-top-collar')),
    );
    final topColor = topCollar.color!;
    expect(topColor.r, AppColors.abyss.r);
    expect(topColor.g, AppColors.abyss.g);
    expect(topColor.b, AppColors.abyss.b);
    expect((topColor.a - 0.92).abs() < 0.01, isTrue);

    final bottomCollar = tester.widget<Container>(
      find.byKey(const ValueKey('share-card-achievement-frame-bottom-collar')),
    );
    final bottomColor = bottomCollar.color!;
    expect(bottomColor.r, AppColors.abyss.r);
    expect(bottomColor.g, AppColors.abyss.g);
    expect(bottomColor.b, AppColors.abyss.b);
    expect((bottomColor.a - 0.92).abs() < 0.01, isTrue);
  });
}
