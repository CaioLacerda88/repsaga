import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Whether a share-card variant widget is rendering for the **preview**
/// surface (visible inside `SharePreviewScreen` at the device's native
/// dp constraints) or the **export** surface (offscreen 1080×1920 tree
/// captured by `ShareImageRenderer.toImage(pixelRatio: 3.0)` and handed
/// to the native share sheet).
///
/// **Why two targets?** Phase 31 device verification surfaced that the
/// previous architecture wrapped the visible tree in
/// `AspectRatio(9/16) → FittedBox(contain) → SizedBox(1080×1920)`. The
/// FittedBox scaled the inner 1080-unit tree down to device width
/// (≈412dp → 0.381× scale factor on Samsung S25 Ultra). Typography
/// values that were authored as "what to read on-screen" then collapsed
/// to 4-15sp after the FittedBox shrink — the D3 collars looked
/// invisible and the XP hero was microscopic (Bugs A + C).
///
/// **Post-Phase-31 architecture:** the visible preview tree renders at
/// **device-native dp** (no FittedBox wrapping). Variants compute
/// collar heights + paddings as proportional fractions of the card's
/// laid-out dimensions (forwarded through `cardWidthDp` + `cardHeightDp`
/// constructor params, defaulting to the export 1080 / 1920). Typography
/// values mean what they say:
///
///   * `ShareCardRenderTarget.preview` — sp / dp values on the device
///     screen. e.g. XP hero = 42sp reads at 42sp on-device.
///   * `ShareCardRenderTarget.export` — px values inside the 1080×1920
///     offscreen tree captured by `toImage`. e.g. XP hero = 64px lands
///     at 64px in the shipped JPEG.
///
/// Geometry stays identical at the proportional level (15% collar slant,
/// 13% top-collar height fraction, 20% bottom-collar height fraction,
/// 4dp side bars) so the two targets render the same shape — only the
/// per-element font sizes vary.
///
/// Both maps are derived from the sanctioned [AppTextStyles] entry
/// points so the typography call-sites gate
/// (`check_typography_call_sites.sh`) still sees a single source of
/// family + weight rules.
enum ShareCardRenderTarget {
  /// The visible preview tree inside `SharePreviewScreen`, laid out at
  /// the device's native dp constraints (no FittedBox shrink).
  /// Typography is sized so it reads at-screen in sp.
  preview,

  /// The offscreen 1080×1920 tree captured by
  /// `ShareImageRenderer.toImage(pixelRatio: 3.0)` and handed to the
  /// native share sheet. Typography matches the locked mockup §6 sizes
  /// expressed as px values inside the 1080-unit canvas.
  export,
}

/// Single source of truth for the per-element font-size + letter-spacing
/// pairs across the two render targets.
///
/// **Invariant.** Most geometry is identical across targets — the strip
/// placement, slash position, layout rhythm. Only the text styles vary.
/// Tests assert the export-target styles match the mockup §6 sizes
/// exactly; the preview-target styles are scaled up so the FittedBox-
/// shrunk preview stays readable.
///
/// **Source.** Per UX-critic device-verification recommendation
/// (Bug 1, PR 30c). The preview-target sizes are roughly 2.5× to 3× the
/// export-target sizes — chosen so that after FittedBox scales the
/// 1080-unit tree down to a 360dp viewport, the visible text reads at
/// 9-13sp (touch-readable typography), while the export bytes keep the
/// locked design language.
class ShareCardTypography {
  ShareCardTypography._();

  // ─── Discreet ──────────────────────────────────────────────────────

  /// Discreet eyebrow (Barlow Condensed 600, +0.22em tracking, hue).
  static TextStyle discreetEyebrow(
    ShareCardRenderTarget target, {
    required Color hue,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 13.0 : 11.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.22 * size,
      color: hue,
    );
  }

