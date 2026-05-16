import 'package:flutter/material.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/theme/app_theme.dart';

/// Character XP bar shown beneath the Saga header (Phase 26b).
///
/// 6dp track with a violet gradient fill + a two-column label row below:
///   * Left: "{lifetimeXp} XP"
///   * Right: "{xpForNextLevel - lifetimeXp} para LVL {characterLevel + 1}"
///
/// Spec source: docs/PROJECT.md §3 Phase 26 → 26b acceptance criteria. The
/// underlying fraction uses the single-body-part approximation owned by
/// `domain/character_xp_calculator.dart` (`xpForNextCharacterLevel`) — this
/// widget is pure presentation.
class CharacterXpBar extends StatelessWidget {
  const CharacterXpBar({
    super.key,
    required this.lifetimeXp,
    required this.xpForNextLevel,
    required this.characterLevel,
  });

  /// Lifetime XP accumulated. Bar numerator.
  final double lifetimeXp;

  /// Cheapest lifetime XP at which the next character level becomes
  /// reachable. Bar denominator. Invariant: `>= lifetimeXp`.
  final double xpForNextLevel;

  /// Current character level. The right-side label reads
  /// `Y para LVL <characterLevel + 1>`.
  final int characterLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final fraction = xpForNextLevel <= lifetimeXp
        ? 1.0
        : (lifetimeXp / xpForNextLevel).clamp(0.0, 1.0);
    final remaining = (xpForNextLevel - lifetimeXp).clamp(0.0, double.infinity);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: AppColors.xpTrack,
              child: FractionallySizedBox(
                key: const ValueKey('character-xp-bar-fill'),
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primaryViolet, AppColors.hotViolet],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${AppNumberFormat.volume(lifetimeXp, locale: locale)} XP',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                // Suffix "para LVL N" is identical across en + pt in spec
                // text for this transitional release. If localization grows,
                // swap to an AppLocalizations entry.
                '${AppNumberFormat.volume(remaining, locale: locale)} '
                'para LVL ${characterLevel + 1}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.hotViolet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
