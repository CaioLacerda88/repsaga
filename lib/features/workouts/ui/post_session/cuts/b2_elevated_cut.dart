import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../domain/post_session_timing.dart';

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
  });

  final Animation<double> animation;
  final BodyPart bodyPart;
  final String bodyPartLabel;
  final int newRank;

  /// Already-resolved "PEITO · RANK 19" copy (pre-localized + interpolated
  /// at the screen layer per `feedback_widget_l10n_parameterization`).
  final String rankCopy;

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
            // Center rank slam — fades in during phase C.
            AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final v = animation.value;
                // Flash overlay (white at 80% alpha) during phase B.
                final inFlash = v >= barFillEnd && v < flashEnd;
                final slamPhase = v < flashEnd
                    ? 0.0
                    : ((v - flashEnd) / (1.0 - flashEnd)).clamp(0.0, 1.0);
                final slamCurve = Curves.easeOutBack.transform(
                  slamPhase.clamp(0.0, 1.0),
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (inFlash) const ColoredBox(color: Color(0xCCFFFFFF)),
                    Center(
                      child: Opacity(
                        opacity: slamCurve.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.85 + slamCurve * 0.15,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$newRank',
                              style: AppTextStyles.celebrationSize(80).copyWith(
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
            // Bottom rank copy — visible during phase C.
            Positioned(
              left: 16,
              right: 16,
              bottom: 30,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final v = animation.value;
                  if (v < flashEnd) return const SizedBox.shrink();
                  final fade = ((v - flashEnd) / (1.0 - flashEnd)).clamp(
                    0.0,
                    1.0,
                  );
                  return Opacity(
                    opacity: fade,
                    child: Text(
                      rankCopy,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.textCream,
                        fontSize: 13,
                        letterSpacing: 0.14 * 13,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElevatedSlash extends CustomPainter {
  _ElevatedSlash(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.36);
    final path = Path()
      ..moveTo(0, size.height * 0.30)
      ..lineTo(size.width, size.height * 0.18)
      ..lineTo(size.width, size.height * 0.36)
      ..lineTo(0, size.height * 0.48)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ElevatedSlash old) => old.color != color;
}
