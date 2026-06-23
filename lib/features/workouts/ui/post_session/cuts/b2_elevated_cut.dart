import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../domain/post_session_timing.dart';
import 'charge_rune.dart';
import 'cut_slash.dart';

/// Beat 2 elevated rank-up cut (Variant D — mockup §3).
///
/// Two-phase animation against a single parent driver:
///   1. Phase A (0.0 → ~0.36): bar fills from 0 to 100% over 400ms.
///   2. Phase B (~0.40 → ~0.43): bar resets + brief flash (80ms).
///   3. Phase C (~0.43 → 1.0): rank number slams in at center, holds.
///
/// **Decoupling Rule 2.** Body-part label arrives pre-resolved.
class B2ElevatedCut extends StatelessWidget {
  const B2ElevatedCut({
    super.key,
    required this.animation,
    required this.bodyPart,
    required this.bodyPartLabel,
    required this.newRank,
    required this.rankCopy,
    this.chargeFractionAfter,
    this.isChargeMax = false,
    this.isChargeHeld = false,
    this.chargeDeltaPercent,
    this.chargeDeltaLabel,
    this.chargeMaxLabel,
    this.chargeHeldLabel,
    this.chargeRechargedLabel,
    this.chargeAtPeakLabel,
    this.chargeHeldSubtitle,
  });

  final Animation<double> animation;
  final BodyPart bodyPart;
  final String bodyPartLabel;
  final int newRank;

  /// Already-resolved "PEITO · RANK 19" copy (pre-localized + interpolated
  /// at the screen layer per `feedback_widget_l10n_parameterization`).
  final String rankCopy;

  /// Conditioning charge fraction after the session (`[0, 1]`), or `null`
  /// when this bp has no charge data. Null → no rune end-cap; the elevated
  /// beat renders exactly as before. The rune completes as the bar crosses
  /// 100% into the rank slam (mockup cinematic frame iii). Phase Vitality-2.
  final double? chargeFractionAfter;

  /// True when held at peak — rune pre-lit/held + MÁX word.
  final bool isChargeMax;

  /// True when held below peak — rune at current level + "Held" / "Mantido"
  /// word (never a dead `+0`).
  final bool isChargeHeld;

  /// Integer percentage-point charge delta for the `▲ +N%` line.
  final int? chargeDeltaPercent;

  /// Pre-localized `+N%` builder (Decoupling Rule 2).
  final String Function(int pct)? chargeDeltaLabel;

  /// Pre-localized "MÁX" held word.
  final String? chargeMaxLabel;

  /// Pre-localized "Held" / "Mantido" word (held-below-peak state).
  final String? chargeHeldLabel;

  /// Pre-localized "Conditioning recharged" subtitle (gainer).
  final String? chargeRechargedLabel;

  /// Pre-localized "Conditioning at peak" subtitle (MÁX).
  final String? chargeAtPeakLabel;

  /// Pre-localized "Conditioning held" subtitle (held state).
  final String? chargeHeldSubtitle;

  /// Whether the rune end-cap renders: charge data present AND copy supplied.
  bool get _hasCharge =>
      chargeFractionAfter != null &&
      chargeDeltaLabel != null &&
      chargeMaxLabel != null &&
      chargeHeldLabel != null &&
      chargeRechargedLabel != null &&
      chargeAtPeakLabel != null &&
      chargeHeldSubtitle != null;

