import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_muscle_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// BUG-013 (Cluster 3) — mini-flipbook of three cycling muscle sigils +
/// "+{N} ranks" label that surfaces inside [`CelebrationOverflowCard`]
/// when the cap-at-3 trims rank-ups.
///
/// **Why a flipbook instead of a static numeric chip:** the pre-Cluster-3
/// overflow card was just text ("3 more rank-ups — open Saga"). Per the
/// critic call (2026-05-02), a numeric-only card reads as a paperwork
/// notification, not as a hint that the user actually crossed three
/// progression thresholds. The cycling sigils mirror the rank-up sigil
/// vocabulary (same SVGs, same hotViolet tint) and signal "yes, real
/// progression happened — go look".
///
/// **Choreography:** three slots cycle through the muscle-sigil set with
/// a 200ms stagger between slots. Each slot holds a sigil for 600ms then
/// fades out as the next sigil fades in (200ms cross-fade). Sigils
/// chosen: chest → back → legs (the powerlifting big three; visually
/// distinct silhouettes that read at 20dp).
///
/// **Why this lived alongside `RankUpOverlay` historically:** they shared
/// the muscle-icon vocabulary. PR 29.5 retires `RankUpOverlay`
/// (replaced by `ThinFlashOverlay`), but the overflow card flipbook is a
/// distinct affordance with its own animation contract; it survives the
/// retirement and gets its own file.
class RankUpOverflowFlipbook extends StatefulWidget {
  const RankUpOverflowFlipbook({super.key, required this.overflowCount});

  /// Number of rank-ups that DIDN'T make the cap-at-3 cut. Surfaces in
  /// the "+{N} ranks" label.
  final int overflowCount;

  /// Per-slot stagger between sigil swaps. 200ms reads as deliberate
  /// rotation rather than fast cycling.
  static const Duration cycleStagger = Duration(milliseconds: 200);

  /// Hold + cross-fade duration per sigil per slot.
  static const Duration cycleDuration = Duration(milliseconds: 800);

  @override
  State<RankUpOverflowFlipbook> createState() => _RankUpOverflowFlipbookState();
}

class _RankUpOverflowFlipbookState extends State<RankUpOverflowFlipbook>
    with SingleTickerProviderStateMixin {
  /// Three sigils cycle through the slots — chest → back → legs. Visually
  /// distinct silhouettes that read at 20dp and cover the big-three
  /// powerlifting vocabulary the gym audience scans for.
  static const _cycleSigils = <String>[
    AppMuscleIcons.chest,
    AppMuscleIcons.back,
    AppMuscleIcons.legs,
  ];

  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: RankUpOverflowFlipbook.cycleDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      identifier: 'rank-up-overflow-flipbook',
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Three sigil slots — each phased by 200ms so the ripple reads
          // left-to-right.
          AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(_cycleSigils.length, (i) {
                  // Phase the per-slot opacity so the slot lights up
                  // 200ms after its left neighbour. Wrap into [0,1] via
                  // modulo so each slot completes a full cycle within
                  // the controller's repeat period.
                  final phase = (i * 200 / 800) % 1.0;
                  final t = (_ticker.value - phase) % 1.0;
                  // Triangle wave: 0 → 1 → 0 across the cycle so each
                  // slot pulses smoothly in and out without a pop.
                  // Cluster-3 review (2026-05-02): floor lowered from 0.4
                  // → 0.15 so "off" slots are clearly subordinate to the
                  // active slot — reads as left-to-right handoff rather
                  // than three icons pulsing in phase.
                  final opacity = (1 - (t * 2 - 1).abs()).clamp(0.15, 1.0);
                  return Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    child: Opacity(
                      opacity: opacity,
                      child: AppIcons.render(
                        _cycleSigils[i],
                        color: AppColors.hotViolet,
                        size: 20,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 8),
          // "+{N} ranks" — Rajdhani 700 24sp; the rank verb is
          // localized via `rankUpOverflowFlipbookLabel`.
          Text(
            l10n.rankUpOverflowFlipbookLabel(widget.overflowCount),
            style: AppTextStyles.headline.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textCream,
            ),
          ),
        ],
      ),
    );
  }
}
