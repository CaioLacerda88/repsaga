import 'package:flutter/material.dart';

import 'radii.dart';

/// Arcane Ascent palette for RepSaga.
///
/// These tokens are the single source of truth for every color in the app.
/// They were chosen for the locked "Arcane Ascent" design direction
/// (Direction B in the Phase 17.0c material-vs-pixel review; see
/// `docs/PROJECT.md` Phase 17 and Phase 26 entries for the design-language
/// history) and the reward-scarcity framework documented in
/// `lib/core/theme/README.md`.
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
  ///
  /// **Decorative / non-text use ONLY** post-Phase-38.9. [textDim] sits at
  /// ~2.78:1 on [abyss] at small sizes — below the WCAG-AA 4.5:1 floor for
  /// body text. Keep it for non-text decoration (strength-bar tracks, faint
  /// dividers, empty-state placeholder strokes) where the contrast guideline
  /// does not apply. For any DIM TEXT, reach for [textDimAA] instead.
  static const textDim = Color(0xFF9C8DB8);

  /// AA-compliant secondary text (Phase 38.9 T2.6).
  ///
  /// A brighter neutral lavender that clears the WCAG-AA 4.5:1 floor for
  /// small body text while staying visibly DIM (not promoted to the
  /// full-strength [textCream] register). Measured contrast on the app
  /// surfaces: ~9.76:1 on [abyss], ~8.85:1 on [surface], ~8.07:1 on
  /// [surface2] — comfortably AA (and AAA) for both 12sp body and the 10sp
  /// eyebrow tier.
  ///
  /// **Text-only.** This is the secondary-TEXT token; it is NOT a body-part
  /// identity hue (brand-vs-identity rule, `project_design_language_brand_
  /// vs_identity`). Use it for `bodySmall` / `numericSmall` text, dim unit
  /// labels, date eyebrows, and dim secondary labels on dark surfaces.
  /// Decorative non-text dimming stays on [textDim].
  static const textDimAA = Color(0xFFCFC5E3);

  /// Positive delta / success state. Distinct from [heroGold] so a green
  /// ✓ chip never competes visually with a reward flash.
  static const success = Color(0xFF62C46D);

  /// Warning — intentionally in the warm-yellow family but different from
  /// [heroGold] so a caution banner is not mistaken for a PR.
  static const warning = Color(0xFFFFB84D);

  /// Error / destructive action.
  static const error = Color(0xFFFF6B6B);

  // ─── Body-part identity (Phase 26a) ──────────────────────────────────
  /// Pink — chest body-part identity (Phase 26a). Anatomical fit (pec/heart)
  /// and distinct from every other body-part hue + the brand violet stack.
  /// Frees [hotViolet] to be the pure brand-primary (gradients, accents,
  /// character XP) without bleeding into the chest body-part identity.
  static const bodyPartChest = Color(0xFFF472B6);

  /// Sky-blue — back body-part identity (Phase 26a). Replaces the old
  /// [primaryViolet] mapping in `VitalityStateStyles.bodyPartColor[back]`
  /// to resolve the chest/back "two purples" hue collision.
  static const bodyPartBack = Color(0xFF38BDF8);

  /// Teal-cyan — cardio track identity (Phase 38b, locked in the
  /// `docs/phase-38-mockups.html` design pass).
  ///
  /// Retuned from the Phase 26a orange placeholder (`0xFFFB923C`) — that
  /// token was infrastructure-only and DEAD (no live surface read it;
  /// cardio rendered in `hair` gray everywhere), so the retune has zero
  /// sweep impact. Cardio is a systemic *capacity*, not a 7th anatomical
  /// body part; the cyan deliberately sits outside the warm body-part
  /// family AND outside the brand violet stack so "teal = my conditioning"
  /// reads as its own parallel track.
  ///
  /// First consumer: the `CardioEntryCard` logging surface (card stripe,
  /// duration hero, done CTA). `body_part_hues.dart` still maps cardio →
  /// `hair`; that wiring + its design-token sweep across Saga/Stats/
  /// celebration surfaces is Phase 38d (cluster:
  /// design-token-sweep-on-new-tokens).
  static const bodyPartCardio = Color(0xFF22D3EE);

  // ─── Progress infrastructure (Phase 26a) ─────────────────────────────
  /// Violet-tinted XP/progress bar track (Phase 26a).
  ///
  /// 10% alpha on [hotViolet]. Replaces the generic
  /// `rgba(255,255,255,0.06)` neutral white-alpha track that progress
  /// bars used pre-Phase-26. Keeps progress infrastructure inside the
  /// Arcane Ascent palette rather than borrowing from a neutral design
  /// system.
  static const xpTrack = Color(0x1AB36DFF); // unfilled track behind XP fill

  // ─── Vitality ramp (Phase 26a) ───────────────────────────────────────
  //
  // Semantic aliases over success / warning / error. Same hex values;
  // named for self-documenting call sites where the rendered semantic
  // is "vitality HP-drain", not "success" or "error". Used by the new
  // [VitalityStateStyles.vitalityRampColorFor] helper.

  /// High band (66–100%). Alias of [success].
  static const vitalityHigh = success;

  /// Mid band (34–65%). Alias of [warning].
  static const vitalityMid = warning;

  /// Low band (0–33%). Alias of [error].
  static const vitalityLow = error;

  /// Hairline for dividers and card borders. A low-alpha violet so borders
  /// feel like they belong to the palette rather than gray plate.
  static const hair = Color(0x24B36DFF); // rgba(179,109,255,0.14)
}

