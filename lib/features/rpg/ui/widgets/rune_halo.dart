import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/reward_accent.dart';
import '../../models/vitality_state.dart';

/// Hero rune halo shown on the character-sheet header.
///
/// Wraps the app's hero sigil (`AppIcons.hero`) in one of four §8.4 visual
/// states. Each state ships its own visual differentiator (motion + color +
/// size) so the four reads as distinct intent at a glance, not a single ramp
/// of "more glow".
///
/// Performance contract:
///   * One [AnimationController] per active state — torn down when the
///     state changes (via `didUpdateWidget`) so off-screen tickers don't leak.
///   * Static states (Active) own no controller at all.
///   * No external assets (no Lottie / Rive) — everything is pure Flutter
///     paint + box decoration.
///
/// Sizes: the sigil renders at [size] (default 96 dp). The halo extends
/// roughly 30 dp past the sigil for the breathing/sweep beats; the widget
/// reserves [size] + 60 dp on each axis so the parent layout doesn't clip
/// the glow.
class RuneHalo extends StatefulWidget {
  const RuneHalo({super.key, required this.state, this.size = 96});

  /// Current vitality state — drives shape + motion + color of the halo.
  final VitalityState state;

  /// Diameter of the inner sigil. The widget itself reserves additional
  /// padding for the halo glow on each side.
  final double size;

  @override
  State<RuneHalo> createState() => _RuneHaloState();
}

class _RuneHaloState extends State<RuneHalo> with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncControllerToState();
  }

  @override
  void didUpdateWidget(covariant RuneHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncControllerToState();
    }
  }

  /// Idempotent: dispose the prior controller (if any) and start exactly
  /// one new controller appropriate for [widget.state]. Active state owns
  /// no controller at all.
  void _syncControllerToState() {
    _controller?.dispose();
    _controller = null;

    switch (widget.state) {
      case VitalityState.untested:
      case VitalityState.dormant:
        // Slow 8s rotation — sigil at 12% opacity, no glow ring.
        // Untested (peak == 0, never trained) shares the dormant treatment:
        // the rune is silent in both cases. Differentiation between the two
        // happens at the stats-table level (`—` vs `0%` percentage readout
        // + distinct marginalia copy), not on the character-sheet halo.
        _controller = AnimationController(
          vsync: this,
          duration: const Duration(seconds: 8),
        )..repeat();
      case VitalityState.fading:
        // 3s breathing pulse on the halo opacity.
        _controller = AnimationController(
          vsync: this,
          duration: const Duration(seconds: 3),
        )..repeat(reverse: true);
      case VitalityState.active:
        // Static — no animation.
        break;
      case VitalityState.radiant:
        // 4.5s sweep cycle for the painter highlight.
        _controller = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 4500),
        )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 26b: when the halo is used as the 36dp Saga-header sigil the
    // legacy +60dp glow-padding is visually disruptive. The static states
    // (active, dormant, untested) don't need outer glow room; the animated
    // states (fading, radiant) keep the legacy padding so their
    // breathing/sweep beats don't clip.
    final isCompact = widget.size < 48;
    final glowPad = isCompact ? 12 : 60;
    final containerSize = widget.size + glowPad;
    return SizedBox(
      width: containerSize,
      height: containerSize,
      child: Center(child: _buildForState()),
    );
  }

  Widget _buildForState() {
    switch (widget.state) {
      case VitalityState.untested:
      case VitalityState.dormant:
        // Same _DormantHalo treatment for both: rune silent, slow rotation,
        // 12% opacity. The differentiation between never-trained and
        // fully-decayed is carried by the stats-table readout, not the halo.
        return _DormantHalo(controller: _controller!, size: widget.size);
      case VitalityState.fading:
        return _FadingHalo(controller: _controller!, size: widget.size);
      case VitalityState.active:
        return _ActiveHalo(size: widget.size);
      case VitalityState.radiant:
        return _RadiantHalo(controller: _controller!, size: widget.size);
    }
  }
}

