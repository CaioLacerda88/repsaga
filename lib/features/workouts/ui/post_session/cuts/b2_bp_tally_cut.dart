import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import 'charge_rune.dart';
import 'cut_slash.dart';

/// Beat 2 single-BP cut (Variant A — mockup §3) AND sequential cut
/// (Variant B). Same widget shape; the screen layer drives different
/// hold durations from [PostSessionTiming].
///
/// **Decoupling Rule 2 — data-only props.** Pre-resolved body-part name
/// is passed as `bodyPartLabel`; the widget never calls
/// `AppLocalizations.of(context)`.
class B2BpTallyCut extends StatelessWidget {
  const B2BpTallyCut({
    super.key,
    required this.animation,
    required this.bodyPart,
    required this.bodyPartLabel,
    required this.xpEarned,
    required this.xpLabel,
    required this.progressFractionAfter,
    required this.rankAfter,
    required this.isFirstAwakening,
    this.firstAwakeningSuffix,
    this.chargeFractionAfter,
    this.isChargeMax = false,
    this.chargeDeltaPercent,
    this.chargeDeltaLabel,
    this.chargeMaxLabel,
    this.chargeRechargedLabel,
    this.chargeAtPeakLabel,
  });

  final Animation<double> animation;
  final BodyPart bodyPart;
  final String bodyPartLabel;
  final int xpEarned;
  final String xpLabel;
  final double progressFractionAfter;
  final int rankAfter;

  /// True when this BP transitioned from "never trained" to "trained" this
  /// session. Mockup §5 State 1: appends " · Desperto" to the eyebrow.
  final bool isFirstAwakening;

  /// Pre-resolved " · Desperto" suffix when [isFirstAwakening] is true.
  /// Decoupled from this widget to keep the l10n decision at the screen
  /// layer.
  final String? firstAwakeningSuffix;

  /// Conditioning charge fraction after the session (`[0, 1]`), or `null`
  /// when this hero bp has no charge data. Null → the rune end-cap is NOT
  /// rendered and the beat looks exactly as before (the fuse is additive).
  /// Phase Vitality-2 S4.
  final double? chargeFractionAfter;

  /// True when the charge is held at peak (`afterPct >= 0.995`). The rune
  /// mounts pre-lit/held + the "MÁX" word renders in place of the `+N%`
  /// delta (mockup cinematic frame ii).
  final bool isChargeMax;

  /// The integer delta (percentage points) gained this session — used for
  /// the `▲ +N%` line. Sourced from the SINGLE charge model so it matches
  /// the summary strip. Ignored when [isChargeMax].
  final int? chargeDeltaPercent;

  /// Pre-localized `+N%` builder for the charge delta. Resolved by the
  /// screen layer (Decoupling Rule 2).
  final String Function(int pct)? chargeDeltaLabel;

  /// Pre-localized "MÁX" held word (already uppercased).
  final String? chargeMaxLabel;

  /// Pre-localized "Conditioning recharged" descriptive subtitle (gainer).
  final String? chargeRechargedLabel;

  /// Pre-localized "Conditioning at peak" descriptive subtitle (MÁX).
  final String? chargeAtPeakLabel;

  /// Whether the rune end-cap should render: charge data present AND the
  /// screen supplied the localized copy. When false the beat renders as
  /// before — additive fuse, never breaks the existing beat.
  bool get _hasCharge =>
      chargeFractionAfter != null &&
      chargeDeltaLabel != null &&
      chargeMaxLabel != null &&
      chargeRechargedLabel != null &&
      chargeAtPeakLabel != null;

  @override
  Widget build(BuildContext context) {
    final hue =
        VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.hotViolet;
    final eyebrow = isFirstAwakening && firstAwakeningSuffix != null
        ? '$bodyPartLabel$firstAwakeningSuffix'
        : bodyPartLabel;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b2-tally',
      label: 'Beat 2 · $bodyPartLabel · +$xpEarned XP',
      child: ColoredBox(
        color: AppColors.abyss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Hue flood — 22% alpha to read as flood, not solid hue.
            ColoredBox(color: hue.withValues(alpha: 0.22)),
            CustomPaint(painter: _DiagonalBpSlash(hue)),
            // Cluster: safearea-system-overlay-overlap — same class as bff76bd
            // + 0d0b4b7. Background flood stays edge-to-edge; content insets
            // respect system bars.
            Positioned.fill(
              child: SafeArea(
                minimum: const EdgeInsets.only(top: 12, bottom: 16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Eyebrow + XP slam.
                    AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final slam = Curves.easeOut.transform(
                          animation.value.clamp(0.0, 0.25) / 0.25,
                        );
                        return Center(
                          child: Opacity(
                            opacity: slam.clamp(0.0, 1.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  eyebrow.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.label.copyWith(
                                    color: hue,
                                    letterSpacing: 0.12 * 11,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '+$xpEarned',
                                    style: AppTextStyles.celebrationSize(36)
                                        .copyWith(
                                          color: AppColors.textCream,
                                          letterSpacing: 0.04 * 36,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  xpLabel,
                                  style: AppTextStyles.label.copyWith(
                                    color: AppColors.textDim,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Bottom progress bar fills as animation crosses 0.30 → 0.70.
                    // The conditioning rune end-cap (when present) lights its
                    // segments in the SAME beat/hue — one read, zero added
                    // cinematic length (Phase Vitality-2 S4).
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 40,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final fill = ((animation.value - 0.30) / 0.40).clamp(
                            0.0,
                            1.0,
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_hasCharge) ...[
                                B2ChargeEndCap(
                                  hue: hue,
                                  afterPct: chargeFractionAfter!,
                                  isMax: isChargeMax,
                                  fill: fill,
                                  deltaPercent: chargeDeltaPercent ?? 0,
                                  deltaLabel: chargeDeltaLabel!,
                                  maxLabel: chargeMaxLabel!,
                                  rechargedLabel: chargeRechargedLabel!,
                                  atPeakLabel: chargeAtPeakLabel!,
                                ),
                                const SizedBox(height: 13),
                              ],
                              ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 4,
                                      color: AppColors.xpTrack,
                                    ),
                                    FractionallySizedBox(
                                      widthFactor:
                                          (progressFractionAfter * fill).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                      child: Container(height: 4, color: hue),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'rank $rankAfter · ${(progressFractionAfter * 100).round()}%',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.numericSmall,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagonalBpSlash extends CustomPainter {
  _DiagonalBpSlash(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    paintCutSlash(canvas, size, color: color, alpha: 0.36);
  }

  @override
  bool shouldRepaint(covariant _DiagonalBpSlash old) => old.color != color;
}
