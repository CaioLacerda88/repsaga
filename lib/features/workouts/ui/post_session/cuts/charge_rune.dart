import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// The cinematic B2 hero rune end-cap: a small [ChargeRune] + a descriptive
/// charge line, rendered above the rank bar in the SAME beat/hue (Phase
/// Vitality-2 S4). Shared by `B2BpTallyCut`, `B2ElevatedCut`, and the cascade
/// hero so the charge flourish looks identical wherever it fuses onto a beat.
///
/// **Two states (mockup cinematic frames i / ii):**
///  * gainer ([isMax] false) → the rune fills its segments as [fill] climbs
///    (`0 → 1` over the host beat's bar-fill window); the line shows
///    `▲ +N%` + the past-tense "Conditioning recharged" subtitle.
///  * MÁX ([isMax] true) → the rune is pre-lit/held (a single hold, no climb
///    — never fake a charge that didn't happen); the line shows the "MÁX"
///    word + the "Conditioning at peak" subtitle, never a dead `+0`.
///
/// **Fill-only safety contract.** The rune only lights up — it never drains
/// or reddens. Copy is past-tense descriptive (no decay/loss-aversion).
///
/// **Decoupling Rule 2.** All copy arrives pre-localized from the screen.
class B2ChargeEndCap extends StatelessWidget {
  const B2ChargeEndCap({
    super.key,
    required this.hue,
    required this.afterPct,
    required this.isMax,
    required this.fill,
    required this.deltaPercent,
    required this.deltaLabel,
    required this.maxLabel,
    required this.rechargedLabel,
    required this.atPeakLabel,
  });

  /// The hero body-part identity hue.
  final Color hue;

  /// Charge fraction after the session (`[0, 1]`).
  final double afterPct;

  /// True → held-at-peak (pre-lit/held rune + MÁX). False → gainer.
  final bool isMax;

  /// The host beat's bar-fill progress (`0 → 1`). Drives the rune climb on a
  /// gainer; ignored on a MÁX cap (the rune is held full).
  final double fill;

  /// Integer percentage-point delta for the `▲ +N%` line (gainer only).
  final int deltaPercent;

  /// Pre-localized `+N%` builder.
  final String Function(int pct) deltaLabel;

  /// Pre-localized "MÁX" held word.
  final String maxLabel;

  /// Pre-localized "Conditioning recharged" gainer subtitle.
  final String rechargedLabel;

  /// Pre-localized "Conditioning at peak" MÁX subtitle.
  final String atPeakLabel;

  @override
  Widget build(BuildContext context) {
    final litTarget = litSegmentsForFraction(afterPct);
    // MÁX → held full (no climb). Gainer → climb with the bar-fill window.
    final litNow = isMax
        ? litTarget
        : (litTarget * fill).ceil().clamp(0, litTarget);

    final trailing = isMax ? maxLabel : deltaLabel(deltaPercent);
    final subtitle = isMax ? atPeakLabel : rechargedLabel;

    return Semantics(
      container: true,
      identifier: 'post-session-b2-charge',
      // Explicit label so the rune + delta + subtitle don't merge into a
      // newline-joined AOM name (cluster: aom-label-text-merge).
      label: '$trailing · $subtitle',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ChargeRune(hue: hue, litSegments: litNow, width: 14, height: 24),
          const SizedBox(width: 9),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMax)
                Text(
                  maxLabel,
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 15,
                    color: hue,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '▲',
                      style: AppTextStyles.numeric.copyWith(
                        fontSize: 11,
                        color: hue,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      deltaLabel(deltaPercent),
                      style: AppTextStyles.numeric.copyWith(
                        fontSize: 15,
                        color: hue,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 2),
              Text(
                subtitle.toUpperCase(),
                style: AppTextStyles.numericSmall.copyWith(
                  fontSize: 8.5,
                  letterSpacing: 0.13 * 8.5,
                  color: AppColors.textDimAA,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A vertical N-segment conditioning charge rune (Phase Vitality-2).
///
/// **Single visual primitive** shared by the summary rune strip
/// (`ConditioningChargeStrip`) and the cinematic B2 hero beat rune end-cap
/// (`B2BpTallyCut` / `B2ElevatedCut` / `B2CascadeCutWidget` hero). Both
/// surfaces render the SAME segmented-rune look so the charge reads
/// identically wherever it appears.
///
/// Segments fill **bottom-up** in the part's [hue]; lit segments carry a hue
/// glow, unlit segments read as a dim track. **Fill-only** — the rune only
/// ever lights up, it never drains or reddens (rebuild-not-deplete law).
///
/// The widget is dumb: the caller computes [litSegments] (already resolved
/// against whatever animation drives the surface) and the rune renders that
/// many lit segments. This keeps each surface free to drive its own timing —
/// the summary strip uses its own controller; the cinematic drives the count
/// off the B2 rank-bar fill window.
class ChargeRune extends StatelessWidget {
  const ChargeRune({
    super.key,
    required this.hue,
    required this.litSegments,
    this.totalSegments = defaultSegments,
    this.width = 16,
    this.height = 30,
    this.gap = 2,
  });

  /// The body-part identity hue lit segments paint in.
  final Color hue;

  /// Number of segments currently lit (bottom-up). Caller-computed and
  /// already clamped against the surface's animation.
  final int litSegments;

  /// Total number of segments in the rune.
  final int totalSegments;

  /// Rune box width.
  final double width;

  /// Rune box height.
  final double height;

  /// Inter-segment gap.
  final double gap;

  /// Canonical segment count (4) shared across surfaces.
  static const int defaultSegments = 4;

  @override
  Widget build(BuildContext context) {
    final lit = litSegments.clamp(0, totalSegments);
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          for (var i = totalSegments - 1; i >= 0; i--) ...[
            if (i < totalSegments - 1) SizedBox(height: gap),
            Expanded(
              child: _RuneSegment(lit: i < lit, hue: hue),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuneSegment extends StatelessWidget {
  const _RuneSegment({required this.lit, required this.hue});

  final bool lit;
  final Color hue;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: lit ? hue : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(2),
        boxShadow: lit
            ? [BoxShadow(color: hue.withValues(alpha: 0.5), blurRadius: 6)]
            : null,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Resolve a charge fraction `[0, 1]` to a lit-segment count.
///
/// `round()` so a part that is e.g. 60% charged lights segments
/// proportionally (2–3 of 4); a maxed part (>= 99.5%) lights all four.
/// Shared so the summary strip and the cinematic rune agree on the mapping.
int litSegmentsForFraction(
  double afterPct, {
  int totalSegments = ChargeRune.defaultSegments,
}) {
  return (afterPct.clamp(0.0, 1.0) * totalSegments).round().clamp(
    0,
    totalSegments,
  );
}
