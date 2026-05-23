import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Beat 3 class-change cut. Full Concept B 1.5s ceremony.
///
/// Mockup §4 Class change:
///   - hotViolet flood, slash, "Classe Desperta" eyebrow.
///   - BULWARK slam in Rajdhani 42, "DESPERTOU." subline at 13px tracked.
///   - Italic class flavor at the bottom.
///
/// **Decoupling Rule 2.** Class name + subline + flavor arrive pre-resolved.
class B3ClassChangeCutWidget extends StatelessWidget {
  const B3ClassChangeCutWidget({
    super.key,
    required this.animation,
    required this.className,
    required this.eyebrowLabel,
    required this.subLabel,
    required this.flavorLine,
  });

  final Animation<double> animation;
  final String className;
  final String eyebrowLabel;
  final String subLabel;
  final String flavorLine;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b3-class-change',
      label: 'Beat 3 · class change · $className',
      child: ColoredBox(
        color: AppColors.abyss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppColors.hotViolet.withValues(alpha: 0.40)),
            CustomPaint(painter: _ClassSlash()),
            // Cluster: safearea-system-overlay-overlap — same class as bff76bd
            // + 0d0b4b7. Background flood stays edge-to-edge; content insets
            // respect system bars.
            Positioned.fill(
              child: SafeArea(
                minimum: const EdgeInsets.only(top: 12, bottom: 16),
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final fade = Curves.easeOut.transform(
                      animation.value.clamp(0.0, 0.30) / 0.30,
                    );
                    final flavorFade = ((animation.value - 0.50) / 0.30).clamp(
                      0.0,
                      1.0,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Opacity(
                            opacity: fade.clamp(0.0, 1.0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    eyebrowLabel,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.hotViolet,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      className,
                                      textAlign: TextAlign.center,
                                      style: AppTextStyles.celebrationSize(42)
                                          .copyWith(
                                            color: AppColors.textCream,
                                            letterSpacing: 0.04 * 42,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    subLabel,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.hotViolet,
                                      fontSize: 13,
                                      letterSpacing: 0.14 * 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 40,
                          child: Opacity(
                            opacity: flavorFade.clamp(0.0, 1.0),
                            child: Text(
                              flavorLine,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textDim,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassSlash extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.hotViolet.withValues(alpha: 0.40);
    final path = Path()
      ..moveTo(0, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.22)
      ..lineTo(size.width, size.height * 0.40)
      ..lineTo(0, size.height * 0.50)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ClassSlash old) => false;
}
