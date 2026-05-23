import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/reward_accent.dart';
import '../../../domain/post_session_choreographer.dart';
import '../../../domain/post_session_timing.dart';

/// Beat 3 PR cut — single or multi PR.
///
/// White flash (33ms) → gold flood → hero PR line. Multi-PR adds N pills
/// below the hero (max 3 + "+N mais"). Mockup §4 PR single + PR multi.
///
/// **Decoupling Rule 2.** Eyebrow + copy line arrive pre-resolved; the
/// multi-PR eyebrow with count is built at the screen layer (the widget
/// receives the already-substituted string).
///
/// **Concept B note (mockup §0):** the 33ms full-screen white flash is a
/// structural cinematic primitive (NOT a `BoxShadow`, NOT a glow). It is
/// rendered as a pure-white `ColoredBox` overlay during the flash window —
/// see [PostSessionTiming.b3PrWhiteFlash]. A future grammar gate must not
/// flag this as a glow.
class B3PrCutWidget extends StatelessWidget {
  const B3PrCutWidget({
    super.key,
    required this.animation,
    required this.data,
    required this.eyebrow,
    required this.copyLine,
    required this.pillLabels,
    required this.truncatedPillLabel,
  });

  final Animation<double> animation;
  final B3PrCutData data;
  final String eyebrow;
  final String copyLine;

  /// Pre-resolved pill row labels — one per PR pill, already
  /// interpolated by the screen layer. Length matches
  /// [B3PrCutData.pillRows]. Empty when the session is single-PR.
  final List<String> pillLabels;

  /// Pre-resolved truncation pill ("+1 more"). Empty string when
  /// `data.truncatedPillCount == 0`.
  final String truncatedPillLabel;

