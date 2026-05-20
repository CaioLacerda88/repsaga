import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_muscle_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reward_accent.dart';
import '../../models/body_part.dart';
import '../widgets/body_part_localization.dart';

/// Direction B "Rune Stamp" rank-up overlay (Phase 18c).
///
/// Choreography (locked in WIP.md, 1100ms total):
///   * 0–200ms — rune sigil ignites `textDim @ 0.3` → `heroGold @ 1.0`
///     (`Curves.easeIn`); card scales 0.88 → 1.0 in 220ms `easeOutBack`.
///   * 200–500ms — sigil holds heroGold; outer `BoxShadow` grows blur 0→24,
///     spread 0→6 in `heroGold @ 0.5`.
///   * 500–900ms — sigil settles `heroGold` → `hotViolet @ 0.9`
///     (`Curves.decelerate`).
///   * 900–1100ms — shadow color cross-fades `heroGold @ 0.5` → `hotViolet
///     @ 0.45` (matches RuneHalo Active steady state for visual continuity).
///
/// Haptic: `mediumImpact()` at t=200ms (peak gold). Heavier than the
/// RuneHalo `lightImpact` because rank-up is a permanent rank transition.
///
/// All `heroGold` pixels flow through [RewardAccent] per the scarcity
/// contract.
///
/// **Auto-advance:** the overlay does not dismiss itself. The runtime
/// scheduler in `ActiveWorkoutNotifier` (Phase 18c stage 7) inserts a
/// 200ms gap between overlays and advances after 1.1s; this widget is a
/// pure presentation surface that runs its tween once.
class RankUpOverlay extends StatefulWidget {
  const RankUpOverlay({
    super.key,
    required this.bodyPart,
    required this.newRank,
  });

  final BodyPart bodyPart;
  final int newRank;

  @override
  State<RankUpOverlay> createState() => _RankUpOverlayState();
}

