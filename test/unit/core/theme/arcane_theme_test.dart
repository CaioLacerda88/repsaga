/// Locks in the Arcane Ascent palette (§17.0c) and typography rhythm.
///
/// The 12 color tokens + 12 typography tokens (`display`, `headline`,
/// `title`, `titleDisplay`, `body`, `bodySmall`, `label`, `sectionHeader`,
/// `numeric`, `numericSmall`, `appBarTitle`, `celebrationSize`) are the
/// single source of truth every screen paints through. If this test ever
/// has to change to make CI pass, treat that as a palette-change review
/// — update the design doc first, not the assertion.
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

  group('AppTextStyles — token property pins', () {
    // Each token pins family + weight + size + height + letterSpacing +
    // baked color (where set). When the codebase swaps the body family
    // (Inter → Barlow in Phase 28b) ONLY the family assertions should
    // need to flip; every other property is independent of which font
    // backs the token.
    //
    // Family assertions use `startsWith` to stay resilient to any future
    // fallback-rename strategy (e.g. google_fonts' historic
    // "<Family>_<Variant>" stamping) while still failing loudly if
    // someone swaps the family in app_theme.dart.

    group('display (Rajdhani 700 32dp)', () {
      final style = AppTextStyles.display;
      test('family is Rajdhani', () {
        expect(style.fontFamily, startsWith('Rajdhani'));
      });
      test('weight is w700', () {
        expect(style.fontWeight, FontWeight.w700);
      });
      test('size is 32', () {
        expect(style.fontSize, 32.0);
      });
      test('height is 1.1', () {
        expect(style.height, closeTo(1.1, 0.001));
      });
      test('letterSpacing is 0.04 * 32 = 1.28', () {
        expect(style.letterSpacing, closeTo(1.28, 0.001));
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('headline (Rajdhani 600 24dp)', () {
      final style = AppTextStyles.headline;
      test('family is Rajdhani', () {
        expect(style.fontFamily, startsWith('Rajdhani'));
      });
      test('weight is w600', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 24', () {
        expect(style.fontSize, 24.0);
      });
      test('height is 1.2', () {
        expect(style.height, closeTo(1.2, 0.001));
      });
      test('letterSpacing is 0.02 * 24 = 0.48', () {
        expect(style.letterSpacing, closeTo(0.48, 0.001));
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('title (Barlow 600 16dp)', () {
      final style = AppTextStyles.title;
      test('family is Barlow', () {
        expect(style.fontFamily, startsWith('Barlow'));
      });
      test('weight is w600', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 16', () {
        expect(style.fontSize, 16.0);
      });
      test('height is 1.3', () {
        expect(style.height, closeTo(1.3, 0.001));
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('titleDisplay (Rajdhani 600 16dp — Phase 27 L18.4)', () {
      // titleDisplay is the Rajdhani variant of the 16dp list-title slot.
      // It is the ONLY token that diverges from Inter at this size — Routines
      // (action surfaces) use it; exercise/settings rows stay on [title]
      // (Inter). Locks family / weight / size / tracking / height.
      final style = AppTextStyles.titleDisplay;
      test('family is Rajdhani', () {
        expect(style.fontFamily, startsWith('Rajdhani'));
      });
      test('weight is w600', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 16', () {
        expect(style.fontSize, 16.0);
      });
      test('height matches title (1.3) so row layout is stable', () {
        expect(style.height, AppTextStyles.title.height);
      });
      test('letterSpacing is 0.02 * 16 = 0.32', () {
        expect(style.letterSpacing, closeTo(0.32, 0.001));
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });

      test('is NOT in _textTheme (must not become a Material default)', () {
        // titleDisplay is deliberately excluded from the Material TextTheme
        // so it can never be accidentally applied via Theme.of(context).
        // textTheme. Verify no slot in AppTheme.dark's TextTheme resolves to
        // a Rajdhani 600 16dp style (which would indicate titleDisplay
        // leaked into the theme as titleMedium or similar).
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
        for (final s in slots) {
          final isRajdhani = s?.fontFamily?.startsWith('Rajdhani') ?? false;
          final is16dp = s?.fontSize == 16.0;
          final isW600 = s?.fontWeight == FontWeight.w600;
          expect(
            isRajdhani && is16dp && isW600,
            isFalse,
            reason:
                'titleDisplay (Rajdhani 600 16dp) must not be wired into the '
                'Material TextTheme. Found a matching slot: $s',
          );
        }
      });
    });

    group('body (Barlow 400 14dp)', () {
      final style = AppTextStyles.body;
      test('family is Barlow', () {
        expect(style.fontFamily, startsWith('Barlow'));
      });
      test('weight is w400', () {
        expect(style.fontWeight, FontWeight.w400);
      });
      test('size is 14', () {
        expect(style.fontSize, 14.0);
      });
      test('height is 1.5', () {
        expect(style.height, closeTo(1.5, 0.001));
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('bodySmall (Barlow 400 12dp textDim)', () {
      final style = AppTextStyles.bodySmall;
      test('family is Barlow', () {
        expect(style.fontFamily, startsWith('Barlow'));
      });
      test('weight is w400', () {
        expect(style.fontWeight, FontWeight.w400);
      });
      test('size is 12', () {
        expect(style.fontSize, 12.0);
      });
      test('height is 1.5', () {
        expect(style.height, closeTo(1.5, 0.001));
      });
      test('color is textDim', () {
        expect(style.color, AppColors.textDim);
      });
    });

    group('label (Barlow Condensed 600 11dp eyebrow)', () {
      final style = AppTextStyles.label;
      test('family is Barlow Condensed', () {
        expect(style.fontFamily, startsWith('Barlow Condensed'));
      });
      test('weight is w600', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 11', () {
        expect(style.fontSize, 11.0);
      });
      test('height is 1.2', () {
        expect(style.height, closeTo(1.2, 0.001));
      });
      test('letterSpacing is 0.12 * 11 = 1.32 (eyebrow tracking)', () {
        expect(style.letterSpacing, closeTo(1.32, 0.001));
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('sectionHeader (Barlow Condensed 600 13dp eyebrow)', () {
      // Derived from `label` via `.copyWith(fontSize: 13, letterSpacing:
      // 0.12 * 13)` — one step up from the chip/tab register so a heading
      // can hold its own next to body copy without competing with [title].
      // Color is intentionally NOT baked — call sites pick (e.g.
      // hotViolet for /saga/stats sections), so the assertion lets the
      // call site own it.
      //
      // Phase 28b: bumped from 12dp to 13dp to match the `SectionHeader`
      // widget's rendered size + the button text-style derivation
      // (`label.copyWith(fontSize: 13)`). Reconciles a token / widget drift.
      final style = AppTextStyles.sectionHeader;
      test('family inherits Barlow Condensed from label', () {
        expect(style.fontFamily, startsWith('Barlow Condensed'));
      });
      test('weight is w600 (inherited from label)', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 13', () {
        expect(style.fontSize, 13.0);
      });
      test('letterSpacing is 0.12 * 13 = 1.56', () {
        expect(style.letterSpacing, closeTo(1.56, 0.001));
      });
    });

    group('numeric (Rajdhani 700 20dp tabular)', () {
      final style = AppTextStyles.numeric;
      test('family is Rajdhani', () {
        expect(style.fontFamily, startsWith('Rajdhani'));
      });
      test('weight is w700', () {
        expect(style.fontWeight, FontWeight.w700);
      });
      test('size is 20', () {
        expect(style.fontSize, 20.0);
      });
      test('height is 1.1', () {
        expect(style.height, closeTo(1.1, 0.001));
      });
      test('fontFeatures contain tabularFigures', () {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      });
      test('color is textCream', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('numericSmall (Rajdhani 600 11dp textDim — Phase 28a)', () {
      // Promotes the repeated 5-property override stack
      //   `numeric.copyWith(fontSize: 11, w600, textDim,
      //    letterSpacing: 0.04 * 11)`
      // into a single token. Inherits `fontFeatures` (tabular figures)
      // from [numeric] so sub-bar numerals don't jitter as digits change.
      final style = AppTextStyles.numericSmall;
      test('family is Rajdhani', () {
        expect(style.fontFamily, startsWith('Rajdhani'));
      });
      test('weight is w600', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 11', () {
        expect(style.fontSize, 11.0);
      });
      test('letterSpacing is 0.04 * 11 = 0.44', () {
        expect(style.letterSpacing, closeTo(0.44, 0.001));
      });
      test('height is 1.4', () {
        expect(style.height, closeTo(1.4, 0.001));
      });
      test('color is textDim', () {
        expect(style.color, AppColors.textDim);
      });
      test('inherits tabular figures from numeric', () {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      });
    });

    group('appBarTitle (Rajdhani 600 18dp — Phase 28a)', () {
      // Promotes the pre-Phase-28a inline
      //   `AppTextStyles.headline.copyWith(fontSize: 18, letterSpacing:
      //    0.02 * 18)`
      // (sitting in `AppTheme.dark.appBarTheme.titleTextStyle`) into a
      // named token. Property pins assert the contract; the
      // theme-wiring group below pins that the AppBarTheme reads through
      // this same token.
      final style = AppTextStyles.appBarTitle;
      test('family is Rajdhani (inherited from headline)', () {
        expect(style.fontFamily, startsWith('Rajdhani'));
      });
      test('weight is w600 (inherited from headline)', () {
        expect(style.fontWeight, FontWeight.w600);
      });
      test('size is 18', () {
        expect(style.fontSize, 18.0);
      });
      test('letterSpacing is 0.02 * 18 = 0.36', () {
        expect(style.letterSpacing, closeTo(0.36, 0.001));
      });
      test('height inherits headline (1.2)', () {
        expect(style.height, AppTextStyles.headline.height);
      });
      test('color is textCream (inherited from headline)', () {
        expect(style.color, AppColors.textCream);
      });
    });

    group('celebrationSize(size) (Rajdhani 700 hero-sized — Phase 28a)', () {
      // Parameterized helper for celebration overlay numerals.
      // Spot-checked at the three canonical sizes used by the overlay
      // tier (level-up 64sp / class-change 36sp / rank-up 24sp).
      //
      // `letterSpacing: 1.28` (= 0.04 * 32 from display) is INHERITED
      // size-agnostic — that's intentional. At 64sp it reads as 0.02em,
      // at 24sp as 0.053em. Pinning it here catches any future change to
      // [display]'s tracking silently rippling through all three
      // celebration overlays. The `class_change_overlay` overrides this
      // with `.copyWith(letterSpacing: 0.06 * 36)` to preserve its
      // per-glyph letter-reveal choreography — the override is on the
      // call site, not on the token.

      test('at 24sp — Rajdhani 700 height 1.0 + display tracking', () {
        final style = AppTextStyles.celebrationSize(24);
        expect(style.fontFamily, startsWith('Rajdhani'));
        expect(style.fontWeight, FontWeight.w700);
        expect(style.fontSize, 24.0);
        expect(style.height, closeTo(1.0, 0.001));
        expect(style.letterSpacing, closeTo(0.04 * 32, 0.001));
      });

      test('at 36sp — Rajdhani 700 height 1.0 + display tracking', () {
        final style = AppTextStyles.celebrationSize(36);
        expect(style.fontFamily, startsWith('Rajdhani'));
        expect(style.fontWeight, FontWeight.w700);
        expect(style.fontSize, 36.0);
        expect(style.height, closeTo(1.0, 0.001));
        expect(style.letterSpacing, closeTo(0.04 * 32, 0.001));
      });

      test('at 64sp — Rajdhani 700 height 1.0 + display tracking', () {
        final style = AppTextStyles.celebrationSize(64);
        expect(style.fontFamily, startsWith('Rajdhani'));
        expect(style.fontWeight, FontWeight.w700);
        expect(style.fontSize, 64.0);
        expect(style.height, closeTo(1.0, 0.001));
        expect(style.letterSpacing, closeTo(0.04 * 32, 0.001));
      });

      test('inherits color from display (textCream)', () {
        expect(AppTextStyles.celebrationSize(64).color, AppColors.textCream);
      });
    });
  });

  group('AppTheme.dark — typography wiring', () {
    // The appBarTheme's titleTextStyle must route through the named
    // [AppTextStyles.appBarTitle] token (not an inline copyWith) so the
    // contract is testable from one place.
    test('appBarTheme.titleTextStyle equals AppTextStyles.appBarTitle', () {
      final wired = AppTheme.dark.appBarTheme.titleTextStyle;
      final token = AppTextStyles.appBarTitle;
      expect(wired?.fontFamily, token.fontFamily);
      expect(wired?.fontWeight, token.fontWeight);
      expect(wired?.fontSize, token.fontSize);
      expect(wired?.letterSpacing, token.letterSpacing);
      expect(wired?.height, token.height);
      expect(wired?.color, token.color);
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