/// Typography tokens for the app, layered on top of the Material `TextTheme`.
///
/// Three families: Rajdhani (display/headline/numeric/celebration), Barlow
/// (title/body/bodySmall), and Barlow Condensed (label/sectionHeader). Phase
/// 28b swapped the body tier from Inter to Barlow — Inter is retained in
/// pubspec.fonts only as a passive fallback during rollout and will be
/// removed in a follow-up cleanup. Rajdhani is a condensed humanist sans
/// that scans fast under gym fatigue at 18+ dp; Barlow covers paragraph
/// readability below 16 dp with a slightly warmer rhythm than Inter;
/// Barlow Condensed picks up Rajdhani's verticality at micro-copy size for
/// the uppercase tracked eyebrow / chip / section-header tier.
///
/// **Loading contract (Phase 27 L14):** all three families are bundled via
/// `pubspec.yaml > flutter.fonts:` and read here through direct
/// `TextStyle(fontFamily: ...)` calls — NOT via the `google_fonts` package's
/// async API. The package's asset-manifest lookup was silently falling back
/// to Inter on real-device release builds, breaking the entire two-family
/// identity. Direct `fontFamily` references Flutter's synchronous font
/// loader and never races first paint. See
/// `project_design_language_typography`.
///
/// See `lib/core/theme/README.md` for the reward-scarcity rule and the
/// "one display, one body, one numeric" typographic rhythm.
class AppTextStyles {
  const AppTextStyles._();

  /// Rajdhani 700 — hero copy, splash wordmark, primary CTA.
  ///
  /// **Use for:** splash wordmark, primary CTA hero text, action-hero
  /// headline (e.g. the "Treino livre" hero on Home).
  ///
  /// **Not for:** AppBar titles (use [appBarTitle]); in-screen section
  /// headers (use [headline]); standalone numerals (use [numeric]).
  static TextStyle get display => const TextStyle(
    fontFamily: 'Rajdhani',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.04 * 32,
    height: 1.1,
    color: AppColors.textCream,
  );

  /// Rajdhani 600 — card titles, overlay titles, section headers.
  ///
  /// **Use for:** page-section heroes (the "Treino livre" action-hero
  /// uses [display]; smaller hero-tier cards use this), overlay-card
  /// titles (rank-up / level-up text-only beats before they reach
  /// celebration-tier size).
  ///
  /// **Not for:** AppBar titles (use [appBarTitle]); list-item titles
  /// (use [title] or [titleDisplay]); the "the surface IS the numeral"
  /// celebration register (use [celebrationSize]).
  static TextStyle get headline => const TextStyle(
    fontFamily: 'Rajdhani',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.02 * 24,
    height: 1.2,
    color: AppColors.textCream,
  );

  /// Barlow 600 — list-item titles, card sub-titles.
  ///
  /// **Routine names use [titleDisplay] instead** (the Rajdhani variant).
  /// See the dartdoc on [titleDisplay] for the design-language rationale
  /// (Phase 27 L18.4 locked decision).
  ///
  /// **Use for:** list-item titles in reference surfaces (exercise list
  /// cards, settings rows), dialog titles, card sub-titles.
  ///
  /// **Not for:** action surfaces where the row IS the daily-driver CTA
  /// (use [titleDisplay]); numerals embedded in a value role (use
  /// [numeric]).
  ///
  /// Family swap (Phase 28b): Inter → Barlow. Weight ramp stays 600.
  static TextStyle get title => const TextStyle(
    fontFamily: 'Barlow',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textCream,
  );

