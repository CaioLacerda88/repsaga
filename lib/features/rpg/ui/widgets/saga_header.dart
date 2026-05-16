import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/character_class.dart';
import '../../models/vitality_state.dart';
import 'class_localization.dart';
import 'rune_halo.dart';

/// Option B v4 three-column header for the Saga character sheet (Phase 26b).
///
/// Layout: 36dp rune halo (left) · 56sp LVL numeral + 10sp "LVL" tag stack
/// (center) · class name + title meta column (right, max 120dp, 1-line
/// ellipsis on each).
///
/// Replaces the legacy centered-rune + 56sp-LVL composition (the old
/// `_SheetHeader` private in `character_sheet_screen.dart`). The new layout
/// trims vertical chrome from ~200dp to ~80dp, freeing the screen for the
/// 6 stat rows.
///
/// **Class slot styling** follows the existing two-tier prestige rule from
/// `class_badge.dart`: `initiate` (the day-1 / still-on-the-way class)
/// renders in the quieter `primaryViolet` palette; the seven earned classes
/// render in `hotViolet`. The day-1 placeholder ("O ferro lhe dará um
/// nome." / "The iron will name you.") is italic when `characterClass` is
/// null.
class SagaHeader extends StatelessWidget {
  const SagaHeader({
    super.key,
    required this.haloState,
    required this.characterLevel,
    required this.characterClass,
    required this.activeTitle,
  });

  final VitalityState haloState;
  final int characterLevel;
  final CharacterClass? characterClass;
  final String? activeTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isStubClass = characterClass == null;
    final classLabel = isStubClass
        ? l10n.classSlotPlaceholder
        : localizedClassName(characterClass!, l10n);
    final hasTitle = activeTitle != null && activeTitle!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Column 1: 36dp rune.
          Semantics(
            container: true,
            identifier: 'rune-halo',
            child: RuneHalo(state: haloState, size: 36),
          ),
          const SizedBox(width: 16),
          // Column 2: 56sp level numeral + 10sp LVL tag.
          Semantics(
            container: true,
            identifier: 'character-level',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$characterLevel',
                  style: GoogleFonts.rajdhani(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textCream,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                // 'LVL' is a brand token, intentionally not localized per
                // Phase 26b spec. (Saga / Stats / Home all share this token;
                // routing it through AppLocalizations would invite per-locale
                // drift on a 3-char brand mark.)
                Text(
                  'LVL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Column 3: meta column (class + title), max 120dp + ellipsis.
          // Flexible (not Expanded) gives the ConstrainedBox loose
          // constraints so the maxWidth: 120 actually bites — Expanded would
          // force a tight width equal to the remaining row space, and
          // BoxConstraints.enforce can't relax tight constraints (it only
          // ADDS restrictions). With Flexible + ConstrainedBox the meta
          // column shrinks to its intrinsic width, capped at 120dp. On a
          // narrow viewport where remaining space is < 120, Flexible's loose
          // [0, available] constraint shrinks the column further so the row
          // never overflows.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    classLabel,
                    key: const ValueKey('saga-header-class'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: classTextColor(characterClass),
                      fontStyle: isStubClass
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasTitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      activeTitle!,
                      key: const ValueKey('saga-header-title'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textDim,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