  /// Discreet hero numeric (Rajdhani 700, -0.02em tracking, height 1.0).
  static TextStyle discreetHero(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 56.0 : 44.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: -0.02 * size,
      height: 1.0,
    );
  }

  /// Discreet hero sub-label (Barlow Condensed 600, +0.22em tracking,
  /// textDim).
  static TextStyle discreetHeroSubLabel(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 10.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.22 * size,
      color: AppColors.textDim,
    );
  }

  /// Discreet PR line (Rajdhani 600, +0.04em tracking, heroGold).
  /// `ignore: reward_accent` annotation belongs at the call site too.
  static TextStyle discreetPrLine(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 16.0 : 14.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.04 * size,
      // ignore: reward_accent — PR line is the canonical reward; heroGold scarcity contract met.
      color: AppColors.heroGold,
    );
  }

  /// Discreet wordmark (Rajdhani 700, +0.24em tracking, textDim).
  static TextStyle discreetWordmark(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 10.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.24 * size,
      color: AppColors.textDim,
    );
  }

  // ─── D3 Achievement Frame ──────────────────────────────────────────
  //
  // The single photo-overlay treatment for the share-card photo path
  // (Phase 31 — replaces Variant A + Variant B). Two trapezoidal collars
  // (top + bottom) frame the photo zone, with 4dp side bars in the
  // dominant-BP hue (left) + hotViolet (right).
  //
  // **Phase 31 device-fix rescale (Bugs A + C).** Preview values
  // pre-rescale were authored assuming the visible tree wrapped a
  // 1080×1920 SizedBox in a FittedBox (so the rendered sp values would
  // shrink by the ~0.38× scale factor on a 412dp viewport). After Phase
  // 31 device verification, that wrapping was removed — the visible
  // tree now renders at device-native dp. Preview values are restated
  // so they read at-screen in sp (XP hero 42sp = 42sp on-device).
  //
  // Sizes are locked per `docs/WIP.md` § Typography decisions (D3
  // Achievement Frame export + preview tables, refreshed Phase 31).

  /// Top-collar class name (Rajdhani 700, +0.04em tracking, textCream).
  /// 36px export / 22sp preview.
  static TextStyle achievementFrameClassName(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 22.0 : 36.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.04 * size,
    );
  }

  /// Top-collar saga eyebrow (Barlow Condensed 600, +0.22em tracking,
  /// textDim). 20px export / 11sp preview.
  static TextStyle achievementFrameSagaEyebrow(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 20.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.22 * size,
      color: AppColors.textDim,
    );
  }

  /// Bottom-collar XP hero (Rajdhani 700, -0.02em tracking, textCream).
  /// The primary numeric register of the share card. 64px export / 42sp
  /// preview — the primary visual the user reads on the preview screen.
  static TextStyle achievementFrameXpHero(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 42.0 : 64.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: -0.02 * size,
      height: 1.0,
    );
  }

  /// Bottom-collar lift detail (Rajdhani 700, +0.04em tracking). Color
  /// is `heroGold` when [isPr] is true (PR is the canonical reward) and
  /// `textCream` otherwise. 28px export / 15sp preview.
  static TextStyle achievementFrameLiftDetail(
    ShareCardRenderTarget target, {
    required bool isPr,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 15.0 : 28.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.04 * size,
      // ignore: reward_accent — PR is the canonical reward; heroGold scarcity contract met (only when isPr is true).
      color: isPr ? AppColors.heroGold : AppColors.textCream,
    );
  }

  /// Bottom-collar BP rank line (Barlow Condensed 600, +0.22em tracking,
  /// hue). Rendered in the dominant-BP hue to mirror the left side bar.
  /// 20px export / 11sp preview.
  static TextStyle achievementFrameBpRank(
    ShareCardRenderTarget target, {
    required Color hue,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 20.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.22 * size,
      color: hue,
    );
  }

  /// Bottom-collar wordmark (Rajdhani 700, +0.24em tracking, textDim).
  /// 18px export / 10sp preview.
  static TextStyle achievementFrameWordmark(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 10.0 : 18.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.24 * size,
      color: AppColors.textDim,
    );
  }

  // ─── Shared chassis (Phase 39) ─────────────────────────────────────
  //
  // The full-bleed photo-hero + scrim + 7-hue rail + wordmark frame both
  // the Bestiary and Clean Flex modes render their content block into
  // (spec §7). The chassis owns only the wordmark; each mode owns its
  // own eyebrow / hero. Sizes mirror the D3 export/preview ratios so the
  // shipped PNG and the on-screen preview stay in lockstep.

  /// Chassis wordmark (Rajdhani 700, +0.24em tracking, textDim). Reuses
  /// the D3 wordmark register so the brand mark reads identically across
  /// every share surface. 18px export / 10sp preview.
  static TextStyle chassisWordmark(ShareCardRenderTarget target) =>
      achievementFrameWordmark(target);

  /// Boss crown glyph (`♛`) floating over the photo — heroGold (spec §4 /
  /// mockup `.crown`, 30px at 300dp → 30sp preview / 54px export). Sized via
  /// the numeric register; the glyph itself is a Unicode symbol so the family
  /// only sets metrics, not letterforms.
  static TextStyle bossCrown(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 30.0 : 54.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      height: 1.0,
      // ignore: reward_accent — boss crown is the canonical rare-encounter reward; heroGold scarcity contract met (isBoss-gated call site).
      color: AppColors.heroGold,
    );
  }

  /// Boss "⚜ CHEFE / BOSS" badge label (Barlow Condensed 600, +0.16em
  /// tracking, gold) — spec §4 / mockup `.badge`. 9px at 300dp → 9sp preview
  /// / 16px export. The gold-tint pill background lives on the badge widget.
  static TextStyle bossBadge(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 9.0 : 16.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.16 * size,
      // ignore: reward_accent — boss badge is the canonical rare-encounter reward; heroGold scarcity contract met (isBoss-gated call site).
      color: AppColors.heroGold,
    );
  }

  // ─── Bestiary mode (Phase 39 spec §7) ──────────────────────────────

  /// Bestiary eyebrow ("⚔ HOJE VOCÊ ABATEU" / "⚜ CHEFE DERROTADO" for
  /// bosses) — Barlow Condensed 600, +0.26em tracking, hue (gold on
  /// bosses). 20px export / 11sp preview.
  static TextStyle bestiaryEyebrow(
    ShareCardRenderTarget target, {
    required Color color,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 20.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.26 * size,
      color: color,
    );
  }

  /// Bestiary beast name (Rajdhani 700 display register — the serif hero
  /// in the mockup; RepSaga bundles no serif family, so the closest
  /// sanctioned display register is used). 62px export / 31sp preview.
  /// [color] carries the line hue (cream on bosses, where the gold lives
  /// in the eyebrow + glyph).
  static TextStyle bestiaryName(
    ShareCardRenderTarget target, {
    required Color color,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 31.0 : 62.0;
    return AppTextStyles.display.copyWith(
      fontSize: size,
      letterSpacing: 0,
      height: 1.04,
      color: color,
    );
  }

  /// Bestiary rank/XP/tonnage stat line (Rajdhani 700, +0.04em tracking,
  /// textDimAA). 24px export / 13sp preview.
  static TextStyle bestiaryStat(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 13.0 : 24.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.04 * size,
      color: AppColors.textDimAA,
    );
  }

  /// Bestiary rank-sigil chip letter (the tier letter inside the rotated
  /// diamond, spec §4 / mockup `.sig b`). Rajdhani numeral register (the
  /// mockup uses Cinzel 800 — rejected per §17.0c + the w800 weight is
  /// CI-forbidden; the sanctioned hero numeral register is the closest fit).
  /// 11px at 300dp → 11sp preview / 20px export. [color] = the accent hue.
  static TextStyle bestiaryRankSigil(
    ShareCardRenderTarget target, {
    required Color color,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 20.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      height: 1.0,
      color: color,
    );
  }

  /// Bestiary XP value emphasis — the "+618 XP" fragment rendered in
  /// heroGold within the stat line (spec §7 mockup: XP in gold). Same
  /// size as [bestiaryStat].
  static TextStyle bestiaryStatXp(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 13.0 : 24.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.04 * size,
      // ignore: reward_accent — session XP is the canonical reward register on the bestiary card; heroGold scarcity contract met (single stat fragment).
      color: AppColors.heroGold,
    );
  }

  /// Bestiary achievement phrase (Barlow 400 italic, textDimAA). 28px
  /// export / 15sp preview. The mockup uses Cinzel italic; the closest
  /// sanctioned italic prose register is Barlow.
  static TextStyle bestiaryPhrase(
    ShareCardRenderTarget target, {
    required Color color,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 15.0 : 28.0;
    return AppTextStyles.body.copyWith(
      fontSize: size,
      fontStyle: FontStyle.italic,
      height: 1.3,
      color: color,
    );
  }

  // ─── Clean Flex mode (Phase 39 spec §7 Stats) ──────────────────────

  /// Clean Flex eyebrow ("BULWARK · NÍVEL 9") — Barlow Condensed 600,
  /// +0.22em tracking, hotViolet. 20px export / 11sp preview.
  static TextStyle cleanFlexEyebrow(
    ShareCardRenderTarget target, {
    required Color color,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 20.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.22 * size,
      color: color,
    );
  }

  /// Clean Flex hero (the PR lift, e.g. "130 kg × 3") — Rajdhani 700,
  /// -0.02em tracking, textCream. 84px export / 47sp preview.
  static TextStyle cleanFlexHero(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 47.0 : 84.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: -0.02 * size,
      height: 0.95,
    );
  }

  /// Clean Flex hero unit suffix (" kg × 3") — same family, demoted size.
  /// 40px export / 22sp preview.
  static TextStyle cleanFlexHeroUnit(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 22.0 : 40.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0,
      height: 0.95,
    );
  }

  /// Clean Flex four-stat strip value (Rajdhani 700, textCream). 34px
  /// export / 19sp preview.
  static TextStyle cleanFlexStatValue(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 19.0 : 34.0;
    return AppTextStyles.numeric.copyWith(fontSize: size, height: 1.0);
  }

  /// Clean Flex four-stat strip key (Barlow Condensed 600, +0.13em
  /// tracking, textDim). 15px export / 8.5sp preview.
  static TextStyle cleanFlexStatKey(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 8.5 : 15.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.13 * size,
      color: AppColors.textDim,
    );
  }
}
