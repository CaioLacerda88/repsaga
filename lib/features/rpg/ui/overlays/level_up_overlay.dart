import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/reward_accent.dart';

/// Character level-up overlay (Phase 18c).
///
/// **Differentiation from [RankUpOverlay]** (locked):
///   * Glyph is the numeral itself (Rajdhani 700 64sp), no muscle icon —
///     character level is body-part-agnostic.
///   * Pure `heroGold` throughout — no settle into `hotViolet`. Character
///     level is cumulative, never resets, so it stays in the reward color.
///   * Entry axis: `SlideTransition` `Offset(0.08, 0)` → `Offset.zero`
///     (200ms `Curves.easeOutCubic`). Rank-up uses scale; level-up uses
///     slide so they read as different rewards even queued back-to-back.
///   * NO backdrop dim — stacking dim layers when already in queue is
///     oppressive.
///   * Haptic: `heavyImpact()` at t=0. Rank-up = medium at peak; level-up
///     = heavy at entry. Different feel, different layer.
///
/// All `heroGold` pixels flow through [RewardAccent].
class LevelUpOverlay extends StatefulWidget {
  const LevelUpOverlay({super.key, required this.newLevel});

  final int newLevel;

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    // Heavy haptic fires structurally on first frame — initState runs once
    // per widget instance, so re-fire is impossible without a remount.
    HapticFeedback.heavyImpact();

    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _entry, curve: Curves.easeOut);

    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      identifier: 'level-up-overlay',
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // ignore: reward_accent — overlay card is the level-up reward surface; BoxDecoration cannot route through RewardAccent.
                color: AppColors.heroGold.withValues(alpha: 0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  // ignore: reward_accent — gold halo is the level-up reward emission; BoxShadow cannot route through RewardAccent.
                  color: AppColors.heroGold.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The glyph IS the numeral. 64sp Rajdhani 700 in heroGold,
                // wrapped in RewardAccent so the gold pixel emission is
                // grouped with its narrative. Phase 28a: routed through
                // [AppTextStyles.celebrationSize] so all three celebration
                // overlays (level-up 64sp / class-change 36sp / rank-up 24sp)
                // share a single token for the "the surface IS the numeral"
                // register.
                RewardAccent(
                  child: Text(
                    '${widget.newLevel}',
                    style: AppTextStyles.celebrationSize(64),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  // l10n.levelUpHeading produces "LEVEL {n}" / "NÍVEL {n}";
                  // we already render the numeral in gold above, so this row
                  // shows only the noun in cream. Strip the numeral by
                  // splitting on the first digit.
                  _stripNumeral(l10n.levelUpHeading(widget.newLevel)),
                  style: AppTextStyles.headline.copyWith(
                    fontSize: 24,
                    color: AppColors.textCream,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns the localized "LEVEL" / "NÍVEL" prefix from a heading like
/// "LEVEL 3" — splits at the first digit and trims trailing whitespace.
/// Keeps the heading translatable without forcing a second arb key.
String _stripNumeral(String heading) {
  final firstDigit = heading.indexOf(RegExp(r'\d'));
  if (firstDigit < 0) return heading;
  return heading.substring(0, firstDigit).trim();
}