  @override
  Widget build(BuildContext context) {
    // Flash phase end as fraction of the cut's full duration.
    // White flash duration / (white flash + gold-flood hold).
    final totalMs =
        PostSessionTiming.b3PrWhiteFlash.inMilliseconds +
        PostSessionTiming.b3HoldPr.inMilliseconds;
    final flashEnd = PostSessionTiming.b3PrWhiteFlash.inMilliseconds / totalMs;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'post-session-b3-pr',
      label:
          'Beat 3 · PR · ${data.heroExerciseName} ${data.heroWeightKg}kg × ${data.heroReps}',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final v = animation.value;
          final inFlash = v < flashEnd;
          // Gold-flood phase progress (0..1 over remaining window).
          final goldPhase = v >= flashEnd
              ? ((v - flashEnd) / (1.0 - flashEnd))
              : 0.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.abyss),
              // 33ms cinematic full-screen white flash — Concept B grammar
              // primitive (see dartdoc above). Intentional palette opt-out:
              // structurally white, not a palette color.
              if (inFlash) _buildFlash(),
              if (!inFlash)
                // Full-screen gold flood — structural fill, no widget subtree
                // to wrap in a RewardAccent. Reads the sanctioned reward
                // color via the static alias per the same precedent as
                // `pr_celebration_screen.dart` (full-screen flash).
                // ignore: reward_accent — full-screen flood; no widget-subtree host for RewardAccent
                ColoredBox(color: RewardAccent.color.withValues(alpha: 0.50)),
              if (!inFlash) CustomPaint(painter: _GoldSlash(goldPhase)),
              if (!inFlash) _buildPrContent(context, goldPhase),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrContent(BuildContext context, double goldPhase) {
    // Cluster: safearea-system-overlay-overlap — same class as bff76bd
    // + 0d0b4b7. Background flood (white flash / gold ColoredBox / slash
    // painter) stays edge-to-edge above this widget; content insets respect
    // system bars here.
    return SafeArea(
      minimum: const EdgeInsets.only(top: 12, bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Eyebrow renders in heroGold via the canonical RewardAccent
            // widget-tree scope — DefaultTextStyle.merge supplies the color so
            // the Text below does not reference the token directly.
            Opacity(
              opacity: goldPhase.clamp(0.0, 1.0),
              child: RewardAccent(
                child: Text(
                  eyebrow,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 12,
                    letterSpacing: 0.14 * 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Opacity(
              opacity: goldPhase.clamp(0.0, 1.0),
              child: Column(
                children: [
                  Text(
                    data.heroExerciseName,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headline.copyWith(
                      color: AppColors.textCream,
                      fontSize: 18,
                      letterSpacing: 0.04 * 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // PR weight × reps — heroGold via RewardAccent (mockup §4:
                  // "B3 PR weight — Rajdhani 700 in heroGold").
                  RewardAccent(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_formatWeight(data.heroWeightKg)}kg × ${data.heroReps}',
                        style: AppTextStyles.celebrationSize(
                          34,
                        ).copyWith(letterSpacing: 0.04 * 34),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Pill rows fade in sequentially (200ms stagger inside the gold
            // window). Mockup §4 PR multi.
            if (data.pillRows.isNotEmpty || data.truncatedPillCount > 0)
              _buildPills(goldPhase),
            const Spacer(),
            Opacity(
              opacity: goldPhase.clamp(0.0, 1.0),
              child: Text(
                copyLine,
                textAlign: TextAlign.center,
                style: AppTextStyles.headline.copyWith(
                  color: AppColors.textCream,
                  fontSize: 16,
                  letterSpacing: 0.04 * 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPills(double goldPhase) {
    final pillStagger =
        PostSessionTiming.b3MultiPrPillStagger.inMilliseconds /
        PostSessionTiming.b3HoldPr.inMilliseconds;
    final widgets = <Widget>[];
    for (var i = 0; i < pillLabels.length; i++) {
      final phaseStart = 0.15 + i * pillStagger;
      final fade = ((goldPhase - phaseStart) / pillStagger).clamp(0.0, 1.0);
      widgets.add(
        Opacity(
          opacity: fade,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              pillLabels[i],
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textCream,
              ),
            ),
          ),
        ),
      );
    }
    if (data.truncatedPillCount > 0 && truncatedPillLabel.isNotEmpty) {
      final phaseStart = 0.15 + pillLabels.length * pillStagger;
      final fade = ((goldPhase - phaseStart) / pillStagger).clamp(0.0, 1.0);
      widgets.add(
        Opacity(
          opacity: fade,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              truncatedPillLabel,
              style: AppTextStyles.label.copyWith(
                color: AppColors.textDim,
                fontSize: 10,
              ),
            ),
          ),
        ),
      );
    }
    return Column(children: widgets);
  }

  /// 33ms cinematic full-screen white flash. Extracted so the ignore
  /// marker can ride the literal directly — keeps the build method
  /// readable while the gate stays satisfied. See class-level docstring.
  // ignore: hardcoded_color — Concept B 33ms cinematic flash
  static Widget _buildFlash() => const ColoredBox(color: Colors.white);

  static String _formatWeight(double w) {
    if (w == w.roundToDouble()) return w.toStringAsFixed(0);
    return w.toStringAsFixed(1);
  }
}

/// Adapter data class for the PR cut widget. Bridges the choreographer's
/// `B3PrCut` (a `PostSessionCut` subclass) to the widget's data needs.
class B3PrCutData {
  const B3PrCutData({
    required this.heroExerciseName,
    required this.heroWeightKg,
    required this.heroReps,
    required this.pillRows,
    required this.truncatedPillCount,
  });

  factory B3PrCutData.fromCut(B3PrCut cut) {
    return B3PrCutData(
      heroExerciseName: cut.heroExerciseName,
      heroWeightKg: cut.heroWeightKg,
      heroReps: cut.heroReps,
      pillRows: cut.pillRows,
      truncatedPillCount: cut.truncatedPillCount,
    );
  }

  final String heroExerciseName;
  final double heroWeightKg;
  final int heroReps;
  final List<PrPillRow> pillRows;
  final int truncatedPillCount;
}

class _GoldSlash extends CustomPainter {
  _GoldSlash(this.phase);
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    // CustomPainter has no BuildContext ancestor mid-paint; read the
    // sanctioned reward color via the static alias per the same precedent
    // as `progress_chart_section.dart` (FlDotPainter).
    final paint = Paint()
      // ignore: reward_accent — CustomPainter has no BuildContext for RewardAccent.of
      ..color = RewardAccent.color.withValues(
        alpha: 0.42 * phase.clamp(0.0, 1.0),
      );
    final path = Path()
      ..moveTo(0, size.height * 0.30)
      ..lineTo(size.width, size.height * 0.20)
      ..lineTo(size.width, size.height * 0.38)
      ..lineTo(0, size.height * 0.48)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GoldSlash old) => old.phase != phase;
}
