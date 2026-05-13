import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'radii.dart';

/// Arcane Ascent palette for RepSaga.
///
/// These tokens are the single source of truth for every color in the app.
/// They were chosen for the Material Design direction B in
/// `tasks/mockups/material-saga-comparison-v2.html` and the reward-scarcity
/// framework documented in `lib/core/theme/README.md`.
///
/// **Reward scarcity rule.** [heroGold] is rendered ONLY through the
/// `RewardAccent` widget — it is a variable-ratio reward signal for PRs,
/// level-ups and streak milestones. `scripts/check_reward_accent.sh` enforces
/// this in CI.
///
/// Nothing else in `lib/` should ship a raw `Color(0x…)` — see
/// `scripts/check_hardcoded_colors.sh`.
class AppColors {
  const AppColors._();

  /// Base background. Used for the scaffold on every screen and as the
  /// splash/launch surface.
  static const abyss = Color(0xFF0D0319);

  /// Default card / sheet surface. One step above [abyss].
  static const surface = Color(0xFF1A0F2E);

  /// Elevated surface — input fields, secondary chips, resting-state buttons.
  /// Two steps above [abyss]; one above [surface].
  static const surface2 = Color(0xFF241640);

  /// Primary brand violet. Structural accent — primary buttons, tab indicator,
  /// FAB gradient start, section dividers when a color beat is needed.
  static const primaryViolet = Color(0xFF6A2FA8);

  /// Daily / interactive violet. Active nav tint, hyperlinks, secondary CTAs,
  /// selected chip stroke. Reads brighter than [primaryViolet] on [abyss].
  static const hotViolet = Color(0xFFB36DFF);

  /// **REWARD-ONLY** gold — PR flash, level-up burst, streak milestone badge.
  /// Rendered only through the `RewardAccent` widget; see
  /// `scripts/check_reward_accent.sh`.
  static const heroGold = Color(0xFFFFB800);

  /// Primary text — reads as off-white on [abyss] without looking surgical.
  static const textCream = Color(0xFFEEE7FA);

  /// Secondary text — captions, metadata, disabled labels.
  static const textDim = Color(0xFF9C8DB8);

  /// Positive delta / success state. Distinct from [heroGold] so a green
  /// ✓ chip never competes visually with a reward flash.
  static const success = Color(0xFF62C46D);

  /// Warning — intentionally in the warm-yellow family but different from
  /// [heroGold] so a caution banner is not mistaken for a PR.
  static const warning = Color(0xFFFFB84D);

  /// Error / destructive action.
  static const error = Color(0xFFFF6B6B);

  /// Hairline for dividers and card borders. A low-alpha violet so borders
  /// feel like they belong to the palette rather than gray plate.
  static const hair = Color(0x24B36DFF); // rgba(179,109,255,0.14)
}

/// Typography tokens for the app, layered on top of the Material `TextTheme`.
///
/// Two families: Rajdhani (display/headline/numeric) and Inter (title/body/
/// label). Rajdhani is a condensed humanist sans that scans fast under gym
/// fatigue at 18+ dp; Inter covers paragraph readability below 16 dp.
///
/// See `lib/core/theme/README.md` for the reward-scarcity rule and the
/// "one display, one body, one numeric" typographic rhythm.
class AppTextStyles {
  const AppTextStyles._();

  /// Rajdhani 700 — hero copy, splash wordmark, primary CTA.
  static TextStyle get display => GoogleFonts.rajdhani(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.04 * 32,
    height: 1.1,
    color: AppColors.textCream,
  );

  /// Rajdhani 600 — card titles, overlay titles, section headers.
  static TextStyle get headline => GoogleFonts.rajdhani(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.02 * 24,
    height: 1.2,
    color: AppColors.textCream,
  );

  /// Inter 600 — list-item titles, routine names, card sub-titles.
  static TextStyle get title => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textCream,
  );

  /// Inter 400 — paragraph copy, descriptions.
  static TextStyle get body => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textCream,
  );

  /// Inter 400 — small meta, captions.
  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textDim,
  );

  /// Inter 600 uppercase with +0.12em tracking — chips, tabs, metadata rails.
  static TextStyle get label => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.12 * 11,
    height: 1.2,
    color: AppColors.textCream,
  );

  /// `[label]` at 12px — section headers above tables/cards on the
  /// numeric face of the saga (`/saga/stats`). One step up from the
  /// chip/tab register so a heading can hold its own next to body copy
  /// without competing with [title]. Color is left to the call site
  /// (sections currently use [AppColors.hotViolet]; future sections may
  /// pick a state-color).
  static TextStyle get sectionHeader =>
      label.copyWith(fontSize: 12, letterSpacing: 0.12 * 12);

  /// Rajdhani 700 tabular — XP counts, level numbers, weight/rep numerals.
  static TextStyle get numeric => GoogleFonts.rajdhani(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
    height: 1.1,
    color: AppColors.textCream,
  );
}