class _DormantHalo extends StatelessWidget {
  const _DormantHalo({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Transform.rotate(
          angle: controller.value * 2 * math.pi,
          child: Opacity(
            opacity: 0.12,
            child: AppIcons.render(
              AppIcons.hero,
              color: AppColors.textDim,
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _FadingHalo extends StatelessWidget {
  const _FadingHalo({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Pulse 0.6 → 1.0 → 0.6 on the halo glow alpha.
        final t = controller.value;
        final pulse = 0.6 + (math.sin(t * math.pi) * 0.4);
        return Container(
          width: size + 32,
          height: size + 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryViolet.withValues(alpha: 0.35 * pulse),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: AppIcons.render(
              AppIcons.hero,
              color: AppColors.primaryViolet,
              size: size,
            ),
          ),
        );
      },
    );
  }
}

class _ActiveHalo extends StatelessWidget {
  const _ActiveHalo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    // Phase 26b: active-state glow REMOVED. The previous two-layer
    // boxShadow read as "this is a special moment" but active is the
    // *steady state* — the user is on the path, not crossing a threshold.
    // Reserving glow for radiant (the reward state) restores the contrast
    // that made the four halo states distinguishable at a glance.
    return Container(
      width: size + 8,
      height: size + 8,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: Center(
        child: AppIcons.render(
          AppIcons.hero,
          color: AppColors.hotViolet,
          size: size,
        ),
      ),
    );
  }
}

/// Stateful so the §8.4 "single haptic on first paint of Radiant state"
/// contract is structurally guaranteed: the haptic fires from `initState`,
/// which runs exactly once per widget instance. Because [_RuneHaloState]
/// returns a fresh `_RadiantHalo` whenever the halo transitions INTO Radiant
/// (via the switch in `_buildForState`), the haptic always fires on the
/// transition without an explicit `_didFire` boolean to maintain.
class _RadiantHalo extends StatefulWidget {
  const _RadiantHalo({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  State<_RadiantHalo> createState() => _RadiantHaloState();
}

class _RadiantHaloState extends State<_RadiantHalo> {
  @override
  void initState() {
    super.initState();
    // §8.4: single haptic on first paint of Radiant state — the reward
    // signal that the user has reached peak conditioning. Fire once per
    // widget instance; the parent (`_RuneHaloState`) disposes and rebuilds
    // a new `_RadiantHalo` on every transition into Radiant, so this
    // naturally fires once per transition without a boolean flag.
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final controller = widget.controller;
    final enlargedSize = size * 1.10;
    // Radiant is the §8.4 reward signal (peak conditioning). All gold pixels
    // in this subtree resolve through `RewardAccent.of(context).color` so the
    // scarcity contract is honored in a single ancestor — sub-widgets that
    // can't read IconTheme/DefaultTextStyle (CustomPainter, SvgPicture via
    // AppIcons.render, BoxShadow) explicitly look up the scope.
    return RewardAccent(
      child: Builder(
        builder: (context) {
          final reward = RewardAccent.of(context)!.color;
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return SizedBox(
                width: size + 60,
                height: size + 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: enlargedSize + 36,
                      height: enlargedSize + 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: reward.withValues(alpha: 0.45),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      // Pure decorative glow — no children.
                    ),
                    CustomPaint(
                      size: Size(enlargedSize + 60, enlargedSize + 60),
                      painter: _RadiantSweepPainter(
                        progress: controller.value,
                        color: reward,
                      ),
                    ),
                    AppIcons.render(
                      AppIcons.hero,
                      color: reward,
                      size: enlargedSize,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Sweep arc that rotates around the rune at a fixed cadence. Single arc
/// (not multiple) so the eye reads it as a "highlight passing across" not a
/// busy loading spinner.
class _RadiantSweepPainter extends CustomPainter {
  _RadiantSweepPainter({required this.progress, required this.color});

  final double progress;

  /// Reward color resolved upstream from `RewardAccent.of(context)` — passed
  /// in rather than read from `AppColors.heroGold` so the scarcity contract
  /// is enforced at the widget-tree boundary, not duplicated here.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = progress * 2 * math.pi;
    const sweepAngle = math.pi / 6; // 30°

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.85)],
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RadiantSweepPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
