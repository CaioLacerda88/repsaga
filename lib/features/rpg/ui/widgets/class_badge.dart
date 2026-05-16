import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/character_class.dart';
import 'class_localization.dart';

/// Style tokens for [ClassBadge] — two-tier prestige alpha values.
///
/// Public so widget tests can pin against [ClassBadgeStyle.initiateFillAlpha]
/// etc. instead of magic-numbering the assertions. A future palette rebalance
/// touches the constants here and the tests keep passing without re-hardcoding
/// values.
///
/// Initiate (quieter "still on the way"):
///   * Border: 40% primaryViolet
///   * Fill:   12% primaryViolet
///
/// Earned classes (Berserker through Ascendant):
///   * Border: 60% hotViolet
///   * Fill:   18% primaryViolet
class ClassBadgeStyle {
  const ClassBadgeStyle._();

  static const double initiateBorderAlpha = 0.4;
  static const double initiateFillAlpha = 0.12;
  static const double earnedBorderAlpha = 0.6;
  static const double earnedFillAlpha = 0.18;
}

/// Class slot — always rendered, even when no class has been derived yet.
///
/// Day-1 copy is "The iron will name you." (en) / "O ferro lhe dará um nome."
/// (pt-BR). The placeholder shows while [characterClass] is null — i.e. while
/// the upstream provider is in `AsyncLoading` / `AsyncError`. Once data
/// arrives, the badge transitions to the resolved class label (always
/// non-null on data, since the resolver returns [CharacterClass.initiate]
/// for the day-0 rank distribution). The transition is immediate — no
/// schema or layout change is required when class derivation engages.
///
/// **L10n contract.** The badge takes a [CharacterClass] enum and resolves
/// the localized label here via the per-class accessor on [AppLocalizations]
/// (one accessor per class slug — `classInitiate`, `classBerserker`, …).
/// Keeping the lookup at the badge means the upstream provider stays
/// l10n-free and the widget tests can assert against either the slug or
/// the localized string.
///
/// **Visual hierarchy — two-tier prestige (Phase 18e UX-critic pass).**
/// Initiate (the day-1 / "still on the way" class — every active rank ≤ 4)
/// renders in the quieter [primaryViolet] palette; the other seven derived
/// classes render in [hotViolet]. The reason: pre-tightening, every resolved
/// class shared the same hotViolet styling, which collapsed the prestige
/// curve — a 4-year balanced veteran's Ascendant looked identical to a
/// day-3 lifter's Initiate. Two tiers restore the "you're still on the way"
/// vs "you've arrived" distinction without introducing 8 separate palettes
/// (which would dilute the brand).
///
/// Detection is via [CharacterClass.initiate] enum equality, not a
/// rank-distribution re-derivation — the resolver already encodes the
/// "max rank < 5" floor, so checking the enum value is the same predicate
/// without the round-trip.
///
/// **Sigil corners.** The badge uses asymmetric [BorderRadius]
/// (top-left + bottom-right tight, top-right + bottom-left loose) so it
/// reads as a struck faction mark rather than a tappable Material chip.
/// Subtle enough not to scream "decorative" but distinct from the title
/// pill, ElevatedButton, OutlinedButton, and CardTheme — all of which
/// share the same 8–10dp circular rounding.
///
/// **Type scale.** The label uses [TextTheme.titleMedium] (~16sp Inter 600).
/// Sitting beneath a 56sp Rajdhani LVL numeral, [titleSmall] (~14sp) was
/// reading as metadata rather than as the second identity beat. Bumping
/// one step up the scale restores the intended hierarchy: LVL > class >
/// title pill.
class ClassBadge extends StatelessWidget {
  const ClassBadge({super.key, required this.characterClass});

  /// The currently-derived class. `null` on the day-1 placeholder
  /// (provider still loading or errored). Once data lands, the resolver
  /// always returns a non-null variant — there is no "unclassified" state.
  final CharacterClass? characterClass;

  /// Sigil corners: top-left + bottom-right tight (4dp), top-right +
  /// bottom-left loose (10dp). The asymmetry is the only thing
  /// differentiating this from a Material chip — keep both numbers stable
  /// so `class_badge_test.dart` can assert on them.
  static const _sigilRadius = BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(10),
    bottomLeft: Radius.circular(10),
    bottomRight: Radius.circular(4),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cls = characterClass;

    final isStub = cls == null;
    final isInitiate = cls == CharacterClass.initiate;
    final label = isStub
        ? l10n.classSlotPlaceholder
        : localizedClassName(cls, l10n);

    // Text color comes from the shared two-tier helper so the saga header
    // and the badge stay in lockstep on a future palette rebalance.
    final textColor = classTextColor(cls);
    final Color borderColor;
    final Color fillColor;
    if (isStub) {
      borderColor = AppColors.hair;
      fillColor = AppColors.surface;
    } else if (isInitiate) {
      // Quieter "still on the way" palette: initiate-tier border/fill alphas
      // on primaryViolet. Keeps Initiate legibly Arcane-Ascent-branded
      // without competing with the seven earned classes for visual prestige.
      borderColor = AppColors.primaryViolet.withValues(
        alpha: ClassBadgeStyle.initiateBorderAlpha,
      );
      fillColor = AppColors.primaryViolet.withValues(
        alpha: ClassBadgeStyle.initiateFillAlpha,
      );
    } else {
      // Earned-class palette: earned-tier border + 18% primaryViolet fill.
      // Reserved for the seven classes a user unlocks after crossing rank 5
      // in some body part.
      borderColor = AppColors.hotViolet.withValues(
        alpha: ClassBadgeStyle.earnedBorderAlpha,
      );
      fillColor = AppColors.primaryViolet.withValues(
        alpha: ClassBadgeStyle.earnedFillAlpha,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: borderColor),
        borderRadius: _sigilRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          color: textColor,
          fontStyle: isStub ? FontStyle.italic : FontStyle.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
