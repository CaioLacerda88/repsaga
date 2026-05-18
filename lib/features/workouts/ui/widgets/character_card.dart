import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/models/character_sheet_state.dart';
import '../../../rpg/providers/character_sheet_provider.dart';
import '../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../rpg/ui/widgets/body_part_localization.dart';
import '../../../rpg/ui/widgets/class_localization.dart';
import '../../../rpg/ui/widgets/rune_halo.dart';
import '../../domain/closest_rank_up.dart';

/// Phase 26f Home character card — tappable expanding surface that replaces
/// the body-part rank chip rail.
///
/// **T7 (this commit): expand/collapse interaction wired.** Tap toggles
/// `_expanded`; chevron rotates 90° via [AnimatedRotation]; closest-rank-up
/// indicator is gated out when expanded. Inner column wrapped in
/// [AnimatedSize] (250ms easeOut) so future expanded-body content (T8)
/// grows/shrinks smoothly. T6's plumbing kept intact — `_expanded` flows
/// through `_CardBody` → `_HeaderRow` (chevron) and is the gate for the
/// `_ClosestRankUpRow`. T8 will append the expanded body (XP bar + 6 stat
/// rows) inside the same [AnimatedSize].
///
/// **Why ConsumerStatefulWidget:** the expand state is local to this card
/// instance and intentionally NOT persisted across launches (PROJECT.md 26f
/// acceptance: "always opens collapsed"). Holding the flag in a Riverpod
/// provider would survive app restarts and add a needless rebuild hop.
///
/// **L10n strategy.** Single-use widget mounted only on the home screen —
/// reads [AppLocalizations.of] inline. See
/// `feedback_widget_l10n_parameterization`: reusable widgets take localized
/// strings as constructor params; screen-bound widgets can read l10n
/// directly. The same rule applies to the inner private widgets here —
/// they are tightly coupled to the card and not exported.
class CharacterCard extends ConsumerStatefulWidget {
  const CharacterCard({super.key});

