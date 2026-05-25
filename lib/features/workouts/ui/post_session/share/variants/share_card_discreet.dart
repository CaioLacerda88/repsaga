import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../../cuts/cut_slash.dart';
import '../share_card_typography.dart';

/// Discreet — the no-photo cinematic still (mockup §6 "Discreet mode").
///
/// **NOT a degraded fallback.** This is a film still in the same Concept-B
/// grammar (abyss + hue flood + diagonal slash + hero numeric) — auto-
/// selected when camera permission is denied OR the user taps
/// "Sem foto · só a saga".
///
/// **Visual contract (mockup §6):**
///   * Background: 135° linear gradient — top-left = [dominantHue] at 20%
///     alpha, transitioning to [AppColors.abyss] by 65%.
///   * Diagonal slash via the shared `paintCutSlash` helper — 2dp thin line,
///     -8° rotated, top 28% of frame (matches the Concept-B cut grammar
///     locked in PR 30a mockup §4½). Drawn in [dominantHue] at 100% alpha.
///   * D-eyebrow (Barlow Condensed 11sp 0.22em tracked, hue) — e.g.
///     "Peito · Rank 19" or "BULWARK DESPERTOU." (class change override).
///   * D-hero (Rajdhani 700 44sp tabular, textCream, line-height 1) — the
///     XP total (`+618`) or the class-change announcement.
///   * XP sub-label below the hero, textDim, Barlow Condensed.
///   * Optional d-sub (heroGold) for the PR lift line + small follow-up
///     body line.
///   * D-wordmark at the bottom-center (Rajdhani 700 10sp +0.24em tracked,
///     textDim).
///
/// **Decoupling Rule 2.** All visible strings arrive as constructor params.
class ShareCardDiscreet extends StatelessWidget {
  const ShareCardDiscreet({
    super.key,
    required this.dominantHue,
    required this.eyebrow,
    required this.heroText,
    required this.heroSubLabel,
    required this.wordmark,
    this.prLine,
    this.prDetail,
    this.renderTarget = ShareCardRenderTarget.export,
  });

  /// Hue accent — drives the background flood top-left, the slash color,
  /// and the eyebrow text. On a class-change session the caller passes
  /// [AppColors.hotViolet] (mockup §6 render rule override).
  final Color dominantHue;

  /// D-eyebrow text, e.g. "Peito · Rank 19" or "BULWARK DESPERTOU."
  /// (class-change override).
  final String eyebrow;

  /// D-hero text — the load-bearing numeral or announcement. e.g. "+618"
  /// (XP) or "BULWARK" (class-change). Rendered at 44sp Rajdhani 700.
  final String heroText;

  /// Sub-label under the hero, e.g. "XP NESTA SAGA" / "XP THIS SAGA".
  final String heroSubLabel;

  /// Optional heroGold PR line, e.g. "!! 95kg × 5". Renders only on PR
  /// sessions. `null` collapses the gap entirely.
  final String? prLine;

  /// Optional small follow-up body line below the PR line, e.g.
  /// "Supino · novo recorde". Caller may use this for non-PR follow-ups
  /// too (e.g. "Saga continua"); the widget is agnostic.
  final String? prDetail;

  /// Wordmark, e.g. "REPSAGA". Rendered Rajdhani 700 10sp +0.24em tracked
  /// at the bottom-center.
  final String wordmark;

  /// Whether this widget is the export (1080×1920 offscreen) tree OR the
  /// preview (FittedBox-scaled visible) tree. Drives the typography
  /// sizing — see [ShareCardTypography] for the per-element pairs.
  /// Defaults to [ShareCardRenderTarget.export] so the golden contract
  /// stays correct.
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: 135° gradient — hue at 20% alpha → abyss by 65%.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.65, 1.0],
              colors: [
                dominantHue.withValues(alpha: 0.20),
                AppColors.abyss,
                AppColors.abyss,
              ],
            ),
          ),
        ),
        // Diagonal slash via the shared helper (cluster — same primitive as
        // every post-session B-cut painter). 2dp thin, -8°, top 28%.
        CustomPaint(
          painter: _DiscreetSlashPainter(color: dominantHue),
          size: Size.infinite,
        ),
        // Content — top-padded so the slash + eyebrow stack naturally;
        // bottom-padded for the wordmark.
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(18, 60, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 36),
              Text(
                eyebrow,
                key: const ValueKey('share-card-discreet-eyebrow'),
                style: ShareCardTypography.discreetEyebrow(
                  renderTarget,
                  hue: dominantHue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                heroText,
                key: const ValueKey('share-card-discreet-hero'),
                textAlign: TextAlign.center,
                style: ShareCardTypography.discreetHero(renderTarget),
              ),
              const SizedBox(height: 4),
              Text(
                heroSubLabel,
                style: ShareCardTypography.discreetHeroSubLabel(renderTarget),
              ),
              if (prLine != null) ...[
                const SizedBox(height: 22),
                // ignore: reward_accent — PR line is the canonical reward; heroGold scarcity contract met (rendered through ShareCardTypography.discreetPrLine).
                Text(
                  prLine!,
                  key: const ValueKey('share-card-discreet-pr-line'),
                  style: ShareCardTypography.discreetPrLine(renderTarget),
                ),
              ],
              if (prDetail != null) ...[
                const SizedBox(height: 4),
                Text(prDetail!, style: AppTextStyles.bodySmall),
              ],
              const Spacer(),
              Text(
                wordmark,
                key: const ValueKey('share-card-discreet-wordmark'),
                style: ShareCardTypography.discreetWordmark(renderTarget),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wraps `paintCutSlash` (cluster: same primitive every post-session
/// B-cut painter uses) so the slash here is byte-identical to the
/// cinematic B-cut slashes — no hand-rolled diagonal.
class _DiscreetSlashPainter extends CustomPainter {
  _DiscreetSlashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintCutSlash(canvas, size, color: color, alpha: 1.0);
  }

  @override
  bool shouldRepaint(covariant _DiscreetSlashPainter oldDelegate) =>
      oldDelegate.color != color;
}
