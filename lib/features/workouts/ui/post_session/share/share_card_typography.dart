import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Whether a share-card variant widget is rendering for the **preview**
/// surface (visible inside `SharePreviewScreen` on the device's native
/// screen) or the **export** surface (offscreen 1080×1920 tree captured
/// by `ShareImageRenderer.toImage(pixelRatio: 3.0)` and handed to the
/// native share sheet).
///
/// **Why two targets?** The card lives in a 1080×1920 logical-pixel tree.
/// On the export path that's the final image size. On the preview path
/// the same tree is scaled by `FittedBox` down to roughly the device
/// width (≈360dp on a typical Android phone — about a 0.333 scale
/// factor). Typography sized for the 1080×1920 export collapses to 7-9px
/// effective on-screen, well below the readable threshold.
///
/// The fix is two trees with **identical geometry** (same strip placement,
/// same collar clip paths, same slash position, same vertical rhythm)
/// but **different per-element font sizes**. The export tree keeps the
/// locked mockup §6 sizes — the visual contract for the shipped image —
/// while the preview tree uses larger sizes that survive the FittedBox
/// scale-down.
///
/// Mockup §6 typography sizes live in [ShareCardTypography.export]; the
/// preview-screen-sized typography lives in [ShareCardTypography.preview].
/// Both are derived from the sanctioned [AppTextStyles] entry points so
/// the typography call-sites gate (`check_typography_call_sites.sh`)
/// still sees a single source of family + weight rules.
enum ShareCardRenderTarget {
  /// The visible, FittedBox-scaled preview inside `SharePreviewScreen`.
  /// Typography is sized so it stays readable after the scale-down to
  /// the device's logical-pixel viewport.
  preview,

  /// The offscreen 1080×1920 tree captured by
  /// `ShareImageRenderer.toImage(pixelRatio: 3.0)` and handed to the
  /// native share sheet. Typography matches the locked mockup §6 sizes.
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
  // dominant-BP hue (left) + hotViolet (right). Typography sizes are
  // locked per docs/WIP.md § "Typography decisions" — D3 Achievement
  // Frame export + preview tables.

  /// Top-collar class name (Rajdhani 700, +0.04em tracking, textCream).
  /// 36px export / 24sp preview.
  static TextStyle achievementFrameClassName(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 24.0 : 36.0;
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
  /// The primary numeric register of the share card. 64px export / 38sp
  /// preview.
  static TextStyle achievementFrameXpHero(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 38.0 : 64.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: -0.02 * size,
      height: 1.0,
    );
  }

  /// Bottom-collar lift detail (Rajdhani 700, +0.04em tracking). Color
  /// is `heroGold` when [isPr] is true (PR is the canonical reward) and
  /// `textCream` otherwise. 28px export / 16sp preview.
  static TextStyle achievementFrameLiftDetail(
    ShareCardRenderTarget target, {
    required bool isPr,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 16.0 : 28.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.04 * size,
      // ignore: reward_accent — PR is the canonical reward; heroGold scarcity contract met (only when isPr is true).
      color: isPr ? AppColors.heroGold : AppColors.textCream,
    );
  }

  /// Bottom-collar BP rank line (Barlow Condensed 600, +0.22em tracking,
  /// hue). Rendered in the dominant-BP hue to mirror the left side bar.
  /// 20px export / 12sp preview.
  static TextStyle achievementFrameBpRank(
    ShareCardRenderTarget target, {
    required Color hue,
  }) {
    final size = target == ShareCardRenderTarget.preview ? 12.0 : 20.0;
    return AppTextStyles.label.copyWith(
      fontSize: size,
      letterSpacing: 0.22 * size,
      color: hue,
    );
  }

  /// Bottom-collar wordmark (Rajdhani 700, +0.24em tracking, textDim).
  /// 18px export / 11sp preview.
  static TextStyle achievementFrameWordmark(ShareCardRenderTarget target) {
    final size = target == ShareCardRenderTarget.preview ? 11.0 : 18.0;
    return AppTextStyles.numeric.copyWith(
      fontSize: size,
      letterSpacing: 0.24 * size,
      color: AppColors.textDim,
    );
  }
}
