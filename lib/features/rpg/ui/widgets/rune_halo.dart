import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/reward_accent.dart';
import '../../../profile/ui/widgets/profile_avatar.dart';
import '../../models/vitality_state.dart';

/// Hero rune halo shown on the character-sheet header and Home card.
///
/// Wraps the user's `ProfileAvatar` (compact mode — gradient disc /
/// monogram / uploaded photo, no badge or scrim) in one of four §8.4
/// visual states. Each state ships its own visual differentiator
/// (motion + color + size) so the four read as distinct intent at a
/// glance, not a single ramp of "more glow".
///
/// **Identity substitution (Phase 32 PR 32e scope add):** the previous
/// abstract "small man" rune figure was retired — the avatar's 3-tier
/// fallback (photo > BP-gradient monogram > Day-0 radial) handles every
/// user state cleanly. The glow-state machine (dormant / fading / active
/// / radiant) stays unchanged — that's the load-bearing RPG signal. The
/// avatar at the center is the user's *current* identity render; the
/// ring around it is what state-of-conditioning that identity is in.
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

  /// Compact outer-padding threshold (Phase 26b, bumped Phase 32 PR 32e).
  /// Below this size, static states use the compact glow-pad; at or above,
  /// the legacy reservation applies. Originally pinned to Material's 48dp
  /// tap-target floor for the 36dp Saga sigil; bumped to 52dp so the new
  /// tappable-avatar sizes (48dp Home + 44dp Saga, Phase 32 PR 32e scope
  /// add) stay on the compact glow-pad branch instead of falling back to
  /// the legacy 60dp pad for dormant + active. The `isAnimatedState` guard
  /// in `build` already bypasses compact for fading + radiant — those
  /// animated states keep the full reservation so their breathing pulse +
  /// sweep arc don't clip.
  // 52dp keeps 48dp Home + 44dp Saga avatars on the compact path;
  // fading/radiant already bypass via isAnimatedState.
  static const double _compactSizeThreshold = 52;

  /// Compact glow-pad for static states at sub-48dp sizes (Phase 26b).
  /// Reserves 6dp on each axis so the sigil has breathing room without
  /// the legacy 30dp glow halo.
  static const double _compactGlowPad = 12;

  /// Legacy glow-pad for animated states (fading breathing pulse, radiant
  /// sweep arc) and any non-compact instance. Reserves 30dp on each axis
  /// so the painter sub-widgets don't clip.
  static const double _legacyGlowPad = 60;

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
    // legacy +60dp glow-padding is visually disruptive. Only the static
    // states (active, dormant, untested) qualify for the compact pad —
    // animated states (fading, radiant) keep the full reservation so their
    // breathing pulse + sweep arc don't clip.
    final isAnimatedState =
        widget.state == VitalityState.fading ||
        widget.state == VitalityState.radiant;
    final isCompact = widget.size < _compactSizeThreshold && !isAnimatedState;
    final glowPad = isCompact ? _compactGlowPad : _legacyGlowPad;
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
    // Rotation wraps ONLY the dim glow shell, never the avatar — a
    // spinning user photo or monogram is jarring. The avatar sits
    // stationary at the centre; the dim ring drifts around it at the
    // 8s cadence.
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Transform.rotate(
              angle: controller.value * 2 * math.pi,
              child: Opacity(
                opacity: 0.12,
                child: Container(
                  width: size + 8,
                  height: size + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.textDim, width: 1.5),
                  ),
                ),
              ),
            );
          },
        ),
        ProfileAvatar(size: size, compact: true),
      ],
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
        // Pulse 0.6 → 1.0 → 0.6 on the halo glow alpha. Only the ring
        // breathes — the avatar at the centre is stationary, so the
        // user's identity stays steady while the *state* signals decay.
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
          child: Center(child: ProfileAvatar(size: size, compact: true)),
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
    //
    // The +8 padding is breathing room around the sigil, NOT glow space —
    // a SizedBox makes that intent explicit (a Container with no
    // decoration would suggest there's a shape/border/shadow to read).
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Center(child: ProfileAvatar(size: size, compact: true)),
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
                    // Avatar carries the user identity unchanged; the
                    // gold reward signal lives in the sweep arc + bloom
                    // around it. Applying a gold tint to a photo (or a
                    // body-part-hue gradient) would visually corrupt
                    // the identity render. Phase 32 PR 32e — scope add.
                    ProfileAvatar(size: enlargedSize, compact: true),
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
