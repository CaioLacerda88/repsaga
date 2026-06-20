import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_theme.dart';

/// "Conditioning charged" debrief beat — a single aggregate teal charge bar
/// (Variant A, user-locked Phase Vitality PR 2 design).
///
/// Reports the honest server recompute of per-body-part vitality at save
/// time: the rune REBUILT UP toward its 7-day peak. Two-tone fill — a dim
/// teal `was` stub (the pre-finish aggregate charge) under a solid teal
/// `now` fill (the post-save aggregate). The `now` fill counts up RIGHTWARD
/// only from the `was` tick; it never shrinks, never reds out — this is a
/// rebuild signal, never a depleting HP bar.
///
/// **Identity, not per-BP color.** The eyebrow + bar fill are always teal
/// ([AppColors.bodyPartCardio] / `#22D3EE`) even on an all-strength session,
/// because the beat IS the Conditioning concept — teal is its identity here,
/// not a per-BP hue. Which-BP is already answered by the segmented bar +
/// per-BP rank-delta rows above. Keeps brand violet / heroGold off the bar
/// (scarcity contract intact).
///
/// **Slimmer sibling of [XpSegmentedBar].** Same hard-edged geometry family,
/// 8dp tall (vs the XP bar's 16dp) so it reads as a secondary state signal
/// under the primary XP bar, not a clone competing for weight.
///
/// **Decoupling Rule 2.** All copy is injected pre-localized.
class ConditioningChargeBar extends StatefulWidget {
  const ConditioningChargeBar({
    super.key,
    required this.beforeFraction,
    required this.afterFraction,
    required this.eyebrowLabel,
    required this.deltaLabel,
    required this.captionLabel,
    this.animate = true,
  });

  /// Aggregate charge fraction BEFORE the session, `[0, 1]`. Paints the
  /// dim `was` stub width — the count-up's starting tick.
  final double beforeFraction;

  /// Aggregate charge fraction AFTER the session, `[0, 1]`. The solid `now`
  /// fill counts up from [beforeFraction] to this width.
  final double afterFraction;

  /// Pre-localized "Conditioning charged" eyebrow (title-cased; uppercased
  /// here for the tracked-label register).
  final String eyebrowLabel;

  /// Pre-localized delta label, e.g. "+14%".
  final String deltaLabel;

  /// Pre-localized "recharges over ~7 days" caption.
  final String captionLabel;

  /// Drives the count-up. Disabled in tests that want to assert the final
  /// geometry without pumping the clock (the bar mounts at [afterFraction]).
  final bool animate;

  /// Bar height — deliberately slimmer than [XpSegmentedBar.barHeight] (8 vs
  /// 16dp) so the beat reads as a secondary signal. Public for tests.
  static const double barHeight = 8.0;

  /// Count-up duration. Public for tests pumping the animation.
  static const Duration countUpDuration = Duration(milliseconds: 700);

  @override
  State<ConditioningChargeBar> createState() => _ConditioningChargeBarState();
}

class _ConditioningChargeBarState extends State<ConditioningChargeBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _nowFill;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ConditioningChargeBar.countUpDuration,
    );
    _buildAnimation();
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  void _buildAnimation() {
    // The `now` fill grows from the `was` tick rightward to the after value
    // — never below `beforeFraction`, so the bar can only ever move right.
    final begin = widget.beforeFraction.clamp(0.0, 1.0);
    final end = widget.afterFraction.clamp(0.0, 1.0);
    _nowFill = Tween<double>(
      begin: begin,
      end: end < begin ? begin : end,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(covariant ConditioningChargeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beforeFraction != widget.beforeFraction ||
        oldWidget.afterFraction != widget.afterFraction) {
      _buildAnimation();
      if (widget.animate) {
        _controller
          ..reset()
          ..forward();
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wasFraction = widget.beforeFraction.clamp(0.0, 1.0);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'conditioning-charge-bar',
      label: '${widget.eyebrowLabel} · ${widget.deltaLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Eyebrow + delta on one baseline-aligned row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Single functional rune (⚡) — the only icon. No decorative
              // chrome (anti-generic-AI: no gradient, no shadow card).
              Text(
                '⚡ ${widget.eyebrowLabel.toUpperCase()}',
                style: AppTextStyles.label.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.22 * 11,
                  color: AppColors.bodyPartCardio,
                ),
              ),
              const Spacer(),
              Text(
                widget.deltaLabel,
                style: AppTextStyles.numeric.copyWith(
                  fontSize: 16,
                  letterSpacing: 0.3,
                  color: AppColors.bodyPartCardio,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(
              ConditioningChargeBar.barHeight / 2,
            ),
            child: SizedBox(
              height: ConditioningChargeBar.barHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fullWidth = constraints.maxWidth;
                  return AnimatedBuilder(
                    animation: _nowFill,
                    builder: (context, _) {
                      // `now` never recedes below `was` (the rebuild only
                      // ever grows the fill rightward — never a depleting
                      // bar). Two disjoint, non-overlapping segments so the
                      // two-tone reads cleanly: 0→was dim (already charged),
                      // was→now solid bright (rebuilt this session).
                      final now = _nowFill.value < wasFraction
                          ? wasFraction
                          : _nowFill.value;
                      final wasWidth = fullWidth * wasFraction;
                      final nowWidth = fullWidth * now;
                      return Stack(
                        children: [
                          // Track.
                          const Positioned.fill(
                            child: ColoredBox(color: AppColors.surface2),
                          ),
                          // Dim `was` segment (0 → was).
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: wasWidth,
                            child: ColoredBox(
                              color: AppColors.bodyPartCardio.withValues(
                                alpha: 0.28,
                              ),
                            ),
                          ),
                          // Solid `now` segment (was → now) — the count-up
                          // grows this sliver rightward.
                          Positioned(
                            left: wasWidth,
                            top: 0,
                            bottom: 0,
                            width: (nowWidth - wasWidth).clamp(0.0, fullWidth),
                            child: const ColoredBox(
                              color: AppColors.bodyPartCardio,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.captionLabel,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