class _RankUpOverlayState extends State<RankUpOverlay>
    with TickerProviderStateMixin {
  /// Master timeline driving the multi-stage choreography.
  late final AnimationController _timeline;

  /// Card entry scale tween (0.88 → 1.0 over the first 220ms).
  late final Animation<double> _cardScale;

  /// Sigil ignition (0–200ms).
  late final Animation<Color?> _ignite;

  /// Sigil settle (500–900ms).
  late final Animation<Color?> _settle;

  /// Shadow blur during the gold-hold beat (200–500ms).
  late final Animation<double> _shadowBlur;
  late final Animation<double> _shadowSpread;

  /// Shadow color cross-fade (900–1100ms).
  late final Animation<double> _shadowFade;

  /// Backdrop dim alpha (0–180ms easeOut).
  late final Animation<double> _backdrop;

  /// Structural one-fire guard for the t=200ms haptic — set true the first
  /// time the timeline crosses 200/1100. We don't use a status listener +
  /// boolean for the haptic because there's no tween-status event at an
  /// arbitrary mid-point; instead we read the controller's elapsed time
  /// from a scheduling callback.
  bool _peakHapticFired = false;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // 0-220ms: card scale 0.88 → 1.0 with easeOutBack (slight overshoot).
    _cardScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(0, 220 / 1100, curve: Curves.easeOutBack),
      ),
    );

    // 0-180ms: backdrop dim 0 → 1.
    _backdrop = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(0, 180 / 1100, curve: Curves.easeOut),
    );

    // 0-200ms: textDim @ 0.3 → heroGold ignition.
    _ignite =
        ColorTween(
          begin: AppColors.textDim.withValues(alpha: 0.3),
          // ignore: reward_accent — ColorTween end value drives the rune-stamp ignition; tween targets cannot route through RewardAccent.
          end: AppColors.heroGold,
        ).animate(
          CurvedAnimation(
            parent: _timeline,
            curve: const Interval(0, 200 / 1100, curve: Curves.easeIn),
          ),
        );

    // 200-500ms: shadow blur 0 → 24, spread 0 → 6 (gold hold beat).
    _shadowBlur = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(200 / 1100, 500 / 1100, curve: Curves.easeOut),
      ),
    );
    _shadowSpread = Tween<double>(begin: 0, end: 6).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(200 / 1100, 500 / 1100, curve: Curves.easeOut),
      ),
    );

    // 500-900ms: heroGold → hotViolet settle.
    _settle =
        ColorTween(
          // ignore: reward_accent — ColorTween begin value is the gold-hold beat; tween sources cannot route through RewardAccent.
          begin: AppColors.heroGold,
          end: AppColors.hotViolet.withValues(alpha: 0.9),
        ).animate(
          CurvedAnimation(
            parent: _timeline,
            curve: const Interval(
              500 / 1100,
              900 / 1100,
              curve: Curves.decelerate,
            ),
          ),
        );

    // 900-1100ms: shadow color fade heroGold → hotViolet.
    _shadowFade = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(900 / 1100, 1.0, curve: Curves.linear),
    );

    _timeline.addListener(_onTick);
    _timeline.forward();
  }

  void _onTick() {
    // mediumImpact at t=200ms peak gold. Idempotent via the boolean — the
    // controller listener fires per-frame, so without the guard we'd haptic
    // ~12 times. The boolean is structural one-fire, not a "ran-once flag":
    // the only way to re-fire is to mount a new RankUpOverlay instance.
    if (!_peakHapticFired && _timeline.value * 1100 >= 200) {
      _peakHapticFired = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _timeline.removeListener(_onTick);
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bodyPartName = localizedBodyPartName(
      widget.bodyPart,
      l10n,
    ).toUpperCase();

    return AnimatedBuilder(
      animation: _timeline,
      builder: (context, _) {
        // The sigil color is whichever stage is live: ignite (0-200), heroGold
        // hold (200-500), settle (500-900), or final hotViolet (900+).
        final t = _timeline.value * 1100;
        final Color sigilColor;
        if (t < 200) {
          // ignore: reward_accent — null-safety fallback for the ignite ColorTween; the animated value already routes through the rune-stamp reward surface.
          sigilColor = _ignite.value ?? AppColors.heroGold;
        } else if (t < 500) {
          // ignore: reward_accent — gold-hold beat (200-500ms) is the rank-up reward emission; computed Color value cannot route through RewardAccent.
          sigilColor = AppColors.heroGold;
        } else if (t < 900) {
          sigilColor = _settle.value ?? AppColors.hotViolet;
        } else {
          sigilColor = AppColors.hotViolet.withValues(alpha: 0.9);
        }

        // Shadow color cross-fade from heroGold @ 0.5 to hotViolet @ 0.45
        // during the 900-1100ms tail.
        final shadowColor = Color.lerp(
          // ignore: reward_accent — Color.lerp source is the rank-up halo emission; lerp endpoints cannot route through RewardAccent.
          AppColors.heroGold.withValues(alpha: 0.5),
          AppColors.hotViolet.withValues(alpha: 0.45),
          _shadowFade.value,
        )!;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Backdrop dim (abyss @ 0.72, fading in over 0-180ms).
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: AppColors.abyss.withValues(
                    alpha: 0.72 * _backdrop.value,
                  ),
                ),
              ),
            ),
            // Card. Semantics identifier lets Playwright detect the overlay.
            Semantics(
              identifier: 'rank-up-overlay',
              child: Transform.scale(
                scale: _cardScale.value,
                child: _RankUpCard(
                  bodyPartName: bodyPartName,
                  rank: widget.newRank,
                  sigilAsset: _sigilAssetFor(widget.bodyPart),
                  sigilColor: sigilColor,
                  shadowBlur: _shadowBlur.value,
                  shadowSpread: _shadowSpread.value,
                  shadowColor: shadowColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RankUpCard extends StatelessWidget {
  const _RankUpCard({
    required this.bodyPartName,
    required this.rank,
    required this.sigilAsset,
    required this.sigilColor,
    required this.shadowBlur,
    required this.shadowSpread,
    required this.shadowColor,
  });

  final String bodyPartName;
  final int rank;
  final String sigilAsset;
  final Color sigilColor;
  final double shadowBlur;
  final double shadowSpread;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // Overlay card border is part of the gold ignition moment.
          // RewardAccent forwards DefaultTextStyle only, not BoxDecoration.
          // The whole RankUpOverlay is the rank-up reward surface so direct
          // heroGold use is the contract here.
          // ignore: reward_accent — see comment above (RankUpOverlay is a reward surface).
          color: AppColors.heroGold.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sigil with the dynamic gold-shadow halo.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: shadowBlur,
                  spreadRadius: shadowSpread,
                ),
              ],
            ),
            child: Center(
              child: AppIcons.render(sigilAsset, color: sigilColor, size: 60),
            ),
          ),
          const SizedBox(height: 20),
          // "{BODY PART} · RANK {N}" — body part + rank noun in cream,
          // numeral wrapped in RewardAccent. Rajdhani 700 24sp (28sp
          // overflows the 280dp card on long body-part names like
          // "SHOULDERS"). FittedBox guards against pt-BR strings that
          // run longer than en — the type scales down rather than wraps.
          // Phase 28a: routed through [AppTextStyles.celebrationSize] so
          // all three celebration overlays share one token. `height: 1.0`
          // is acceptable here because the FittedBox.scaleDown absorbs
          // the small leading delta from the previous `1.1`, and a
          // single-line Row inside a FittedBox derives its height from
          // the glyph extents rather than line-leading.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: DefaultTextStyle.merge(
              style: AppTextStyles.celebrationSize(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$bodyPartName · ${l10n.rankWord} ',
                    style: const TextStyle(color: AppColors.textCream),
                  ),
                  RewardAccent(child: Text('$rank')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _sigilAssetFor(BodyPart bodyPart) {
  switch (bodyPart) {
    case BodyPart.chest:
      return AppMuscleIcons.chest;
    case BodyPart.back:
      return AppMuscleIcons.back;
    case BodyPart.legs:
      return AppMuscleIcons.legs;
    case BodyPart.shoulders:
      return AppMuscleIcons.shoulders;
    case BodyPart.arms:
      return AppMuscleIcons.arms;
    case BodyPart.core:
      return AppMuscleIcons.core;
    case BodyPart.cardio:
      return AppMuscleIcons.cardio;
  }
}

// =============================================================================
// BUG-013 (Cluster 3) — Rank-up overflow flipbook
// =============================================================================

/// Mini-flipbook of three cycling muscle sigils + "+{N} ranks" label —
/// surfaces inside [`CelebrationOverflowCard`] when the cap-at-3 trims
/// rank-ups.
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
/// **Why this lives in the same file as [RankUpOverlay]:** they share the
/// muscle-icon vocabulary (`_sigilAssetFor`) and are both rank-up
/// presentation surfaces. Co-location keeps the icon-mapping refactor
/// (e.g. add a new sigil set for Phase 18g) trivial.
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
