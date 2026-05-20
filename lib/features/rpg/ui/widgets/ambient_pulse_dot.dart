import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ring inner-size at rest scale (1.0). The 6dp body-part dot diameter +
/// ~5dp clearance on each side. `Transform.scale` wraps this — see the
/// per-mode amplitudes below.
const double _ringRestDiameter = 16;

/// Ambient pulse period — slow, low-attention. ~3.2s for one full cycle.
const Duration _ambientPeriod = Duration(milliseconds: 3200);

/// Emphasized (rank-up) pulse period — fast, high-attention. Matches the
/// previous `RankUpPulse` 1.6s cadence.
const Duration _emphasizedPeriod = Duration(milliseconds: 1600);

/// Ambient mode amplitudes — subtle ring (~15% scale growth, low alpha).
const double _ambientScaleAmplitude = 0.15;
const double _ambientAlphaMin = 0.08;
const double _ambientAlphaMax = 0.18;

/// Emphasized mode amplitudes — preserved from the original `RankUpPulse`
/// (1.0 → 1.5 scale, 0.15 → 0.35 alpha).
const double _emphasizedScaleAmplitude = 0.5;
const double _emphasizedAlphaMin = 0.15;
const double _emphasizedAlphaMax = 0.35;

/// Animated glow-ring overlay that wraps a body-part dot with a continuous
/// pulse. Two tiers controlled by [emphasized]:
///
///   * `emphasized: false` — **ambient baseline** (Phase 27 L8). Every
///     trained body-part dot renders this so the user reads pulsing as
///     "this part is active" rather than puzzling over a single static
///     dot. Subtle 15% scale growth, low alpha, 3.2s period.
///   * `emphasized: true` — **rank-up emphasis** (Phase 26b). Bigger
///     amplitude (50% scale) + faster period (1.6s). Carries the same
///     visual weight as the original `RankUpPulse` it replaced.
///
/// **Single widget, two modes (vs. two separate widgets).** Gating two
/// different subtrees on the rank-up boolean caused animation discontinuity
/// + gesture-arena reshuffling when the 24h window flipped. One widget
/// with a runtime-switched amplitude transitions cleanly: when [emphasized]
/// changes, the controller's `duration` is rebound in `didUpdateWidget` so
/// the next cycle picks up the new period without remounting the subtree.
///
/// **Gating (whether to mount this at all) is the parent's responsibility.**
/// Untrained body parts must NOT mount this widget — `BodyPartRankRow`
/// renders a plain dot for those. This widget assumes it's only ever
/// instantiated for trained parts.
///
/// **Performance.** Wrapped in [RepaintBoundary] so the per-frame paint
/// invalidates a tiny region per dot, not the whole row. 6 trained dots ×
/// 60 fps × tiny region = trivial CPU.
class AmbientPulseDot extends StatefulWidget {
  const AmbientPulseDot({
    super.key,
    required this.color,
    required this.size,
    this.emphasized = false,
  });

  /// Dot color — also used for the ring border at low alpha. Should match
  /// the body-part identity hue.
  final Color color;

  /// Diameter of the inner solid dot. Body-part rows pass 6dp.
  final double size;

  /// `false` → ambient baseline pulse (every trained dot).
  /// `true` → rank-up emphasis (within the 24h post-rank-up window).
  final bool emphasized;

  @override
  State<AmbientPulseDot> createState() => _AmbientPulseDotState();
}

class _AmbientPulseDotState extends State<AmbientPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _periodFor(widget.emphasized),
  )..repeat();

  static Duration _periodFor(bool emphasized) =>
      emphasized ? _emphasizedPeriod : _ambientPeriod;

  @override
  void didUpdateWidget(covariant AmbientPulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emphasized != widget.emphasized) {
      // Rebind duration so the next sine cycle samples at the new period.
      // We keep the current `value` so the ring doesn't snap back to t=0 —
      // it continues smoothly into the new cadence.
      _controller.duration = _periodFor(widget.emphasized);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaleAmplitude = widget.emphasized
        ? _emphasizedScaleAmplitude
        : _ambientScaleAmplitude;
    final alphaMin = widget.emphasized ? _emphasizedAlphaMin : _ambientAlphaMin;
    final alphaMax = widget.emphasized ? _emphasizedAlphaMax : _ambientAlphaMax;

    final dot = SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      ),
    );

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // Sine cycle — symmetric across the period so the open/close
          // halves match (no perceptual stutter at the loop point).
          final t = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
          final scale = 1.0 + scaleAmplitude * t;
          final alpha = alphaMin + (alphaMax - alphaMin) * t;
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
        child: dot,
      ),
    );
  }
}
