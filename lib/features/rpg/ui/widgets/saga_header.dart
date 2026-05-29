import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/character_class.dart';
import '../../models/vitality_state.dart';
import 'class_localization.dart';
import 'rune_halo.dart';
import 'title_localization.dart';

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
          // Column 1: 44dp rune wrapped as a tappable target that navigates
          // to Profile Settings (Phase 32 PR 32e scope add — per UX-critic
          // memo). Tap routes to `/profile/settings`, NOT directly to the
          // upload picker — the halo is a read-anchor RPG signal, not an
          // edit surface, and the upload UI is already purpose-built on the
          // IdentityCard. The 'rune-halo' identifier stays (referenced by
          // existing E2E specs); button:true + explicitChildNodes:true added
          // per cluster_semantics_identifier_pair_rule so the AOM exposes
          // the GestureDetector as a tappable target. Size bumped 36→44 to
          // match Home's 48dp register while staying within the Saga
          // header's vertical rhythm. Still below RuneHalo's bumped 52dp
          // compact threshold so static states keep the compact glow-pad.
          Semantics(
            container: true,
            explicitChildNodes: true,
            identifier: 'rune-halo',
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/profile/settings'),
              child: RuneHalo(state: haloState, size: 44),
            ),
          ),
          const SizedBox(width: 16),
          // Column 2: 56sp level numeral + 10sp LVL tag.
          //
          // Explicit `label: 'Lvl $characterLevel'` is required so the AOM
          // exposes a single, parseable accessible name. Without it Flutter
          // merges the two child Texts as "$N\nLVL" — breaking both the
          // Phase 18b `readLvlFromCharacterSheet` helper (regex `/Lvl (\d+)/`)
          // and the saga.spec.ts S2 parser (`.replace(/^Lvl\s*/, '')`).
          // Pattern mirrors `saga-settings-btn` in character_sheet_screen.dart.
          Semantics(
            container: true,
            identifier: 'character-level',
            label: 'Lvl $characterLevel',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$characterLevel',
                  // Hero-scale character-level numeral. 56dp is larger
                  // than any token in [AppTextStyles], so we layer on
                  // top of [AppTextStyles.numeric] (Rajdhani 700 tabular)
                  // — same family + weight + tabular figures + textCream
                  // color, just upsized. Stays one route through the
                  // sanctioned token so the typography call-site CI gate
                  // doesn't trip on a raw `fontFamily: 'Rajdhani'`.
                  style: AppTextStyles.numeric.copyWith(
                    fontSize: 56,
                    height: 1,
                  ),
                ),
                // 'LVL' is a brand token, intentionally not localized per
                // Phase 26b spec. (Saga / Stats / Home all share this token;
                // routing it through AppLocalizations would invite per-locale
                // drift on a 3-char brand mark.)
                Text(
                  'LVL',
                  style: AppTextStyles.label.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AppColors.textDim,
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
                  // ValueKey for widget tests; Semantics identifier for E2E
                  // selectors — both serve as stable anchors so neither has
                  // to be duplicated into the other test layer.
                  Semantics(
                    container: true,
                    identifier: 'saga-header-class',
                    // Mockup spec: 10sp UPPERCASE class label with
                    // letterSpacing 1.8 (0.18em in CSS). The 14sp Inter
                    // sentence-case `titleSmall` we shipped first visually
                    // competed with the 56sp LVL numeral; the spec's tracked-
                    // out UPPERCASE rendering makes the class subordinate.
                    //
                    // Day-1 placeholder stays lowercase + italic: it reads
                    // as a soft "still on the way" prompt — UPPERCASING the
                    // phrase "O ferro lhe dará um nome." / "The iron will
                    // name you." would read as shouting and break the tone.
                    // The seven earned class names ("Baluarte", "Sentinela",
                    // etc.) DO render uppercase per the mockup.
                    child: Text(
                      isStubClass ? classLabel : classLabel.toUpperCase(),
                      key: const ValueKey('saga-header-class'),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.8,
                        color: classTextColor(characterClass),
                        fontStyle: isStubClass
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasTitle) ...[
                    const SizedBox(height: 2),
                    // ValueKey for widget tests; Semantics identifier for E2E.
                    // Replaces the legacy ActiveTitlePill identifier.
                    //
                    // `activeTitle` is the raw slug from `earned_titles.title_id`
                    // (e.g. `chest_r5_initiate_of_the_forge`). Resolve through
                    // `localizedTitleCopy` before rendering; fall back to the
                    // slug if a future DB title lacks an l10n entry (preferable
                    // to a crash). See `cluster_slug_rendered_as_display_name`.
                    Semantics(
                      container: true,
                      identifier: 'saga-header-title',
                      child: Text(
                        localizedTitleCopy(activeTitle!, l10n)?.name ??
                            activeTitle!,
                        key: const ValueKey('saga-header-title'),
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
