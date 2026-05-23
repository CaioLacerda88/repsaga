import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/reward_accent.dart';
import '../../../../rpg/models/body_part.dart';
import '../../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../domain/post_session_choreographer.dart';

/// Beat 3 title-unlock cut. Hue-typed flood — NO white flash (reserved
/// for PR). Mockup §4 Title.
///
/// **Decoupling Rule 2.** Title name + sub-label arrive pre-resolved.
///
/// **Reward-scarcity note.** The `characterLevel` variant renders a
/// heroGold flood (mockup §4: "Character-level milestone title → heroGold
/// flood") — body-part-typed and cross-build variants use violet/body-part
/// hues. heroGold emissions are quarantined to the reward-tier register
/// per `RewardAccent`; the typographic gold accent on the title text goes
/// through the widget-tree scope, and the structural fill/painter sinks
/// read `RewardAccent.color` directly with an `ignore: reward_accent`
/// marker (same precedent as `pr_celebration_screen.dart`).
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
    final isCharacterLevel = variant == TitleCutVariant.characterLevel;
    final titleText = Text(
      titleName,
      textAlign: TextAlign.center,
      style: AppTextStyles.celebrationSize(28).copyWith(
        color: isCharacterLevel ? null : AppColors.textCream,
        letterSpacing: 0.04 * 28,
      ),
    );
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
                            // Character-level milestone title renders in heroGold
                            // via the RewardAccent widget-tree scope (mockup §4).
                            // Body-part-typed and cross-build variants stay in
                            // textCream (the hue is signaled by the flood
                            // background + slash painter, not by the title color).
                            if (isCharacterLevel)
                              RewardAccent(child: titleText)
                            else
                              titleText,
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
              ),
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
        // Structural sink (consumed by ColoredBox fill + _TitleSlash painter
        // + eyebrow color); no widget subtree to wrap in RewardAccent. Same
        // precedent as `pr_celebration_screen.dart` (full-screen flash).
        // ignore: reward_accent — structural flood; no widget-subtree host for RewardAccent
        return RewardAccent.color;
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
