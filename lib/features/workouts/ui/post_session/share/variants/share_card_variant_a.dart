import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';
import '../share_card_typography.dart';

/// Variant A — Minimal Strip overlay (mockup §6 default).
///
/// Renders the bottom 18% strip overlay only — the photo underlay is the
/// caller's responsibility (the `ShareCardRenderer` stacks the photo behind
/// this widget). This is the WhatsApp-Status-native default for every
/// session and every share target.
///
/// **Visual contract (mockup §6):**
///   * Flat abyss strip at 92% opacity (`AppColors.abyss.withValues(alpha:0.92)`).
///     No blur, no backdrop-filter — readable on any background brightness.
///   * 2dp top accent line in [dominantHue].
///   * Row 1: `xpText` (Rajdhani 22sp tabular) on the left; optional `prText`
///     (Rajdhani 16sp heroGold) on the right. Both via `AppTextStyles`.
///   * 3dp progress bar with white-10% track + hue fill at [barFillFraction].
///   * REPSAGA wordmark right-aligned (Rajdhani 9sp, +0.22em tracking, textDim).
///
/// **Decoupling Rule 2 — pre-localized strings.** Every visible string
/// (`xpText`, `prText`, `wordmark`) is a constructor parameter. NO
/// `AppLocalizations.of(context)` here; the screen layer formats and passes.
class ShareCardVariantA extends StatelessWidget {
  const ShareCardVariantA({
    super.key,
    required this.dominantHue,
    required this.xpText,
    required this.wordmark,
    required this.barFillFraction,
    this.prText,
    this.renderTarget = ShareCardRenderTarget.export,
  });

  /// Hue accent color — drives the top 2dp line + the bar fill.
  /// Picked by the caller from the SharePayload's `dominantHue` getter.
  final Color dominantHue;

  /// Pre-formatted XP line, e.g. "+618 XP".
  final String xpText;

  /// Pre-formatted PR line, e.g. "95kg × 5 · PR". `null` on non-PR sessions —
  /// renders nothing on the right of row 1, leaving XP alone (mockup §6
  /// Variant A legend: "on baseline sessions it disappears entirely").
  final String? prText;

  /// Wordmark string. Always non-null. Constant "REPSAGA" today but kept as
  /// a param so future white-label / event-rebrand surfaces can override.
  final String wordmark;

  /// Progress bar fill fraction in [0.0, 1.0]. Reflects the dominant BP's
  /// rank progress fraction; clamped defensively inside the widget.
  final double barFillFraction;

  /// Whether this widget is the export (1080×1920 offscreen) tree OR the
  /// preview (FittedBox-scaled visible) tree. Drives the typography
  /// sizing — see [ShareCardTypography] for the per-element pairs.
  /// Defaults to [ShareCardRenderTarget.export] so the golden contract
  /// (which captures the 1080×1920 frame) stays correct without callers
  /// touching the param.
  final ShareCardRenderTarget renderTarget;

  @override
  Widget build(BuildContext context) {
    final clampedFill = barFillFraction.clamp(0.0, 1.0);
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.abyss.withValues(alpha: 0.92),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 2dp hue accent — sits at the top edge of the padding row.
              // (The strip's padded interior reads as "inside the accent";
              // mockup positions the accent as a top hairline of the strip.)
              Container(
                key: const ValueKey('share-card-variant-a-accent'),
                height: 2,
                color: dominantHue,
              ),
              const SizedBox(height: 12),
              // Row 1: XP (left, big) + optional PR (right, heroGold).
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    xpText,
                    style: ShareCardTypography.variantAXp(renderTarget),
                  ),
                  const Spacer(),
                  if (prText != null)
                    // ignore: reward_accent — PR is the canonical reward; heroGold scarcity contract met (PR-only render via ShareCardTypography.variantAPr).
                    Text(
                      prText!,
                      style: ShareCardTypography.variantAPr(renderTarget),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Mini progress bar (3dp).
              SizedBox(
                height: 3,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      // ignore: hardcoded_color — progress-track background (10%-white scrim, no token covers this transient overlay).
                      child: ColoredBox(color: Color(0x1AFFFFFF)),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: clampedFill,
                      child: ColoredBox(
                        key: const ValueKey('share-card-variant-a-bar-fill'),
                        color: dominantHue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Wordmark — Rajdhani 700 (textDim), +0.22em tracking,
              // right-aligned. Size routed through ShareCardTypography so
              // the preview-target widening (9sp → 11sp) reads on a
              // FittedBox-scaled visible preview. Derived from `numeric`
              // so the family override stays inside the sanctioned
              // `AppTextStyles.*` entry point — Gate 1 forbids raw
              // `fontFamily: 'Rajdhani'` literals at call sites.
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  wordmark,
                  style: ShareCardTypography.variantAWordmark(renderTarget),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
