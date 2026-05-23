import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../domain/post_session_choreographer.dart';

/// Beat 3 title-unlock cut. Hue-typed flood — NO white flash (reserved
/// for PR). Mockup §4 Title.
///
/// **Decoupling Rule 2.** Title name + sub-label arrive pre-resolved.
class B3TitleCutWidget extends StatelessWidget {
  const B3TitleCutWidget({
    super.key,
    required this.animation,
    required this.variant,
    required this.titleName,
    required this.subLabel,
    required this.eyebrowLabel,
    this.bodyPart,
  });

  final Animation<double> animation;
  final TitleCutVariant variant;
  final String titleName;
  final String subLabel;
  final String eyebrowLabel;

  /// Required when [variant] == [TitleCutVariant.bodyPartTyped].
  final BodyPart? bodyPart;

  @override
  Widget build(BuildContext context) {
    final hue = _floodHue();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b3-title',
      label: 'Beat 3 · title · $titleName',
      child: ColoredBox(
        color: AppColors.abyss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: hue.withValues(alpha: 0.36)),
            CustomPaint(painter: _TitleSlash(hue)),
            AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final fade = Curves.easeOut.transform(
                  animation.value.clamp(0.0, 0.30) / 0.30,
                );
                return Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          eyebrowLabel,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.label.copyWith(
                            color: hue,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          titleName,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.celebrationSize(28).copyWith(
                            color: variant == TitleCutVariant.characterLevel
                                ? AppColors.heroGold
                                : AppColors.textCream,
                            letterSpacing: 0.04 * 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          subLabel,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _floodHue() {
    switch (variant) {
      case TitleCutVariant.crossBuild:
        return AppColors.hotViolet;
      case TitleCutVariant.characterLevel:
        return AppColors.heroGold;
      case TitleCutVariant.bodyPartTyped:
        final bp = bodyPart;
        if (bp == null) return AppColors.hotViolet;
        return VitalityStateStyles.bodyPartColor[bp] ?? AppColors.hotViolet;
    }
  }
}

class _TitleSlash extends CustomPainter {
  _TitleSlash(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.32);
    final path = Path()
      ..moveTo(0, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.22)
      ..lineTo(size.width, size.height * 0.40)
      ..lineTo(0, size.height * 0.50)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TitleSlash old) => old.color != color;
}
