import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/workouts/ui/post_session/share/variants/share_card_variant_a.dart';

/// Pins Variant A (Minimal Strip) overlay behavior — what the user sees on
/// the share card's bottom strip across PR / non-PR sessions and various
/// dominant body parts.
///
/// **Behavior, not wiring.** Each test asserts a rendered Text/widget on the
/// surface — not that a paint method was called. The accent line + bar fill
/// keys exist explicitly so the color contract can be verified at the
/// `ValueKey` boundary without painter mocking.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // 9:16 share card aspect.
          width: 270,
          height: 480,
          child: child,
        ),
      ),
    );
  }

  testWidgets(
    'renders the XP text and the wordmark verbatim (no l10n lookup)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardVariantA(
            dominantHue: AppColors.bodyPartChest,
            xpText: '+618 XP',
            wordmark: 'REPSAGA',
            barFillFraction: 0.78,
          ),
        ),
      );

      expect(find.text('+618 XP'), findsOneWidget);
      expect(find.text('REPSAGA'), findsOneWidget);
    },
  );

  testWidgets('renders the PR line when prText is provided', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantA(
          dominantHue: AppColors.bodyPartChest,
          xpText: '+618 XP',
          prText: '95kg × 5 · PR',
          wordmark: 'REPSAGA',
          barFillFraction: 0.78,
        ),
      ),
    );

    expect(find.text('95kg × 5 · PR'), findsOneWidget);
  });

  testWidgets('omits the PR slot entirely when prText is null', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantA(
          dominantHue: AppColors.bodyPartChest,
          xpText: '+412 XP',
          wordmark: 'REPSAGA',
          barFillFraction: 0.5,
        ),
      ),
    );

    expect(find.textContaining('PR'), findsNothing);
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('accent line color tracks the dominant BP hue', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantA(
          dominantHue: AppColors.bodyPartBack,
          xpText: '+320 XP',
          wordmark: 'REPSAGA',
          barFillFraction: 0.4,
        ),
      ),
    );

    final accent = tester.widget<Container>(
      find.byKey(const ValueKey('share-card-variant-a-accent')),
    );
    expect((accent.color), AppColors.bodyPartBack);
  });

  testWidgets('bar fill color tracks the dominant BP hue', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantA(
          dominantHue: AppColors.success, // legs
          xpText: '+540 XP',
          wordmark: 'REPSAGA',
          barFillFraction: 0.66,
        ),
      ),
    );

    final fill = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('share-card-variant-a-bar-fill')),
    );
    expect(fill.color, AppColors.success);
  });

  testWidgets(
    'bar fill fraction is clamped to [0.0, 1.0] (defensive — no overflow)',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ShareCardVariantA(
            dominantHue: AppColors.bodyPartChest,
            xpText: '+618 XP',
            wordmark: 'REPSAGA',
            barFillFraction: 1.5, // overshoot
          ),
        ),
      );

      final fractionallySized = tester.widget<FractionallySizedBox>(
        find.ancestor(
          of: find.byKey(const ValueKey('share-card-variant-a-bar-fill')),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(fractionallySized.widthFactor, 1.0);
    },
  );

  testWidgets('strip background is flat abyss at ~92% opacity', (tester) async {
    await tester.pumpWidget(
      host(
        const ShareCardVariantA(
          dominantHue: AppColors.bodyPartChest,
          xpText: '+618 XP',
          wordmark: 'REPSAGA',
          barFillFraction: 0.5,
        ),
      ),
    );

    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ShareCardVariantA),
        matching: find.byType(DecoratedBox),
      ),
    );
    final color = (decorated.decoration as BoxDecoration).color!;
    // Per mockup §6 "Render rules": rgba(13,3,25,0.92) — abyss at 92%.
    // We compare R/G/B to the abyss token (via the new float-channel
    // accessors — `.red/.green/.blue/.alpha` are deprecated in Flutter
    // 3.27+) and alpha within ~1% tolerance.
    expect(color.r, AppColors.abyss.r);
    expect(color.g, AppColors.abyss.g);
    expect(color.b, AppColors.abyss.b);
    expect((color.a - 0.92).abs() < 0.01, isTrue);
  });
}
