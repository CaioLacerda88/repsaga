import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';

/// Variant B — Full-Bleed Collars overlay (mockup §6 "Destaque" one-tap toggle).
///
/// Top + bottom diagonal collars frame an unobstructed middle photo zone
/// (~68%). The diagonals mirror the cinematic slash grammar (mockup §6
/// "diagonal cuts mirror the cinematic slash grammar"). Reserved for
/// high-drama sessions where the user toggles from default Variant A.
///
/// **Visual contract (mockup §6):**
///   * Top collar: 60dp tall, 95% abyss, `clip-path: polygon(0 0, 100% 0,
///     100% 100%, 0 75%)` — right edge full height, left edge 75%, diagonal
///     cut on bottom-left.
///   * Top content: BP eyebrow (body-part hue, Barlow Condensed 10sp 0.18em
///     tracked uppercase), class name (Rajdhani 700 14sp, textCream), and
///     REPSAGA wordmark right-aligned (Rajdhani 700 9sp +0.22em tracked).
///   * Bottom collar: 110dp tall, 95% abyss, `clip-path: polygon(0 25%,
///     100% 0, 100% 100%, 0 100%)` — left edge 25% from top, right edge 0,
///     diagonal cut on top.
///   * Bottom content: `!! Recorde` PR tag (Barlow Condensed 9sp 0.24em
///     tracked, heroGold) — drop on non-PR sessions; lift line (Rajdhani 700
///     24sp tabular textCream); row with BP-sub (Barlow Condensed 9sp 0.16em
///     tracked, body-part hue) + XP-sub (Rajdhani 600 13sp tabular textCream).
///
/// **Decoupling Rule 2.** All visible strings (`bpEyebrow`, `className`,
/// `wordmark`, `prTag`, `lift`, `bpSub`, `xpSub`) arrive pre-localized via
/// constructor params. NO `AppLocalizations.of(context)` here.
class ShareCardVariantB extends StatelessWidget {
  const ShareCardVariantB({
    super.key,
    required this.dominantHue,
    required this.bpEyebrow,
    required this.className,
    required this.wordmark,
    required this.lift,
    required this.bpSub,
    required this.xpSub,
    this.prTag,
  });

  /// Body-part hue — drives the top eyebrow color + the bottom BP-sub label.
  final Color dominantHue;

  /// Pre-localized body-part eyebrow text on the top collar, e.g. "Peito".
  /// Caller uppercases (the AppTextStyles.label token does not auto-upper).
  final String bpEyebrow;

  /// Pre-localized character class name on the top collar, e.g. "BULWARK".
  /// Caller uppercases.
  final String className;

  /// Wordmark string, e.g. "REPSAGA". Right-aligned at the top.
  final String wordmark;

  /// PR tag string for the bottom collar, e.g. "!! Recorde". `null` on
  /// non-PR sessions — drops the heroGold line entirely per mockup §6
  /// "drop it on non-PR sessions and lead with rank info instead".
  final String? prTag;

  /// Lift line on the bottom collar, e.g. "95kg × 5". On non-PR sessions
  /// the caller can populate this with a rank-up line ("Rank 19 · Peito")
  /// — the widget is agnostic to the semantic.
  final String lift;

  /// Body-part sub-line on the bottom-left row, e.g. "Supino · Peito".
  /// Renders in [dominantHue].
  final String bpSub;

  /// XP sub-line on the bottom-right row, e.g. "+618 XP".
  final String xpSub;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Top collar (60dp, diagonal cut bottom-left).
        Align(
          alignment: Alignment.topCenter,
          child: ClipPath(
            clipper: const _TopCollarClipper(),
            child: Container(
              key: const ValueKey('share-card-variant-b-top-collar'),
              height: 60,
              color: AppColors.abyss.withValues(alpha: 0.95),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        bpEyebrow,
                        style: AppTextStyles.label.copyWith(
                          fontSize: 10,
                          letterSpacing: 0.18 * 10,
                          color: dominantHue,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        className,
                        style: AppTextStyles.numeric.copyWith(
                          fontSize: 14,
                          letterSpacing: 0.04 * 14,
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Text(
                      wordmark,
                      style: AppTextStyles.numeric.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.22 * 9,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom collar (110dp, diagonal cut top).
        Align(
          alignment: Alignment.bottomCenter,
          child: ClipPath(
            clipper: const _BottomCollarClipper(),
            child: Container(
              key: const ValueKey('share-card-variant-b-bottom-collar'),
              height: 110,
              color: AppColors.abyss.withValues(alpha: 0.95),
              padding: const EdgeInsets.fromLTRB(14, 32, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (prTag != null)
                    Text(
                      prTag!,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.24 * 9,
                        // ignore: reward_accent — PR tag is the canonical
                        // reward; heroGold scarcity contract met.
                        color: AppColors.heroGold,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    lift,
                    style: AppTextStyles.numeric.copyWith(
                      fontSize: 24,
                      letterSpacing: -0.01 * 24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          bpSub,
                          style: AppTextStyles.label.copyWith(
                            fontSize: 9,
                            letterSpacing: 0.16 * 9,
                            color: dominantHue,
                          ),
                        ),
                      ),
                      Text(
                        xpSub,
                        style: AppTextStyles.numeric.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Top collar shape — `clip-path: polygon(0 0, 100% 0, 100% 100%, 0 75%)`.
/// Right side full height, left side 75%, diagonal cut on bottom-left.
class _TopCollarClipper extends CustomClipper<Path> {
  const _TopCollarClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height * 0.75)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// Bottom collar shape — `clip-path: polygon(0 25%, 100% 0, 100% 100%, 0 100%)`.
/// Left edge 25% from top, right edge from top, diagonal cut on top.
class _BottomCollarClipper extends CustomClipper<Path> {
  const _BottomCollarClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.25)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