/// App-wide Material 3 theme.
///
/// Seeded from [AppColors.primaryViolet] with explicit overrides for
/// surface/onSurface so dark-mode text stays on the [AppColors.textCream]
/// off-white instead of Material's default pure white.
class AppTheme {
  const AppTheme._();

  /// Primary brand gradient. Used for the "Create" FAB, the start-workout
  /// CTA and a few other primary-intent surfaces. Anything else that needs a
  /// solid primary should read [AppColors.primaryViolet] directly.
  static const primaryGradient = LinearGradient(
    colors: [AppColors.primaryViolet, AppColors.hotViolet],
  );

  /// Destructive gradient — delete routines / wipe data. Reads red without
  /// leaking [heroGold] into the scarcity budget.
  static const destructiveGradient = LinearGradient(
    colors: [AppColors.error, Color(0xFF8A2F2F)],
  );

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryViolet,
      brightness: Brightness.dark,
      primary: AppColors.primaryViolet,
      onPrimary: AppColors.textCream,
      secondary: AppColors.hotViolet,
      onSecondary: AppColors.abyss,
      surface: AppColors.surface,
      onSurface: AppColors.textCream,
      surfaceContainerHighest: AppColors.surface2,
      error: AppColors.error,
      onError: AppColors.textCream,
      outline: AppColors.hair,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.abyss,
      textTheme: _textTheme,
      cardTheme: _cardTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      filledButtonTheme: _filledButtonTheme,
      inputDecorationTheme: _inputDecorationTheme,
      segmentedButtonTheme: _segmentedButtonTheme,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLg)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: TextStyle(color: AppColors.textCream),
        behavior: SnackBarBehavior.floating,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryViolet,
        foregroundColor: AppColors.textCream,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textCream,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hair, thickness: 1),
    );
  }

  static TextTheme get _textTheme => TextTheme(
    displayLarge: AppTextStyles.display.copyWith(fontSize: 40),
    displayMedium: AppTextStyles.display.copyWith(fontSize: 32),
    displaySmall: AppTextStyles.display.copyWith(fontSize: 24),
    headlineLarge: AppTextStyles.headline.copyWith(fontSize: 28),
    headlineMedium: AppTextStyles.headline,
    headlineSmall: AppTextStyles.headline.copyWith(fontSize: 20),
    titleLarge: AppTextStyles.title.copyWith(fontSize: 20),
    titleMedium: AppTextStyles.title,
    titleSmall: AppTextStyles.title.copyWith(fontSize: 14),
    bodyLarge: AppTextStyles.body.copyWith(fontSize: 16),
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.bodySmall,
    labelLarge: AppTextStyles.label.copyWith(fontSize: 13),
    labelMedium: AppTextStyles.label,
    labelSmall: AppTextStyles.label.copyWith(fontSize: 10),
  );

  static CardThemeData get _cardTheme => CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
      side: const BorderSide(color: AppColors.hair),
    ),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  );

  static ElevatedButtonThemeData get _elevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryViolet,
          foregroundColor: AppColors.textCream,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: AppTextStyles.label.copyWith(fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusSm + 2), // 10
          ),
        ),
      );

  static OutlinedButtonThemeData get _outlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.hotViolet,
          side: const BorderSide(color: AppColors.hotViolet),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: AppTextStyles.label.copyWith(fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusSm + 2),
          ),
        ),
      );

  static FilledButtonThemeData get _filledButtonTheme => FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primaryViolet,
      foregroundColor: AppColors.textCream,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: AppTextStyles.label.copyWith(fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSm + 2),
      ),
    ),
  );

  /// Dark-surface tuning for Material 3 `SegmentedButton`.
  ///
  /// M3's default renders underpowered on our deep-violet surface: the
  /// selected container is barely tinted and the unselected label drops to
  /// ~0.38 alpha. This theme bumps selected visibility (primary tint at 0.15,
  /// primary foreground, weight 600) and lifts unselected foreground to
  /// 0.75 alpha so both segments stay legible on dark surfaces.
  static SegmentedButtonThemeData get _segmentedButtonTheme =>
      SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryViolet.withValues(alpha: 0.15);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.hotViolet;
            }
            return AppColors.textCream.withValues(alpha: 0.75);
          }),
          textStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppTextStyles.label.copyWith(fontWeight: FontWeight.w600);
            }
            // w600 (SemiBold) is bundled via google_fonts; w500 (Medium) is
            // not, so with `allowRuntimeFetching = false` Flutter nearest-
            // matches to w400/w600 unpredictably. Using w600 here gives the
            // "slightly heavier than body" intent for the unselected label
            // while matching a bundled weight exactly.
            return AppTextStyles.label.copyWith(fontWeight: FontWeight.w600);
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(
                color: AppColors.hotViolet.withValues(alpha: 0.5),
              );
            }
            return const BorderSide(color: AppColors.hair);
          }),
        ),
      );

  static InputDecorationThemeData get _inputDecorationTheme =>
      InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.textDim),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
          borderSide: const BorderSide(color: AppColors.hotViolet, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadiusSm + 2),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
      );
}