  /// Rajdhani 600 — the action-surface variant of [title].
  ///
  /// Same 16dp slot as [title] (so it drops into list-item rows without
  /// reflowing layout) but routes the family to Rajdhani so the call site
  /// reads as an "Arcane Ascent" performance artifact rather than as
  /// reference content. Reserved for surfaces where the list item IS the
  /// primary action — tapping starts a workout, opens a celebration, etc.
  /// `RoutineCard` is the canonical user: the card is the daily-driver
  /// CTA on Home and the start-the-workout affordance on `/routines`.
  ///
  /// Do NOT use this for reference-browse surfaces (exercise list,
  /// settings rows). Those stay on [title] (Inter) so the screen-title
  /// Rajdhani at the top of the screen retains its tier separation —
  /// promoting every list-item to Rajdhani collapses the hierarchy
  /// into a single-typeface "word wall" (UX-critic Phase-27-L18.4
  /// reasoning).
  ///
  /// Letter-spacing follows [headline]'s 2% multiplier so the two
  /// Rajdhani sizes read as the same family rhythm.
  ///
  /// **Not wired into [_textTheme]** — deliberately excluded so it
  /// cannot become a Material theme default (`titleMedium`). Call
  /// sites that need this register must reach for `AppTextStyles.titleDisplay`
  /// directly, which keeps the design-language opt-in explicit.
  static TextStyle get titleDisplay => const TextStyle(
    fontFamily: 'Rajdhani',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.02 * 16,
    height: 1.3,
    color: AppColors.textCream,
  );

  /// Barlow 400 — paragraph copy, descriptions.
  ///
  /// **Use for:** paragraph prose, form tips, exercise descriptions,
  /// dialog body text, snackbar copy, mixed-string cardinality lines
  /// like "3 exercícios".
  ///
  /// **Not for:** standalone numerals (use [numeric]); eyebrow / chip
  /// / section delimiters (use [label] or [sectionHeader]).
  ///
  /// Family swap (Phase 28b): Inter → Barlow. Weight 400 stays.
  static TextStyle get body => const TextStyle(
    fontFamily: 'Barlow',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textCream,
  );

  /// Barlow 400 — small meta, captions.
  ///
  /// **Use for:** secondary metadata (timestamps, sub-titles,
  /// caption-context, "last session" lines).
  ///
  /// **Not for:** numeric data — even at this size, that's
  /// [numericSmall]'s register. Eyebrow labels stay on [label].
  ///
  /// Family swap (Phase 28b): Inter → Barlow.
  static TextStyle get bodySmall => const TextStyle(
    fontFamily: 'Barlow',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    // Phase 38.9 T2.6: AA-compliant dim text (was textDim ~2.78:1 < 4.5).
    color: AppColors.textDimAA,
  );

  /// Barlow Condensed 600 uppercase with +0.12em tracking — chips, tabs,
  /// metadata rails.
  ///
  /// **Use for:** 11sp uppercase tracked eyebrow / chip / tab labels,
  /// metadata-rail delimiters. Call sites pass an already-uppercased
  /// string (ARB key supplies the casing).
  ///
  /// **Not for:** data values, even small ones (use [numericSmall]);
  /// section eyebrows above tables (use [sectionHeader]).
  ///
  /// Family swap (Phase 28b): Inter → Barlow Condensed. The condensed
  /// width-axis picks up Rajdhani's verticality at micro-copy size — gives
  /// uppercase tracked labels an engineered feel without escalating to the
  /// display register.
  static TextStyle get label => const TextStyle(
    fontFamily: 'Barlow Condensed',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.12 * 11,
    height: 1.2,
    color: AppColors.textCream,
  );

  /// `[label]` at 13px — section headers above tables/cards on the
  /// numeric face of the saga (`/saga/stats`). One step up from the
  /// chip/tab register so a heading can hold its own next to body copy
  /// without competing with [title]. Color is left to the call site
  /// (sections currently use [AppColors.hotViolet]; future sections may
  /// pick a state-color).
  ///
  /// **Use for:** 13sp uppercase tracked section eyebrows above
  /// tables / cards (e.g. "VITALIDADE ATUAL").
  ///
  /// **Not for:** chips / tabs (use [label]); list-item titles (use
  /// [title]).
  ///
  /// Phase 28b: standardized at 13dp (was 12dp). Reconciles the prior
  /// inconsistency where the `SectionHeader` widget hand-rolled 13dp on
  /// top of `label.copyWith(fontSize: 13, …)` while the token sat at 12dp.
  /// 13dp matches the `ElevatedButton/FilledButton/OutlinedButton.textStyle`
  /// derivation (`label.copyWith(fontSize: 13)`) — promoted section headers
  /// read at the same size as button text, intentional visual rhythm.
  static TextStyle get sectionHeader =>
      label.copyWith(fontSize: 13, letterSpacing: 0.12 * 13);

