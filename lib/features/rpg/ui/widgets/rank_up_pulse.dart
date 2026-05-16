import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ring inner-size at rest scale (1.0). Computed as the 6dp body-part
/// dot diameter + ~5dp clearance on each side. The Transform.scale wraps
/// this at 1.0–1.5×, so the ring grows to ~24dp at peak.
const double _ringRestDiameter = 16;

/// Animated glow-ring overlay used during the 24h post-rank-up pulse
/// window (Phase 26b). Wraps the body-part dot; pulses its scale (1.0 →
/// 1.5) and outer ring alpha (15% → 35%) in a slow sine loop.
///
/// Gating (whether to render this at all) is the parent's responsibility —
/// see `RankUpPulseLocalStorage.isPulsing()`. This widget is unconditional
/// once mounted: it just wraps its [child] in an animated ring.
class RankUpPulse extends StatefulWidget {
  const RankUpPulse({super.key, required this.color, required this.child});

  /// Ring color — should match the body-part identity hue. The ring
  /// renders at 15% → 35% alpha so the dot underneath stays the primary
  /// signal.
  final Color color;

  /// The dot (or other small content) wrapped by the pulse ring. Rendered
  /// above the ring in the Stack so the dot stays the primary signal.
  final Widget child;

  @override
  State<RankUpPulse> createState() => _RankUpPulseState();
}

class _RankUpPulseState extends State<RankUpPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Sine ease-in-out cycle. NOTE: v=0 yields t=0.5 (sine midpoint),
        // NOT t=0 (rest state). The ring opens at scale=1.25 / alpha=0.25 on
        // first paint and reaches rest (t=0 → scale=1.0 / alpha=0.15) at
        // v=0.75. The perceptual difference is sub-second — using cosine
        // `(1 - cos(2π v)) / 2` would start at rest, but the ring is only
        // ever mounted post-rank-up where the user just saw a celebration
        // overlay, so the mid-pulse entry reads as a continuation rather
        // than a jump. Sine is kept for symmetry across the cycle.
        final t = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
        final scale = 1.0 + 0.5 * t;
        final alpha = 0.15 + 0.20 * t;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: alpha),
                    width: 1.5,
                  ),
                ),
                child: const SizedBox(
                  width: _ringRestDiameter,
                  height: _ringRestDiameter,
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
