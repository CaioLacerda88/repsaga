/// Locks in the Arcane Ascent palette (§17.0c) and typography rhythm.
///
/// The 12 color tokens + 7 text styles are the single source of truth every
/// screen paints through. If this test ever has to change to make CI pass,
/// treat that as a palette-change review — update the design doc first, not
/// the assertion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/theme/app_theme.dart';

void main() {
  group('AppColors — Arcane Ascent 12-token palette', () {
    test('abyss is #0D0319', () {
      expect(AppColors.abyss, const Color(0xFF0D0319));
    });

    test('surface is #1A0F2E', () {
      expect(AppColors.surface, const Color(0xFF1A0F2E));
    });

    test('surface2 is #241640', () {
      expect(AppColors.surface2, const Color(0xFF241640));
    });

    test('primaryViolet is #6A2FA8', () {
      expect(AppColors.primaryViolet, const Color(0xFF6A2FA8));
    });

    test('hotViolet is #B36DFF', () {
      expect(AppColors.hotViolet, const Color(0xFFB36DFF));
    });

    test('heroGold is #FFB800 (reward-scarcity-gated)', () {
      // Intentionally asserted here despite the reward-accent lint.
      // This file is on the check_reward_accent.sh allow-list
      // (lib/core/theme/app_theme.dart owns the constant; test files are
      // automatically skipped by the script's `lib/` scope), so the lock-in
      // assertion does not break the scarcity rule.
      expect(AppColors.heroGold, const Color(0xFFFFB800));
    });

    test('textCream is #EEE7FA', () {
      expect(AppColors.textCream, const Color(0xFFEEE7FA));
    });

    test('textDim is #9C8DB8', () {
      expect(AppColors.textDim, const Color(0xFF9C8DB8));
    });

    test('success is #62C46D', () {
      expect(AppColors.success, const Color(0xFF62C46D));
    });

    test('warning is #FFB84D', () {
      expect(AppColors.warning, const Color(0xFFFFB84D));
    });

    test('error is #FF6B6B', () {
      expect(AppColors.error, const Color(0xFFFF6B6B));
    });

    test('hair is rgba(179,109,255,0.14)', () {
      // 0x24 == 36 == round(255 * 0.14).
      expect(AppColors.hair, const Color(0x24B36DFF));
    });
  });

  group('AppTextStyles — font families', () {
    // GoogleFonts stamps the family as "<Family>_<Variant>" (see
    // google_fonts/src/google_fonts_family_with_variant.dart). Locking a
    // `startsWith` assertion is resilient to fallback renames while still
    // failing loudly if someone swaps the family in app_theme.dart.

    test('display uses Rajdhani', () {
      expect(AppTextStyles.display.fontFamily, startsWith('Rajdhani'));
    });

    test('headline uses Rajdhani', () {
      expect(AppTextStyles.headline.fontFamily, startsWith('Rajdhani'));
    });

    test('title uses Inter', () {
      expect(AppTextStyles.title.fontFamily, startsWith('Inter'));
    });

    test('body uses Inter', () {
      expect(AppTextStyles.body.fontFamily, startsWith('Inter'));
    });

    test('bodySmall uses Inter', () {
      expect(AppTextStyles.bodySmall.fontFamily, startsWith('Inter'));
    });

    test('label uses Inter', () {
      expect(AppTextStyles.label.fontFamily, startsWith('Inter'));
    });

    test('titleDisplay uses Rajdhani', () {
      expect(AppTextStyles.titleDisplay.fontFamily, startsWith('Rajdhani'));
    });

    test('numeric uses Rajdhani with tabular figures', () {
      expect(AppTextStyles.numeric.fontFamily, startsWith('Rajdhani'));
      expect(
        AppTextStyles.numeric.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('AppTextStyles — titleDisplay contract (Phase 27 L18.4)', () {
    // titleDisplay is the Rajdhani variant of the 16dp list-title slot.
    // It is the ONLY token that diverges from Inter at this size — Routines
    // (action surfaces) use it; exercise/settings rows stay on [title] (Inter).
    // These assertions lock the five properties the UX-critic verdict locked:
    // family (Rajdhani), weight (600), size (16dp), tracking (0.32 = 0.02*16),
    // and height (1.3 — same line-box as [title] so routine card layout is
    // stable when the two tokens share a parent Column).
    test('is Rajdhani 600 at 16dp', () {
      expect(AppTextStyles.titleDisplay.fontFamily, startsWith('Rajdhani'));
      expect(AppTextStyles.titleDisplay.fontWeight, FontWeight.w600);
      expect(AppTextStyles.titleDisplay.fontSize, 16.0);
    });

    test('letter-spacing is 0.02 * 16 = 0.32', () {
      expect(AppTextStyles.titleDisplay.letterSpacing, closeTo(0.32, 0.001));
    });

    test('height matches title (1.3) so row layout is stable', () {
      expect(AppTextStyles.titleDisplay.height, AppTextStyles.title.height);
    });

    test('is NOT in _textTheme (must not become a Material default)', () {
      // titleDisplay is deliberately excluded from the Material TextTheme so
      // it can never be accidentally applied via Theme.of(context).textTheme.
      // Verify no slot in AppTheme.dark's TextTheme resolves to a Rajdhani
      // 600 16dp style (which would indicate titleDisplay leaked into the
      // theme as titleMedium or similar).
      final textTheme = AppTheme.dark.textTheme;
      final slots = [
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.titleLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.bodyLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
        textTheme.labelLarge,
      ];
      // None of the theme slots should be Rajdhani 600 at 16dp.
      for (final style in slots) {
        final isRajdhani = style?.fontFamily?.startsWith('Rajdhani') ?? false;
        final is16dp = style?.fontSize == 16.0;
        final isW600 = style?.fontWeight == FontWeight.w600;
        expect(
          isRajdhani && is16dp && isW600,
          isFalse,
          reason:
              'titleDisplay (Rajdhani 600 16dp) must not be wired into the '
              'Material TextTheme. Found a matching slot: $style',
        );
      }
    });
  });

  group('AppTheme.dark', () {
    test('is Material 3', () {
      expect(AppTheme.dark.useMaterial3, isTrue);
    });

    test('is a dark-brightness theme', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('scaffold background is AppColors.abyss', () {
      expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.abyss);
    });

    test('primary color is AppColors.primaryViolet', () {
      expect(AppTheme.dark.colorScheme.primary, AppColors.primaryViolet);
    });

    test('surface is AppColors.surface', () {
      expect(AppTheme.dark.colorScheme.surface, AppColors.surface);
    });

    test('onSurface is AppColors.textCream', () {
      expect(AppTheme.dark.colorScheme.onSurface, AppColors.textCream);
    });

    test('error color is AppColors.error', () {
      expect(AppTheme.dark.colorScheme.error, AppColors.error);
    });
  });
}