  /// Rajdhani 700 tabular — XP counts, level numbers, weight/rep numerals.
  ///
  /// **Use for:** ALL numeric data — LVL, XP, weight, reps, %, rank values,
  /// set counts, PR values, weight-stepper output. Anywhere a numeral is
  /// the load-bearing piece of information.
  ///
  /// **Not for:** mixed-string cardinality (e.g. "3 exercícios" — that's
  /// prose with a number embedded; use [body]). Not for non-data text
  /// even when monospace would technically look fine.
  static TextStyle get numeric => const TextStyle(
    fontFamily: 'Rajdhani',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.1,
    color: AppColors.textCream,
  );

  /// Rajdhani 600 11sp tabular textDim — small numeric metadata lines
  /// where the value is data but the visual register is supporting-text.
  ///
  /// Promotes the 6-property override stack
  ///   `numeric.copyWith(fontSize: 11, fontWeight: w600, color: textDim,
  ///    letterSpacing: 0.04 * 11, height: 1.4)`
  /// (repeated in body-part rank rows + character-card closest-rank
  /// indicator) into a single token so the next surface that needs the
  /// same register reaches for one name instead of copy-pasting overrides.
  ///
  /// **`height: 1.4` is intentional and is a delta from the previous
  /// override stacks** on `body_part_rank_row.dart:161,169`, which inherited
  /// [numeric]'s `1.1` line-height by not overriding it. Sub-bar XP labels
  /// sit under a 4dp progress bar and benefit from the extra ~3.3px of
  /// leading at 11sp; if visual verification surfaces a layout regression
  /// here, the fix is either a per-call-site `.copyWith(height: 1.1)`
  /// override OR splitting `numericSmall` into two tier-specific tokens.
  ///
  /// **Use for:** sub-bar XP labels (`X XP` / `Y restantes`),
  /// character-card closest-rank indicator (`X XP for rank Y`), rank
  /// progress meta.
  ///
  /// **Not for:** standalone numerals (use [numeric] at full size). Not
  /// for prose with a number embedded (use [body] or [bodySmall]).
  static TextStyle get numericSmall => numeric.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    // Phase 38.9 T2.6: AA-compliant dim numerals (was textDim ~2.78:1 < 4.5).
    color: AppColors.textDimAA,
    letterSpacing: 0.04 * 11,
    height: 1.4,
  );

  /// [numericSmall]'s typography (Rajdhani 600 11sp tabular,
  /// letter-spacing 0.04 × 11, line-height 1.4) WITHOUT a baked-in
  /// color. Use this token inside a [RewardAccent] (or any
  /// `DefaultTextStyle.merge` wrapper) so the surrounding scope's
  /// color flows through. Caught during PR #285 device verification —
  /// `numericSmall`'s `color: textDim` overrides [RewardAccent]'s
  /// `heroGold` via Flutter's `Text.style.merge` explicit-wins rule,
  /// so the gold PR diamond rendered as dim grey-violet on real
  /// hardware.
  ///
  /// **Use for:** numeric data rendered inside `RewardAccent` (PR
  /// diamond, gold PR-row glyph on the workout detail screen, future
  /// `RewardAccent`-scoped numeric badges).
  ///
  /// **Not for:** standalone numerals (use [numericSmall] — the
  /// baked `textDim` is the right register at the bare-screen level).
  static TextStyle get numericSmallInheriting => const TextStyle(
    fontFamily: 'Rajdhani',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.04 * 11,
    height: 1.4,
  );

  /// Rajdhani 600 18sp — AppBar titles across all screens.
  ///
  /// Wired into [AppTheme.dark]'s `appBarTheme.titleTextStyle` so every
  /// AppBar that doesn't pass an explicit `title:` style picks this up
  /// automatically. Defining it as a named token (rather than the
  /// pre-Phase-28a inline `headline.copyWith(fontSize: 18, letterSpacing:
  /// 0.02 * 18)`) gives unit tests something to assert against and lets
  /// future call sites pin the AppBar register without re-deriving the
  /// size/tracking math.
  ///
  /// **Use for:** any AppBar's `title:` widget.
  ///
  /// **Not for:** in-screen section headers (use [headline] or
  /// [sectionHeader]); overlay-card titles (use [headline]).
  static TextStyle get appBarTitle =>
      headline.copyWith(fontSize: 18, letterSpacing: 0.02 * 18);

  /// Rajdhani 700 hero-sized — celebration overlay numerals.
  ///
  /// Parameterized by [size] because each celebration tier has its own
  /// visual weight in the choreography:
  ///   * Level-up: 64sp glyph numeral
  ///   * Class-change: 36sp class-name display
  ///   * Rank-up: 24sp rank-line display
  ///
  /// `height: 1.0` because celebration overlays sit in `Column`s with
  /// hand-tuned `SizedBox(height: ...)` gaps below the numeral — letting
  /// `display`'s default 1.1 leading bleed through here would offset the
  /// caller's vertical spacing math.
  ///
  /// **Use for:** standalone overlay-dominant text where the whole
  /// surface IS the text (level-up burst, rank-up label, class-change
  /// announcement).
  ///
  /// **Not for:** inline-screen display text (use [display] or
  /// [headline]). Not for numerals embedded in a data row (use [numeric]).
  static TextStyle celebrationSize(double size) =>
      display.copyWith(fontSize: size, height: 1.0);
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
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textCream,
        // L15: AppBar titles use Rajdhani 600 per mockup `.mock-appbar-title`
        // (font-family: 'Rajdhani'; font-weight: 600; font-size: 18px;
        // letter-spacing: 0.02em). Material's default falls back to Inter
        // titleLarge — wrong for our display-font identity. See
        // `project_design_language_typography`. Phase 28a: routed through
        // the named [AppTextStyles.appBarTitle] token so the contract is
        // testable and call-site overrides share a single derivation.
        titleTextStyle: AppTextStyles.appBarTitle,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hair, thickness: 1),
    );
  }

  /// Narrow `TextTheme` compatibility shim — Phase 28b Step 4.
  ///
  /// **This shim is intentionally narrow.** App code MUST route through
  /// `AppTextStyles.*` directly (enforced by Gate 6 in
  /// `scripts/check_typography_call_sites.sh`). The slots wired here exist
  /// ONLY so Flutter's Material widgets can inherit a brand-consistent
  /// style from their internal `*Defaults*M3` classes when RepSaga doesn't
  /// override the component theme:
  ///
  ///   * `bodyLarge` — `InputDecoration` M3 hint (`input_decorator.dart` 2202-2204),
  ///     `ListTile` M3 title (`list_tile.dart` 1786).
  ///   * `bodyMedium` — `Dialog` M3 content (`dialog.dart:1825`),
  ///     `SnackBar` M3 content (`snack_bar.dart:973-977`),
  ///     `ListTile` M3 subtitle (`list_tile.dart:1787`).
  ///   * `bodySmall` — `InputDecoration` M3 helper / error / counter
  ///     (`input_decorator.dart` 5839-5855, 6028-6053).
  ///   * `labelLarge` — `Chip` / `FilterChip` M3 label
  ///     (`chip.dart:2505`, `filter_chip.dart:332`).
  ///   * `labelMedium` — `NavigationBar` M3 destination label
  ///     (`navigation_bar.dart:1471`).
  ///   * `titleMedium` — `PopupMenuItem` M3 (`popup_menu.dart:1817`),
  ///     `InputDecoration` base size for `floatingLabelStyle`
  ///     (`input_decorator.dart:2188`).
  ///
  /// Slots dropped at narrowing time (no Material widget RepSaga uses
  /// inherits them, or RepSaga overrides the component theme entirely —
  /// e.g. `ElevatedButton`/`FilledButton`/`OutlinedButton` set
  /// `textStyle: AppTextStyles.label.copyWith(fontSize: 13)` directly):
  /// `displayLarge`, `displayMedium`, `displaySmall`, `headlineLarge`,
  /// `headlineMedium`, `headlineSmall`, `titleLarge`, `titleSmall`,
  /// `labelSmall`.
  ///
  /// If a future Material widget unexpectedly inherits from a dropped slot
  /// and falls back to Flutter's M3 defaults (which would NOT be Rajdhani /
  /// Barlow), RESTORE the slot here and document the inheriting widget.
  static TextTheme get _textTheme => TextTheme(
    bodyLarge: AppTextStyles.body.copyWith(fontSize: 16),
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.bodySmall,
    labelLarge: AppTextStyles.label.copyWith(fontSize: 13),
    labelMedium: AppTextStyles.label,
    titleMedium: AppTextStyles.title,
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
            // w600 (SemiBold) is bundled via `pubspec.yaml > flutter.fonts:`;
            // w500 (Medium) is not, so Flutter nearest-matches to w400/w600
            // unpredictably for Inter. Using w600 here gives the "slightly
            // heavier than body" intent for the unselected label while
            // matching a bundled weight exactly. (Post-Phase-27-L14: the
            // `google_fonts` async API is forbidden in production paths —
            // see `lib/core/theme/README.md` typography section.)
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
