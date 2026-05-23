import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../domain/reward_tier.dart';

/// Beat 1 — the XP cut.
///
/// **Decoupling Rule 2 — data-only props.** Receives plain primitives plus
/// the resolved [copyLine] (already-localized at the screen layer per
/// `feedback_widget_l10n_parameterization`) and the parent's animation
/// `Listenable`. NO `AppLocalizations.of(context)`, NO Riverpod,
/// NO AnimationController of its own (Decoupling Rule 3 — single parent
/// controller).
///
/// **Visual grammar (mockup §2 Variants):** hard cut to abyss, diagonal
/// hotViolet slash, XP number slams from above (translateY -40 → 0, 180ms
/// overshoot), bottom copy line. The slam animation runs against the
/// parent's [animation] driver — when `tier.b1PreRoll` is non-zero, the
/// screen layer schedules the parent to dwell during the pre-roll before
/// the XP slam progress crosses 0 → 1.
class B1XpCutWidget extends StatelessWidget {
  const B1XpCutWidget({
    super.key,
    required this.animation,
    required this.tier,
    required this.totalXp,
    required this.copyLine,
    required this.xpLabel,
  });

  /// 0.0 → 1.0 progress driver from the parent's `AnimationController.view`.
  /// At 0.0 the XP number is offscreen above; at ~0.18 the slam reaches its
  /// resting position; from 0.18 to 1.0 the cut holds.
  final Animation<double> animation;

  /// Drives the hold duration + pre-roll. The screen layer is the timeline
  /// owner — this widget reads [tier] only for choreographic hints (e.g.
  /// the Max variant's pre-roll is visualized as a hairline-only abyss).
  final RewardTier tier;

  /// XP earned this session.
  final int totalXp;

  /// Pre-resolved copy line (e.g. "ENCERRADO.\nMAIS FORTE."). Already
  /// translated by the screen layer.
  final String copyLine;

  /// Pre-resolved "XP" sub-label. Localized at the screen layer.
  final String xpLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b1-xp',
      label: 'Beat 1 · XP slam · +$totalXp XP',
      child: ColoredBox(
        color: AppColors.abyss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Diagonal hotViolet slash — `clip-path: polygon` equivalent
            // per the Concept B grammar (`docs/post-session-screen-mockup-v2.html`
            // §0 anti-AI render rules: no box-shadow, no border-radius).
            const _DiagonalSlash(color: AppColors.hotViolet),
            // XP number slam (translateY -40 → 0, 180ms overshoot).
            AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final slam = Curves.easeOutBack.transform(
                  animation.value.clamp(0.0, 0.18) / 0.18,
                );
                final translateY = (1 - slam) * -40.0;
                final opacity = slam.clamp(0.0, 1.0);
                return Center(
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(0, translateY),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '+$totalXp',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.celebrationSize(48).copyWith(
                                color: AppColors.textCream,
                                letterSpacing: 0.04 * 48,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            xpLabel,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.textDim,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            // Bottom copy line.
            Positioned(
              left: 16,
              right: 16,
              bottom: 40,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final fade =
                      (animation.value.clamp(0.18, 0.45) - 0.18) / 0.27;
                  return Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: Text(
                      copyLine,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headline.copyWith(
                        color: AppColors.textCream,
                        fontSize: 22,
                        letterSpacing: 0.04 * 22,
                        height: 1.1,
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

/// Diagonal slash painter — implements the Concept B "diagonal hotViolet
/// slash" using a single `CustomPaint` so we don't reach for box-shadow or
/// border-radius (banned by mockup §0 anti-AI rules).
class _DiagonalSlash extends StatelessWidget {
  const _DiagonalSlash({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SlashPainter(color));
  }
}

class _SlashPainter extends CustomPainter {
  _SlashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.16);
    // Diagonal stripe across the cut from upper-left to lower-right.
    final path = Path()
      ..moveTo(0, size.height * 0.30)
      ..lineTo(size.width, size.height * 0.20)
      ..lineTo(size.width, size.height * 0.42)
      ..lineTo(0, size.height * 0.52)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SlashPainter old) => old.color != color;
}