  @override
  ConsumerState<CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends ConsumerState<CharacterCard> {
  /// Local-only flag (T7). Intentionally NOT persisted — PROJECT.md §3 26f
  /// "always opens collapsed". Hoisting this into a Riverpod provider would
  /// survive restarts and add a needless rebuild hop. T8 will gate the
  /// expanded body (`if (_expanded) ...`) inside the [AnimatedSize] in
  /// [_CardBody].
  // ignore: prefer_final_fields
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sheetAsync = ref.watch(characterSheetProvider);

    return sheetAsync.when(
      loading: () => const _CharacterCardSkeleton(),
      // Day-0 / fresh-account error states render as a blank skeleton so
      // home layout doesn't pop. Errors are surfaced via Saga / Stats — the
      // home card is a glanceable affordance, not the primary diagnostic
      // surface.
      error: (_, _) => const _CharacterCardSkeleton(),
      data: (sheet) => _CardBody(
        sheet: sheet,
        expanded: _expanded,
        onTap: () => setState(() => _expanded = !_expanded),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.sheet,
    required this.expanded,
    required this.onTap,
  });

  final CharacterSheetState sheet;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'home-character-card',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kRadiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadiusLg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            // 250ms easeOut height tween (PROJECT.md §3 26f). Anchored
            // top-center so the header stays planted while the body grows
            // downward — the home layout reads as the card "opening" rather
            // than the whole tile shifting. T8's expanded body will live
            // inside this same Column.
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderRow(sheet: sheet, expanded: expanded),
                  // T8 will insert the expanded body (XP bar + 6 stat rows)
                  // here when `expanded == true`. The closest-rank-up row is
                  // hidden once expanded — the stat rows render the same
                  // information in higher fidelity.
                  if (!expanded) ...[
                    const SizedBox(height: 12),
                    _ClosestRankUpRow(sheet: sheet),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 3-column header: 40dp rune (left) · level + class + title (center) ·
/// dominant rank chip (right) + chevron.
///
/// Mirrors the Saga character-sheet header structure (`SagaHeader`) but at a
/// compact register: 40dp rune (vs 36dp on Saga), 28sp Rajdhani LVL numeral
/// (vs 56sp), 10sp UPPERCASE class label (same), bodySmall title (same). The
/// dominant rank column on the right is new for Home — it surfaces the
/// user's strongest track at a glance without expanding the card.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.sheet, required this.expanded});

  final CharacterSheetState sheet;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isStubClass = sheet.characterClass == null;
    final classLabel = isStubClass
        ? l10n.classSlotPlaceholder
        : localizedClassName(sheet.characterClass!, l10n);
    final hasTitle = sheet.activeTitle != null && sheet.activeTitle!.isNotEmpty;
    final dominant = _dominantTrainedEntry(sheet);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Column 1: 40dp rune halo. Below RuneHalo's 48dp compact threshold,
        // so the static states render with the compact glow-pad (Phase 26b
        // retrospective: prevents the legacy +60dp glow from blowing out the
        // home card's vertical rhythm).
        RuneHalo(state: sheet.haloState, size: 40),
        const SizedBox(width: 12),
        // Column 2: level numeral + LVL tag + class label + title.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Inline LVL line: 28sp Rajdhani numeral + 10sp brand tag.
              // 'LVL' is a brand token, intentionally not localized — mirrors
              // SagaHeader's choice so the marker stays stable across Saga /
              // Stats / Home (no per-locale drift on a 3-char mark).
              Semantics(
                container: true,
                identifier: 'home-character-card-level',
                label: 'Lvl ${sheet.characterLevel}',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${sheet.characterLevel}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textCream,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
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
              const SizedBox(height: 4),
              // Class label — UPPERCASE earned class names, lowercase + italic
              // day-1 placeholder. Mirrors SagaHeader's classSlotPlaceholder
              // treatment so the two surfaces (Saga + Home) read consistently.
              Text(
                isStubClass ? classLabel : classLabel.toUpperCase(),
                key: const ValueKey('character-card-class'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: classTextColor(sheet.characterClass),
                  letterSpacing: 1.8,
                  fontStyle: isStubClass ? FontStyle.italic : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasTitle) ...[
                const SizedBox(height: 2),
                Text(
                  sheet.activeTitle!,
                  key: const ValueKey('character-card-title'),
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
        // Column 3: dominant rank + body-part name in hue. Only renders
        // when at least one body part has been trained — day-0 users get a
        // sized gap that keeps the chevron right-anchored without the column
        // collapsing visually.
        if (dominant != null) ...[
          const SizedBox(width: 8),
          _DominantColumn(entry: dominant),
        ],
        const SizedBox(width: 8),
        _Chevron(expanded: expanded, hint: l10n.homeCharacterCardChevronHint),
      ],
    );
  }

  /// Dominant = the highest-ranked trained body part. Tie-break by canonical
  /// [activeBodyParts] order (chest → back → legs → shoulders → arms → core),
  /// matching the determinism contract on [closestRankUp]. Returns null when
  /// every active body part is untrained (day-0 user).
  BodyPartSheetEntry? _dominantTrainedEntry(CharacterSheetState sheet) {
    BodyPartSheetEntry? best;
    for (final e in sheet.bodyPartProgress) {
      if (e.isUntrained) continue;
      if (best == null || e.rank > best.rank) best = e;
    }
    return best;
  }
}

/// Right-column chip: rank num stacked over body-part name, both rendered
/// in the body-part hue. Mirrors the mockup's `cc-dom` column — the
/// "Dominante" label is intentionally omitted so this column does not
/// require a new l10n key (T1 only authorized closest-rank-up + chevron
/// hint + first-step keys). The visual reads unambiguously as "dominant"
/// via the heavy 28sp body-part-colored numeral.
class _DominantColumn extends StatelessWidget {
  const _DominantColumn({required this.entry});

  final BodyPartSheetEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color =
        VitalityStateStyles.bodyPartColor[entry.bodyPart] ?? AppColors.textDim;
    final bodyPartName = localizedBodyPartName(entry.bodyPart, l10n);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${entry.rank}',
          key: const ValueKey('character-card-dominant-rank'),
          style: GoogleFonts.rajdhani(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          bodyPartName,
          key: const ValueKey('character-card-dominant-name'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Closest-rank-up indicator row. Renders the localized template
/// `'◆ {bodyPart} · {xp} XP for rank {rank}'` (en) / `'◆ {bodyPart} · {xp}
/// XP p/ rank {rank}'` (pt). The diamond glyph lives in the ARB string —
/// not a separate icon — so the leading `◆` is tinted in the body-part hue
/// via a [Text.rich] split on the first three characters.
///
/// Falls back to the day-0 first-step copy when [closestRankUp] returns
/// null (every active body part untrained or every trained part at max
/// rank — the latter is an end-game state but the same fallback applies).
class _ClosestRankUpRow extends StatelessWidget {
  const _ClosestRankUpRow({required this.sheet});

  final CharacterSheetState sheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final closest = closestRankUp(sheet.bodyPartProgress);

    if (closest == null) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'home-closest-rank-up',
        child: Text(
          l10n.homeFirstStepFallback,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim),
        ),
      );
    }

    final color =
        VitalityStateStyles.bodyPartColor[closest.bodyPart] ??
        AppColors.textDim;
    final bodyPartName = localizedBodyPartName(closest.bodyPart, l10n);
    // Gap rounded UP — the user needs at least this many XP to cross the
    // next rank threshold. `.ceil()` matches the user-facing semantics of
    // "X XP for rank Y" (you cannot half-clear a threshold).
    final xpToRank = (closest.xpForNextRank - closest.xpInRank).clamp(
      0.0,
      double.infinity,
    );
    final fullLine = l10n.homeClosestRankUp(
      bodyPartName,
      xpToRank.ceil(),
      closest.rank + 1,
    );
    // The ARB template starts with `◆ ` — split the leading two chars off
    // so the diamond glyph renders in the body-part hue while the rest of
    // the line stays at the muted body-text color. Tests pin the merged
    // text via `find.text(fullLine)`, which still resolves because
    // `Text.rich` exposes a joined `data` to the AOM.
    const diamondPrefix = '◆ ';
    final remainder = fullLine.startsWith(diamondPrefix)
        ? fullLine.substring(diamondPrefix.length)
        : fullLine;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'home-closest-rank-up',
      child: Text.rich(
        TextSpan(
          children: [
            if (fullLine.startsWith(diamondPrefix))
              TextSpan(
                text: diamondPrefix,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            TextSpan(
              text: remainder,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.expanded, required this.hint});

  final bool expanded;
  final String hint;

  @override
  Widget build(BuildContext context) {
    // Single icon (`chevron_right`) rotated 90° via [AnimatedRotation] when
    // expanded — turns 0 (›) → 0.25 (⌄). Using one icon + rotation (rather
    // than swapping `chevron_right` ↔ `expand_more`) makes the animation
    // continuous and gives tests a stable `find.byIcon(Icons.chevron_right)`
    // anchor across both states. 250ms easeOut matches the [AnimatedSize]
    // body tween so the chevron's spin lands when the card finishes growing.
    return Semantics(
      label: hint,
      child: AnimatedRotation(
        turns: expanded ? 0.25 : 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: const Icon(
          Icons.chevron_right,
          color: AppColors.textDim,
          size: 24,
        ),
      ),
    );
  }
}

/// Loading placeholder. Reserves the collapsed-state height (~118dp) so the
/// home layout doesn't pop when sheet data lands. Surface tone matches the
/// real card (`AppColors.surface`) to avoid a flicker on hydrate.
class _CharacterCardSkeleton extends StatelessWidget {
  const _CharacterCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kRadiusLg),
      ),
    );
  }
}