  @override
  Widget build(BuildContext context) {
    final hue =
        VitalityStateStyles.bodyPartColor[bodyPart] ?? AppColors.hotViolet;

    // Phase windows expressed as a fraction of the elevated cut's hold
    // duration (1100ms). Bar fill = 400ms = 0.36. Flash = 80ms = 0.07.
    final barFillEnd =
        PostSessionTiming.b2ElevatedBarFill.inMilliseconds /
        PostSessionTiming.b2HoldElevated.inMilliseconds;
    final flashEnd =
        barFillEnd +
        PostSessionTiming.b2ElevatedRankFlash.inMilliseconds /
            PostSessionTiming.b2HoldElevated.inMilliseconds;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b2-tally',
      label: 'Beat 2 elevated · $rankCopy',
      child: ColoredBox(
        color: AppColors.abyss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: hue.withValues(alpha: 0.30)),
            CustomPaint(painter: _ElevatedSlash(hue)),
            // Cluster: safearea-system-overlay-overlap — same class as bff76bd
            // + 0d0b4b7. Background flood stays edge-to-edge; content insets
            // respect system bars.
            Positioned.fill(
              child: SafeArea(
                minimum: const EdgeInsets.only(top: 12, bottom: 16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Center rank slam — fades in during phase C.
                    AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final v = animation.value;
                        // Flash overlay (white at 80% alpha) during phase B.
                        final inFlash = v >= barFillEnd && v < flashEnd;
                        final slamPhase = v < flashEnd
                            ? 0.0
                            : ((v - flashEnd) / (1.0 - flashEnd)).clamp(
                                0.0,
                                1.0,
                              );
                        final slamCurve = Curves.easeOutBack.transform(
                          slamPhase.clamp(0.0, 1.0),
                        );
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // Phase B: 80ms cinematic 80%-alpha white flash —
                            // Concept B grammar primitive (mockup §3 elevated
                            // rank-up flash). Structurally white, not a palette
                            // color; intentional opt-out.
                            if (inFlash) _buildFlash(),
                            Center(
                              child: Opacity(
                                opacity: slamCurve.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: 0.85 + slamCurve * 0.15,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '$newRank',
                                      style: AppTextStyles.celebrationSize(80)
                                          .copyWith(
                                            color: AppColors.textCream,
                                            letterSpacing: 0.04 * 80,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    // Bar at bottom: fills 0→100% during phase A, then disappears
                    // during phase B+C.
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 60,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final v = animation.value;
                          // Bar visible only during phase A.
                          if (v >= barFillEnd) return const SizedBox.shrink();
                          final fill = (v / barFillEnd).clamp(0.0, 1.0);
                          return Stack(
                            children: [
                              Container(height: 4, color: AppColors.xpTrack),
                              FractionallySizedBox(
                                widthFactor: fill,
                                child: Container(height: 4, color: hue),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Bottom rank copy + conditioning rune end-cap — visible
                    // during phase C. The rune completes as the bar crosses
                    // 100% into the rank slam (mockup cinematic frame iii):
                    // the bar already reached full in phase A, so the rune
                    // mounts held-full and fades in with the rank copy.
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 30,
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final v = animation.value;
                          if (v < flashEnd) return const SizedBox.shrink();
                          final fade = ((v - flashEnd) / (1.0 - flashEnd))
                              .clamp(0.0, 1.0);
                          return Opacity(
                            opacity: fade,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_hasCharge) ...[
                                  B2ChargeEndCap(
                                    hue: hue,
                                    afterPct: chargeFractionAfter!,
                                    isMax: isChargeMax,
                                    isHeld: isChargeHeld,
                                    // Bar already crossed 100% in phase A; the
                                    // rune rides the rank slam fully completed.
                                    fill: 1.0,
                                    deltaPercent: chargeDeltaPercent ?? 0,
                                    deltaLabel: chargeDeltaLabel!,
                                    maxLabel: chargeMaxLabel!,
                                    heldLabel: chargeHeldLabel!,
                                    rechargedLabel: chargeRechargedLabel!,
                                    atPeakLabel: chargeAtPeakLabel!,
                                    heldSubtitle: chargeHeldSubtitle!,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Text(
                                  rankCopy,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.label.copyWith(
                                    color: AppColors.textCream,
                                    fontSize: 13,
                                    letterSpacing: 0.14 * 13,
                                  ),
                                ),
                              ],
                            ),
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

  /// Phase B 80%-alpha white flash. Extracted so the ignore marker can
  /// ride the literal directly — keeping the build method readable while
  /// the gate stays satisfied. See class-level docstring.
  Widget _buildFlash() {
    // ignore: hardcoded_color — Concept B 80ms cinematic flash
    return ColoredBox(color: Colors.white.withValues(alpha: 0.80));
  }
}

class _ElevatedSlash extends CustomPainter {
  _ElevatedSlash(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    paintCutSlash(canvas, size, color: color, alpha: 0.36);
  }

  @override
  bool shouldRepaint(covariant _ElevatedSlash old) => old.color != color;
}
