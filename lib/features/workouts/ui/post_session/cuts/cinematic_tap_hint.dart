import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';

/// Discoverability affordance for the tap-anywhere-to-advance gesture on
/// [PostSessionScreen] (PR 30a UX pass, 2026-05-23).
///
/// The gesture itself is already wired via the screen's outer
/// `GestureDetector(onTap:)` — what was missing was the affordance that
/// the gesture exists. On-device user feedback: the cinematic plays past
/// without any indication the screen is interactive.
///
/// **Concept B grammar (mockup §0):** no ripple chrome, no fills, no
/// borders. A subtle pulsing chevron-right at low alpha pinned to the
/// bottom-right corner — present enough to be discoverable, restrained
/// enough not to compete with the cut content.
///
/// **Lifecycle ownership.** The hint is composed into B1 only by
/// [PostSessionScreen] under three composed predicates:
///   * `!_userHasTapped` — first tap retires the affordance permanently
///   * `cutIndex == 0` — never reappears on later beats
///   * `!_tapHintExpired` — a one-shot 2000ms `Future.delayed` in initState
///     retires the affordance even if the user never taps
///
/// All three predicates are owned by the screen's State; this widget is
/// purely a "render the pulsing chevron" leaf. It does NOT subscribe to
/// the cinematic's animation controller (Decoupling Rule 2 — leaf is
/// l10n + state-harness-free) and runs its own short pulse controller.
class CinematicTapHint extends StatefulWidget {
  const CinematicTapHint({super.key});

  @override
  State<CinematicTapHint> createState() => _CinematicTapHintState();
}

class _CinematicTapHintState extends State<CinematicTapHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _alpha;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    // 1.0 → 1.15 scale pulse + 0.45 → 0.85 alpha pulse against the cut.
    // Curve.easeInOut keeps the pulse natural-feeling at the endpoints.
    _scale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _alpha = Tween<double>(
      begin: 0.45,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: SafeArea(
        // Don't shrink the cut canvas — only inset our own hint by the
        // bottom system region so the chevron clears gesture-nav handles.
        top: false,
        left: false,
        right: false,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Opacity(
                opacity: _alpha.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textDim,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
