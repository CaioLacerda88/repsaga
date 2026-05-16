import 'dart:math' as math;

import 'package:flutter/material.dart';

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
        // 0..1 → ease in/out via sine.
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
                child: const SizedBox(width: 16, height: 16),
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
