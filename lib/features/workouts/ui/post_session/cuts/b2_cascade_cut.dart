import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../domain/post_session_choreographer.dart';
import '../../../domain/post_session_timing.dart';

/// Beat 2 cascade cut widget (Variant C — mockup §3, 3+ BPs trained).
///
/// Hero BP renders at the top in the dominant hue; secondary BPs cascade
/// in from the bottom as compact rows (140ms stagger each).
///
/// **Decoupling Rule 2.** Body-part labels arrive pre-resolved via
/// [bodyPartLabels] (`{BodyPart: localizedName}`), supplied by the screen
/// layer.
///
/// The widget consumes the choreographer's [B2CascadeCut] data class
/// directly (imported from the domain layer); the class names don't
/// collide because the widget is exposed as [B2CascadeCutWidget].
class B2CascadeCutWidget extends StatelessWidget {
  const B2CascadeCutWidget({
    super.key,
    required this.animation,
    required this.cut,
    required this.bodyPartLabels,
    required this.xpLabel,
    required this.truncatedPillLabel,
  });

  final Animation<double> animation;
  final B2CascadeCut cut;
  final Map<BodyPart, String> bodyPartLabels;
  final String xpLabel;

  /// Pre-resolved truncation pill label (e.g. "+2 mais"). The screen
  /// layer calls the AppLocalizations function and substitutes the
  /// count before passing the string down.
  /// Empty string when [B2CascadeCut.truncatedCount] is 0.
  final String truncatedPillLabel;

  @override
  Widget build(BuildContext context) {
    final heroHue =
        VitalityStateStyles.bodyPartColor[cut.heroBodyPart] ??
        AppColors.hotViolet;
    final heroLabel =
        bodyPartLabels[cut.heroBodyPart] ?? cut.heroBodyPart.dbValue;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b2-tally',
      label: 'Beat 2 · cascade · ${cut.cascadeRows.length + 1} body parts',
      child: ColoredBox(
        color: AppColors.abyss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: heroHue.withValues(alpha: 0.22)),
            CustomPaint(painter: _CascadeSlash(heroHue)),
            // Hero region: top half, fades in on first 0.25 of progress.
            Positioned(
              top: 36,
              left: 16,
              right: 16,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final slam = Curves.easeOut.transform(
                    animation.value.clamp(0.0, 0.25) / 0.25,
                  );
                  return Opacity(
                    opacity: slam.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          heroLabel.toUpperCase(),
                          style: AppTextStyles.label.copyWith(color: heroHue),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '+${cut.heroXp}',
                            style: AppTextStyles.celebrationSize(40).copyWith(
                              color: AppColors.textCream,
                              letterSpacing: 0.04 * 40,
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
                  );
                },
              ),
            ),
            // Cascade rows: bottom half, staggered fade-in. Each row gets a
            // dedicated phase window (140ms stagger / cut total ≈ 2.0s →
            // 0.07 of progress per row).
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final rows = <Widget>[];
                  final staggerPerRow =
                      PostSessionTiming.b2CascadeRowStagger.inMilliseconds /
                      PostSessionTiming.b2HoldCascade.inMilliseconds;
                  for (var i = 0; i < cut.cascadeRows.length; i++) {
                    final phaseStart = 0.30 + i * staggerPerRow;
                    final fade =
                        ((animation.value - phaseStart) / staggerPerRow).clamp(
                          0.0,
                          1.0,
                        );
                    final row = cut.cascadeRows[i];
                    final rowHue =
                        VitalityStateStyles.bodyPartColor[row.bodyPart] ??
                        AppColors.textDim;
                    final rowLabel =
                        bodyPartLabels[row.bodyPart] ?? row.bodyPart.dbValue;
                    rows.add(
                      Opacity(
                        opacity: fade,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Text(
                                rowLabel,
                                style: AppTextStyles.label.copyWith(
                                  color: rowHue,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '+${row.xpEarned}',
                                style: AppTextStyles.numericSmall.copyWith(
                                  color: AppColors.textCream,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (cut.truncatedCount > 0 && truncatedPillLabel.isNotEmpty) {
                    final phaseStart =
                        0.30 + cut.cascadeRows.length * staggerPerRow;
                    final fade =
                        ((animation.value - phaseStart) / staggerPerRow).clamp(
                          0.0,
                          1.0,
                        );
                    final label = truncatedPillLabel;
                    rows.add(
                      Opacity(
                        opacity: fade,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            label,
                            textAlign: TextAlign.right,
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.textDim,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
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

class _CascadeSlash extends CustomPainter {
  _CascadeSlash(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.30);
    final path = Path()
      ..moveTo(0, size.height * 0.46)
      ..lineTo(size.width, size.height * 0.36)
      ..lineTo(size.width, size.height * 0.52)
      ..lineTo(0, size.height * 0.60)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CascadeSlash old) => old.color != color;
}
