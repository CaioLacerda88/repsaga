import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/character_sheet_state.dart';
import '../../../rpg/providers/character_sheet_provider.dart';
import '../../../rpg/ui/utils/vitality_state_styles.dart';
import '../../../rpg/ui/widgets/body_part_localization.dart';
import '../../../rpg/ui/widgets/body_part_rank_row.dart';
import '../../../rpg/ui/widgets/cardio_progress_row.dart';
import '../../../rpg/ui/widgets/character_xp_bar.dart';
import '../../../rpg/ui/widgets/class_localization.dart';
import '../../../rpg/ui/widgets/rune_halo.dart';
import '../../../rpg/ui/widgets/title_localization.dart';
import '../../domain/closest_rank_up.dart';

/// Phase 26f Home character card — tappable expanding surface that replaces
/// the body-part rank chip rail.
///
/// **Collapsed state.** Header (40dp rune · level/class/title meta · dominant
/// rank chip · chevron) + the closest-rank-up indicator row.
///
/// **Expanded state.** Header + 1dp hair divider + [CharacterXpBar] +
/// 6 [BodyPartRankRow] widgets in canonical order
/// (chest → back → legs → shoulders → arms → core). The closest-rank-up
/// indicator is hidden in expanded state — the stat rows render the same
/// information in higher fidelity. Each row is `InkWell`-tappable and
/// `context.push`-es to `/saga/stats?body_part=<dbValue>`; that contract
/// lives inside [BodyPartRankRow] (reused verbatim from Saga).
///
/// **Why reuse [BodyPartRankRow] verbatim.** The Saga character sheet
/// renders the identical row spec (Option B v4 — 6dp dot · UPPERCASE name
/// · rank num · 4dp bar · 9sp XP labels). Reusing the widget means the
/// Home expanded view stays visually identical to Saga without two copies
/// of the row to keep in sync. The widget already watches
/// `rankUpPulseLocalStorageProvider` for the 24h glow-ring overlay — that
/// behavior carries over to the home card automatically.
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
  /// Local-only flag. Intentionally NOT persisted — PROJECT.md §3 26f
  /// "always opens collapsed". Hoisting this into a Riverpod provider would
  /// survive restarts and add a needless rebuild hop. Gates the expanded
  /// body (XP bar + 6 stat rows) inside the [AnimatedSize] in [_CardBody].
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
    // Tap scope: ONLY the header + closest-rank-up row act as the
    // toggle target. The expanded body sits OUTSIDE the outer InkWell —
    // each `BodyPartRankRow` owns its own InkWell that deep-links to
    // `/saga/stats?body_part=<slug>`. Nesting the row InkWells inside
    // an outer InkWell would have the outer one intercept taps before
    // they reached the rows (Material InkWells don't claim gestures
    // from descendants — the outermost handler wins on hit-test), and
    // the user would see the card collapse instead of navigating.
    // Splitting the tap surface preserves both interactions cleanly.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'home-character-card',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kRadiusLg),
        // 250ms easeOut height tween (PROJECT.md §3 26f). Anchored
        // top-center so the header stays planted while the body grows
        // downward — the home layout reads as the card "opening" rather
        // than the whole tile shifting.
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header tap zone: toggles expanded state. Includes the
              // header row + the closest-rank-up indicator (when
              // collapsed) so the whole collapsed surface is tappable.
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(kRadiusLg),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, expanded ? 8 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HeaderRow(sheet: sheet, expanded: expanded),
                      // Collapsed only: closest-rank-up indicator. In the
                      // expanded state the stat rows below render the same
                      // information in higher fidelity, so the indicator
                      // would duplicate the data.
                      if (!expanded) ...[
                        const SizedBox(height: 12),
                        _ClosestRankUpRow(sheet: sheet),
                      ],
                    ],
                  ),
                ),
              ),
              // Expanded body sits OUTSIDE the InkWell so its child row
              // InkWells receive taps without the outer toggle intercept.
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    identifier: 'home-character-card-expanded',
                    child: _ExpandedBody(sheet: sheet),
                  ),
                ),
            ],
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
        // Column 1: 48dp rune halo wrapped as a tappable target that
        // navigates to Profile Settings (Phase 32 PR 32e scope add — per
        // UX-critic memo: improve discoverability of the upload flow without
        // inviting accidental taps in workout context). Tap routes to
        // `/profile/settings`, NOT directly to the upload picker — the halo
        // is a read-anchor RPG signal, not an edit surface, and the upload
        // UI is already purpose-built on the IdentityCard. No badge inside
        // the compact halo (would visually compete with the glow signal).
        //
        // Size bumped 40→48 to match the Pokemon GO trainer-figure register
        // (the closest RPG-conditioning-photo analogue) while staying within
        // the card's column budget. Still below RuneHalo's bumped 52dp
        // compact threshold so static states keep the compact glow-pad.
        //
        // Semantics: identifier 'home-character-avatar' + button:true +
        // explicitChildNodes:true per cluster_semantics_identifier_pair_rule
        // — the inner ProfileAvatar's own Semantics nodes must not interfere
        // with the AOM exposing this as a tappable target.
        Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'home-character-avatar',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/profile/settings'),
            child: RuneHalo(state: sheet.haloState, size: 48),
          ),
        ),
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
                explicitChildNodes: true,
                identifier: 'home-character-card-level',
                label: 'Lvl ${sheet.characterLevel}',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${sheet.characterLevel}',
                      // Character-level numeral, collapsed card. Routed
                      // through [AppTextStyles.numeric] with the card-
                      // specific 28dp size override.
                      style: AppTextStyles.numeric.copyWith(fontSize: 28),
                    ),
                    const SizedBox(width: 6),
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
              const SizedBox(height: 4),
              // Class label — UPPERCASE earned class names, lowercase + italic
              // day-1 placeholder. Mirrors SagaHeader's classSlotPlaceholder
              // treatment so the two surfaces (Saga + Home) read consistently.
              Text(
                isStubClass ? classLabel : classLabel.toUpperCase(),
                key: const ValueKey('character-card-class'),
                style: AppTextStyles.label.copyWith(
                  fontSize: 10,
                  letterSpacing: 1.8,
                  color: classTextColor(sheet.characterClass),
                  fontStyle: isStubClass ? FontStyle.italic : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasTitle) ...[
                const SizedBox(height: 4),
                // `sheet.activeTitle` is the raw slug from
                // `earned_titles.title_id` (e.g. `chest_r5_initiate_of_the_forge`).
                // It MUST be resolved through `localizedTitleCopy` before
                // rendering. The `?? sheet.activeTitle!` fallback is
                // intentional: a freshly-shipped DB title without an l10n
                // entry should degrade to the slug rather than crash. See
                // `cluster_slug_rendered_as_display_name`.
                //
                // L12 (Phase 27, 2026-05-19) — wrap the resolved title in
                // a neutral pill chip matching mockup `.cc-title-pill`:
                //   background: var(--surface2)     ⇒ AppColors.surface2
                //   border-radius: 10px             ⇒ BorderRadius.circular(10)
                //   padding: 3px 8px                ⇒ EdgeInsets.symmetric(8,3)
                //   display: inline-block           ⇒ Align(start) + min-width
                //
                // The pill is intentionally single-style (no tier variants)
                // — mockup uses one neutral surface tone for every equipped
                // title. The `Align(centerStart)` + `Container` pair keeps
                // the pill from stretching to the column's full width:
                // without it the Column's stretch crossAxis would force the
                // pill into a full-row strip.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _TitlePill(
                    label:
                        localizedTitleCopy(sheet.activeTitle!, l10n)?.name ??
                        sheet.activeTitle!,
                  ),
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

  /// Dominant = the highest-ranked trained STRENGTH body part. Cardio is
  /// excluded: identity (dominant-chip + class-pin) stays pure 6-strength —
  /// cardio is a separate track recognized via titles, not an identity
  /// (locked scope decision). Tie-break by canonical [strengthBodyParts]
  /// order (chest → back → legs → shoulders → arms → core), matching the
  /// determinism contract on [closestRankUp]. Returns null when every
  /// strength body part is untrained (day-0 user).
  BodyPartSheetEntry? _dominantTrainedEntry(CharacterSheetState sheet) {
    BodyPartSheetEntry? best;
    for (final e in sheet.bodyPartProgress) {
      if (e.bodyPart == BodyPart.cardio) continue; // identity = strength-only
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
          // Dominant body-part rank numeral. Routed through
          // [AppTextStyles.numeric] with the card's 28dp size +
          // body-part hue color overrides.
          style: AppTextStyles.numeric.copyWith(fontSize: 28, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          bodyPartName,
          key: const ValueKey('character-card-dominant-name'),
          style: AppTextStyles.label.copyWith(
            fontSize: 10,
            letterSpacing: 1.2,
            color: color,
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
    final l10n = AppLocalizations.of(context);
    final closest = closestRankUp(sheet.bodyPartProgress);

    // Phase 28a: collapsed the 5-property override stack into the canonical
    // [AppTextStyles.numericSmall] token (Rajdhani 600 / 11dp / textDim /
    // 0.04em tracking, tabular figures inherited from `numeric`). The
    // emphasized fragment below flips `color` to `textCream` via copyWith.
    final fallbackStyle = AppTextStyles.numericSmall;

    if (closest == null) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: 'home-closest-rank-up',
        child: Text(l10n.homeFirstStepFallback, style: fallbackStyle),
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
    // The ARB template starts with `◆ ` then the body-part name then a
    // `· {xp} XP ...` tail. We slice into three spans so the diamond stays
    // in the body-part hue, the body-part name takes the bold-cream
    // emphasis (mockup `.cc-closest .indicator strong`), and the tail
    // stays muted. Tests pin the merged text via `find.text(fullLine)`,
    // which still resolves because `Text.rich` exposes a joined `data` to
    // the AOM. The bold-cream fragment is the body-part name — locate it
    // in the rendered line via `String.indexOf` so locale-driven word
    // order changes still work (defensive fallback to whole-line if not
    // found).
    //
    // L11.b (Phase 27, 2026-05-19) — adds the bold-cream body-part span.
    const diamondPrefix = '◆ ';
    // Use the same Rajdhani 600 11px baseline as the fallback line above —
    // mockup `.cc-closest .indicator` is the same style for both branches.
    // Bold span lifts to w700 + textCream so the body-part name reads as
    // distinct emphasis (matches L11.b's original contract pinned by tests).
    // `final` (was `const`) because L18.4 routed `fallbackStyle` through
    // `AppTextStyles.numeric.copyWith(...)` which is not a const expression.
    final baseStyle = fallbackStyle;
    final boldStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.textCream,
    );
    final diamondStyle = baseStyle.copyWith(color: color);
    // Body-part name lookup starts AFTER the diamond prefix (skips the
    // glyph) and bails to a single muted span if the name isn't present
    // — should never happen since we generate the line from this same
    // name, but the fallback keeps the row rendering instead of crashing.
    final nameStart = fullLine.indexOf(
      bodyPartName,
      fullLine.startsWith(diamondPrefix) ? diamondPrefix.length : 0,
    );
    final spans = <TextSpan>[];
    if (fullLine.startsWith(diamondPrefix)) {
      spans.add(TextSpan(text: diamondPrefix, style: diamondStyle));
    }
    if (nameStart >= 0) {
      final headEnd = nameStart;
      final tailStart = nameStart + bodyPartName.length;
      // `head` covers anything between the diamond prefix and the body-
      // part name (typically empty for both en/pt; the diamond prefix
      // sits flush against the name).
      final headStart = fullLine.startsWith(diamondPrefix)
          ? diamondPrefix.length
          : 0;
      if (headEnd > headStart) {
        spans.add(
          TextSpan(
            text: fullLine.substring(headStart, headEnd),
            style: baseStyle,
          ),
        );
      }
      spans.add(TextSpan(text: bodyPartName, style: boldStyle));
      if (tailStart < fullLine.length) {
        spans.add(
          TextSpan(text: fullLine.substring(tailStart), style: baseStyle),
        );
      }
    } else {
      // Defensive: body-part name not found in the rendered string. Fall
      // back to a single muted span carrying everything after the diamond
      // prefix.
      final remainder = fullLine.startsWith(diamondPrefix)
          ? fullLine.substring(diamondPrefix.length)
          : fullLine;
      spans.add(TextSpan(text: remainder, style: baseStyle));
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'home-closest-rank-up',
      child: Text.rich(
        TextSpan(children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Phase 27 L12 pill chip wrapping the active title on the character card
/// header. Mockup `.cc-title-pill`:
///
///   background: var(--surface2)   ⇒ AppColors.surface2 (#241640)
///   padding: 3px 8px              ⇒ EdgeInsets.symmetric(8,3)
///   border-radius: 10px           ⇒ BorderRadius.circular(10)
///   font-size: 9px                ⇒ labelSmall + letterSpacing 1.2
///   color: var(--text-dim)        ⇒ AppColors.textDim
///   text-transform: uppercase     ⇒ `.toUpperCase()` on the label
///
/// Single neutral style — the mockup does not vary the background per
/// title tier; the surface2 fill reads as a quiet badge against the
/// surrounding `AppColors.surface` card. The label uppercases the
/// localized title because the mockup specifies `text-transform: uppercase`
/// + 0.14em letter-spacing — a tracked-out brand-badge treatment. UPPER
/// is done here (presentation) not in the localization layer because the
/// raw localized string still flows unchanged into accessibility / clipboard
/// copy paths. `ValueKey('character-card-title')` stays on the inner Text
/// so existing widget tests anchored to that key (ellipsis + slug-resolution
/// pins) keep resolving.
class _TitlePill extends StatelessWidget {
  const _TitlePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label.toUpperCase(),
        key: const ValueKey('character-card-title'),
        style: AppTextStyles.label.copyWith(
          fontSize: 9,
          letterSpacing: 1.2,
          color: AppColors.textDim,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Expanded body — 1dp hair divider, character XP bar, and 6 body-part rank
/// rows in canonical order. Mounted only when `_expanded == true`; the
/// [AnimatedSize] parent owns the open/close height tween.
///
/// `sheet.bodyPartProgress` is built by `character_sheet_provider` in
/// `activeBodyParts` order (chest → back → legs → shoulders → arms → core),
/// so a `for` loop over the list reproduces the canonical order without a
/// client-side sort. `BodyPartRankRow` decides internally whether to render
/// the trained or untrained variant (`entry.isUntrained` ⇒ dimmed `—`),
/// so this widget passes every entry through unconditionally — including
/// day-0 sheets where every body part is untrained.
class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({required this.sheet});

  final CharacterSheetState sheet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1dp hair divider separates the header section from the expanded
        // body. `AppColors.hair` (rgba(179,109,255,0.14)) matches the
        // `--hair` token used in the mockup. `Divider`'s 24dp height
        // provides the 12dp vertical padding above + below the line.
        const Divider(height: 24, thickness: 1, color: AppColors.hair),
        CharacterXpBar(
          lifetimeXp: sheet.lifetimeXp,
          xpForNextLevel: sheet.xpForNextLevel,
          characterLevel: sheet.characterLevel,
        ),
        const SizedBox(height: 16),
        // Six strength rows (Phase 38e: cardio is excluded here and rendered
        // as the banded CardioProgressRow below — mirrors the Saga sheet's
        // separate-but-equal grouping so both surfaces read identically).
        for (final entry in sheet.bodyPartProgress)
          if (entry.bodyPart != BodyPart.cardio)
            Padding(
              // 4dp inter-row gap — `BodyPartRankRow` already owns a 48dp
              // min-height tap target and its own 8dp/12dp vertical padding,
              // so this is purely visual breathing room between rows.
              padding: const EdgeInsets.only(bottom: 4),
              child: BodyPartRankRow(entry: entry),
            ),
        // Grouped-apart cardio track.
        for (final entry in sheet.bodyPartProgress)
          if (entry.bodyPart == BodyPart.cardio) ...[
            const SizedBox(height: 4),
            const Divider(height: 1, thickness: 1, color: AppColors.surface2),
            const SizedBox(height: 8),
            CardioProgressRow(
              entry: entry,
              trackLabel: AppLocalizations.of(context).cardioTrackLabel,
              eyebrowLabel: AppLocalizations.of(context).muscleGroupCardio,
            ),
          ],
      ],
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
